# Kubernetes Decision Record

Why the manifests look the way they do.

Same shape as every entry in `terraform/DECISIONS.md`: **situation**, **decision**, **why**,
**what it costs**. That last line matters most — a decision with no downside is usually one
that has not been thought about, and "what's the trade-off?" is the follow-up question in
every design review.

---

## Structure

### D-1 — Kustomize, not Helm

**Situation.** The repo had a Helm chart. Both tools solve environment variation.

**Decision.** Deleted `helm/`. Kustomize with a base and three overlays.

**Why.** Kustomize patches *real Kubernetes YAML*; Helm templates *strings that become YAML*.
That means a kustomize base is valid on its own, `kubectl apply -k` needs no extra tooling,
and you never debug whitespace in a Go template. It is also named explicitly in the target
job description.

**Cost.** No packaging or distribution story. Helm is genuinely better for shipping software
to *other people*; kustomize is better for deploying *your own*. Third-party components
(ingress-nginx here) still come from Helm.

---

### D-2 — Base plus overlays, namespace per environment

**Decision.** One base; `dev`, `stage`, `prod` overlays each setting `namespace:`.

**Why.** Every `.yaml` in `base/` is byte-identical for all environments. Divergence is how
prod quietly stops resembling what you tested. Kustomize renames the `Namespace` object too,
so one base produces three isolated environments.

**Cost.** Namespaces isolate names, RBAC and quotas — **not** the control plane, the
Kubernetes version, or cluster-scoped resources. You cannot rehearse a cluster upgrade this
way. At real scale prod gets its own cluster; the overlays make that a config change.

---

### D-3 — Three strategic merge patches per overlay, split by concern

**Decision.** `scale.yaml`, `resources.yaml`, `ingress.yaml`.

**Why.** Strategic merge reads as ordinary YAML — you state the fields you want changed and
kustomize merges by the schema's merge keys (`name` for containers). JSON6902 patches are
more precise but read as `/spec/template/spec/containers/0/...` and break silently when
list order changes. Splitting by concern means "how many replicas in prod?" is answerable
by opening one small file.

**Cost.** Strategic merge cannot express everything. Lists without a merge key (`args`,
`rules`, `volumeClaimTemplates`) are **replaced wholesale**, so changing one element means
restating all of them. That is why `prod/patches/ingress.yaml` restates the entire rule.

---

## Configuration

### D-4 — `configMapGenerator` / `secretGenerator` with hash suffixes

**Decision.** ConfigMaps and Secrets are generated from `.env` files, keeping the content
hash in the name.

**Why.** **This is the main reason to use kustomize at all.** A generated ConfigMap becomes
`voteapp-db-config-tkfhk78kg8`. Change a value → the hash changes → the name changes → the
Deployment's pod spec changes → **an automatic rolling update**.

Without it, editing a ConfigMap does nothing to running pods. Environment variables are read
once, at container start. That exact behaviour caused INCIDENT-001, where a Secret was
changed and only one of three consumers restarted.

**Cost.** Old generated objects accumulate until pruned. Anything referencing a ConfigMap by
its literal name from outside kustomize will break.

---

### D-5 — Three ConfigMaps grouped by what they *describe*

**Decision.** `redis-config`, `db-config`, `vote-config` — not one big one, not one per
service.

**Why.** A boundary should follow who *owns* a value, not who *consumes* it. `REDIS_HOST` is
a fact about the Redis Service; putting it in both a vote-config and a worker-config gives
you two places to edit and a chance to drift.

The hash behaviour makes this concrete. Blast radius matches reality:

| Change | Restarts |
|---|---|
| `REDIS_HOST` | vote + worker — both must reconnect ✅ |
| `POSTGRES_HOST` | db + worker + result ✅ |
| `OPTION_A` | vote only ✅ |

One monolithic ConfigMap would restart Postgres to change a button label.

**Cost.** `envFrom` gives a pod every key in the map, including a few it ignores.

---

### D-6 — `db-config` is consumed by Postgres itself

**Why.** The database is created with exactly the `POSTGRES_USER` and `POSTGRES_DB` that
worker and result connect with. One source of truth; they cannot drift.

Note what Postgres does *not* read: `POSTGRES_HOST` and `POSTGRES_PORT`. A server does not
need to be told its own address — those exist for clients. Same for Redis, which needs only
the password.

---

### D-7 — `stringData`, never hand-rolled base64

**Why.** `echo "pw" | base64` appends a newline. The encoded string looks perfectly normal
and authentication fails with a password that appears correct everywhere you check. This
cost real time before it was caught. `stringData` takes plain text and lets Kubernetes
encode it.

**Cost.** None. There is no reason to hand-encode.

---

### D-8 — Short Service names, not FQDNs

**Decision.** `POSTGRES_HOST=db-service`, not `db-service.voting.svc.cluster.local`.

**Why.** The FQDN hardcodes a namespace, so the same base could not be deployed to
`voting-dev` and `voting-prod`. A bare name resolves within the pod's own namespace. The
kustomize migration forced this fix.

---

## Security

### D-9 — `seccompProfile: RuntimeDefault` everywhere

**Why.** Filters ~350 syscalls down to what normal applications use. **Docker applies this by
default; Kubernetes does not** — so without it these pods were *less* confined than the same
image under `docker run`. It is also required by the `restricted` Pod Security Standard.

**Cost.** Effectively none. The runtime's default profile is built around what real apps do.

---

### D-10 — Namespace enforces Pod Security Standards `restricted`

**Why.** Turns hardening from a convention into a control. Verified: `kubectl run` with a
plain busybox pod is **rejected** by the API server. Conventions decay when someone is in a
hurry; admission control does not.

**Cost.** Rollout order matters — add `seccompProfile` to workloads *first* or every deploy
fails. Enforcement only applies at pod *creation*, so existing pods must be rolled.
Infrastructure namespaces often cannot be `restricted`: ingress-nginx needs
`NET_BIND_SERVICE` to bind port 80.

---

### D-11 — NetworkPolicy: default-deny plus exactly four edges

**Decision.** Deny all ingress and egress, then allow `vote→redis`, `worker→redis`,
`worker→db`, `result→db`, plus DNS.

**Why.** Default Kubernetes lets any pod reach any pod. The most valuable consequence:
**`vote`, the internet-facing tier, can no longer reach the database at all.** Verified —
`vote→postgres` times out while the app works normally.

Three things that are easy to get wrong and are worth stating:

1. **There is no deny verb.** You deny by selecting a pod for a `policyType` with no matching
   rule. `worker-netpol` lists `Ingress` with `ingress: []` for exactly this reason.
2. **DNS must be allowed explicitly.** Default-deny egress blocks CoreDNS and every hostname
   lookup fails, presenting as an application bug.
3. **Two selectors in one `from:` list is OR. Two selectors inside one list item is AND.**
   This is the classic NetworkPolicy bug.

**Cost.** L3/L4 only. It controls who can open a connection, not who they are. Any permitted
pod can do whatever the protocol allows. Workload identity needs mTLS via a service mesh.

Also: **NetworkPolicy is a spec, not an implementation.** A non-enforcing CNI accepts the
objects and ignores them — `kubectl get netpol` looks perfect and everything still flows.
This was verified by applying a deny-all and confirming traffic actually broke.

---

## Availability

### D-12 — PDBs, and `minAvailable` vs `maxUnavailable` is not stylistic

**Decision.** `minAvailable: 1` for vote and result; `maxUnavailable: 1` for worker.

**Why.** `minAvailable: 1` on a **single-replica** workload permits *zero* voluntary
disruptions — `kubectl drain` blocks forever on a budget that can never be satisfied.
Measured: `ALLOWED DISRUPTIONS: 0`. `maxUnavailable: 1` is safe at any replica count. In
prod, where worker runs 3, it switches to `minAvailable: 2`.

**Cost.** PDBs only constrain **voluntary** disruption. Node crashes, OOMKills and
`kubectl delete pod` ignore them entirely.

No PDB for Postgres or Redis: both are single-replica, so any PDB is either useless or
blocks every drain. They are single points of failure and a PDB does not change that.

---

### D-13 — Topology spread with `ScheduleAnyway`, not `DoNotSchedule`

**Why.** Before this, replicas *happened* to land on different nodes. Nothing enforced it.

`ScheduleAnyway` is deliberate: with `DoNotSchedule` plus a PDB on a small cluster, a drain
deadlocks — the evicted pod cannot satisfy the skew anywhere, stays `Pending`, the PDB never
recovers, and the next eviction is blocked forever.

`matchLabelKeys: [pod-template-hash]` scopes the skew calculation to one ReplicaSet.
Without it, old pods count during a rolling update and push new pods onto the wrong nodes.

**Cost.** Soft constraint — under pressure the scheduler will co-locate rather than refuse.

**PDB and topology spread solve different halves:** PDB stops too many going down *at once*
(voluntary); spread stops them being *where one failure takes them all* (involuntary).

---

### D-14 — HPA on `vote` only

**Why.** Autoscale on the signal that correlates with load *for that component*.

- **vote** — request-driven, CPU tracks load. ✅
- **result** — polls Postgres once/second *per replica* regardless of users. CPU is flat; a
  CPU HPA would scale on noise. The real signal is WebSocket connections.
- **worker** — polls Redis every 100ms unconditionally. Also flat. The real signal is queue
  depth, via KEDA — which is also the metric that should be alerting.

**The critical detail:** HPA utilisation is a percentage of the **request**, not the node.
At 250m requests and 15m actual usage the HPA reported `2%/70%` and would never have fired.
**Right-sizing requests is a prerequisite for autoscaling, not a separate cost exercise.**

**Cost.** HPA owns `replicas`, so leaving it in the manifest causes flapping under GitOps.

---

## Resources

### D-15 — Requests from measurement; CPU limits removed

**Decision.** Requests set from observed usage. Memory limits kept, CPU limits deleted
(`cpu: null` in the patch).

**Why.** Measured against 250m/512Mi requests:

```
vote 15m/137Mi   result 9m/64Mi   worker 32m/41Mi
postgres 30m/30Mi   redis 18m/4Mi
```

About **14× over on CPU, 7× on memory**. Requests are what the scheduler *reserves*, so that
capacity is unavailable to anything else whether used or not.

CPU limits are removed because CPU is *compressible*: exceeding a limit causes CFS throttling
at the quota boundary **even when the node is idle**. Requests already guarantee your share.
Memory is *incompressible* — exceed it and you are OOMKilled — so memory limits stay.

**Cost.** No CPU limit means a runaway pod can consume idle node CPU. Acceptable: requests
protect the neighbours, and throttling hurts latency more than a noisy neighbour does.

**Redis is the exception worth knowing:** its memory *limit* must exceed `--maxmemory` plus
overhead, or a full queue means OOMKill instead of Redis's own eviction policy.

**Caveat:** `kubectl top` is a ~15-second rolling average, not a peak. A load test that
finishes in seconds is averaged into invisibility. Real sizing needs Prometheus percentiles
over days, or VPA in recommendation mode.

---

## Networking

### D-16 — Host-based Ingress, not path-based

**Situation.** `localhost/vote` and `localhost/result` is tempting.

**Decision.** `vote.local` and `results.local`.

**Why.** Both apps serve assets from root-absolute paths, and the Socket.IO client hardcodes
`/socket.io/` at the origin root regardless of `<base href>`. Path-based routing therefore
requires **six application changes** and bakes the mount point into the image — this was
implemented, tested, and reverted. Host-based needs zero application changes.

**Cost.** Needs DNS (or `/etc/hosts` locally) rather than one hostname.

---

### D-17 — Sticky sessions at the Ingress, not the Service

**Decision.** nginx cookie affinity. Explicitly **no** `sessionAffinity: ClientIP`.

**Why.** Socket.IO opens with HTTP long-polling — a multi-request handshake where only the
pod holding the session knows about it. With two replicas and no affinity it fails
intermittently.

Cookie affinity beats IP affinity twice over: it identifies the *browser*, so users behind a
shared NAT still spread across replicas; and behind an Ingress the Service only sees the
*controller's* pod IP, so `ClientIP` would pin **all** traffic to one pod.

**Cost.** Affinity is a workaround for state living in the wrong place. The real fix is
forcing `transports: ['websocket']` on the client, which skips the handshake entirely.

---

### D-18 — Terraform owns AWS; kustomize owns cluster contents

**Why.** Clean ownership, and a hard technical reason: a `kubernetes` provider configured
from `module.eks` outputs cannot be configured during the *first* plan, because those outputs
do not exist yet. That is the well-known `cannot create REST client` failure, and the cure is
a lifetime of two-stage `-target` applies.

**Cost.** The gp3 StorageClass has to live in kustomize rather than Terraform.

---

## Known gaps

Stated plainly, because naming them is better than hoping nobody asks.

| Gap | What it should be |
|---|---|
| Credentials in git | External Secrets Operator from AWS Secrets Manager |
| `result` has no readiness probe | Needs a `/healthz` that queries Postgres — an app change |
| No ServiceAccount per workload | One each, `automountServiceAccountToken: false` |
| No `ResourceQuota` / `LimitRange` | Namespace guardrails; mandatory at enterprise scale |
| No `priorityClassName` | Postgres should outrank vote under node pressure |
| No ownership annotations | Team, on-call and runbook link belong on every object |
| No ServiceMonitor | No metrics scraping means no SLOs |
| Images are tags, not digests | A tag can be repointed; a digest cannot |
| Applied by hand | CI with plan-on-PR, or Argo CD reconciling continuously |

The last one is the biggest. Everything above is a manifest; that one is a process.
