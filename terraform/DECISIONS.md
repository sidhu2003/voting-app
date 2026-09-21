# Decision Record

Why this infrastructure is built the way it is.

Every entry follows the same shape: **the situation**, **what was chosen**, **why**, and
**what it costs you**. That last line matters most — a decision with no downside is
usually a decision you have not thought about yet, and "what's the trade-off?" is the
follow-up question in every design review.

---

## Structure

### D1 — Split state by layer, not one state per environment

**Situation.** Everything could live in one state file per environment.

**Decision.** Three state files per environment: `00-network`, `10-platform`,
`20-workload`.

**Why.** Blast radius. A mistake in the workload layer *cannot* produce a plan that
destroys the VPC, because the VPC is not in that state file — Terraform cannot see it.
Plans stay small and fast. Later, CI can auto-apply the workload layer while requiring a
human for the network layer.

**Cost.** Cross-layer values need `terraform_remote_state`, and a full rebuild is three
sequential applies instead of one.

---

### D2 — A directory per environment, not workspaces

**Situation.** `terraform workspace new prod` is the obvious-looking answer.

**Decision.** `live/dev`, `live/stage`, `live/prod`.

**Why.** Workspaces share one backend configuration, so you cannot vary the region or
state bucket per environment, and `apply` in the wrong workspace is one forgotten command
away. Directories make the environment visible in the path — you can *see* where you are.

**Cost.** Duplication. Acceptable here only because `live/` is thin (34 lines for a
network layer). If a live directory grows past ~100 lines of real config, the module
boundary is wrong.

---

### D3 — Every environment's `.tf` files are byte-identical

**Situation.** Environments could diverge freely once copied.

**Decision.** Only `terraform.tfvars` and the backend `key` differ.

**Why.** Divergence is how prod quietly stops resembling what you tested. If a change
cannot be expressed as a variable, that is a signal — either it belongs in a variable, or
the environments are genuinely different systems and should say so loudly.

**Cost.** Some variables exist purely so an environment can differ.

---

### D4 — Variable defaults are the cheap, safe option

**Situation.** Defaults could mirror production.

**Decision.** Defaults are dev-shaped: no KMS, no audit logs, SPOT, 7-day retention.

**Why.** A forgotten value should cost nothing and break nothing. Prod overrides every
one of them explicitly in its `tfvars`, so prod's configuration is fully readable in one
file rather than half-inherited from defaults.

**Cost.** Reading `prod/terraform.tfvars` alone does not tell you what dev does.

---

## Build vs. borrow

### D5 — Hand-write the VPC; use the community module for EKS

**Situation.** `terraform-aws-modules` has excellent modules for both.

**Decision.** VPC written by hand. EKS via `terraform-aws-modules/eks ~> 21.0`.

**Why.** The VPC is ~150 lines and every one of them teaches something you need when
networking breaks — subnet tags, NAT placement, route table association, the DNS hostname
requirement. The EKS module is thousands of lines handling launch templates, addon
ordering and access entries; hand-writing it is not a learning exercise, it is a detour.

**Cost.** The hand-written VPC is less featureful than the community one. In a real job
you would use the community module — but you would understand what it was doing.

---

### D6 — Hand-write **all** IAM

**Situation.** The EKS module creates its own cluster and node roles by default.

**Decision.** `create_iam_role = false` everywhere; roles come from `modules/eks-iam`,
OIDC and IRSA from `modules/irsa`.

**Why.** IAM is where the security actually lives, and it is the thing you will be asked
to justify. A generated role you have never read is a role you cannot defend. This is
also the highest-value area for the team that owns Apple Pay infrastructure.

**Cost.** More code, and you own its correctness. A missing node policy produces failures
that do not mention IAM anywhere.

---

### D7 — Pin every module and provider version

**Decision.** `~> 21.0` for the EKS module, `~> 6.0` for the AWS provider,
`.terraform.lock.hcl` committed.

**Why.** Without pins, a rebuild six weeks from now silently picks up a new major version
and your plan shows changes you did not write. v21 renamed most of v20's inputs —
`cluster_name` → `name`, `cluster_version` → `kubernetes_version` — so an unpinned upgrade
would not even parse.

**Cost.** Upgrades become deliberate work rather than drift.

---

## State

### D8 — S3 native locking, not DynamoDB

**Decision.** `use_lockfile = true`.

**Why.** DynamoDB-based locking was the only option before Terraform 1.10 and has been
deprecated since 1.11. Native locking is one line and one less resource to manage.

**Cost.** Every older tutorial you find will tell you to create a DynamoDB table. Know
the history so the question does not catch you out.

---

### D9 — The state bucket has `prevent_destroy`

**Why.** Deleting the state bucket orphans every resource in every layer: Terraform
forgets they exist, AWS keeps billing, and you clean up by hand in the console.
Versioning is enabled for the same reason — a corrupted state file has an undo.

**Cost.** Genuinely tearing it down needs a code edit first. That friction is the point.

---

## Networking

### D10 — Non-overlapping CIDRs per environment

**Decision.** dev `10.0.0.0/16`, stage `10.1.0.0/16`, prod `10.2.0.0/16`.

**Why.** Identical CIDRs work perfectly in isolation — until someone wants VPC peering or
a transit gateway between environments, at which point overlapping ranges make it
impossible and you are renumbering something live. Costs nothing to get right on day one.

---

### D11 — Private subnets `/18`, public `/20`

**Why.** The AWS VPC CNI assigns a **real VPC IP address to every pod**. Private subnets
hold pods and need room; public subnets hold only load balancers and NAT gateways.
`10.0.48.0/20` is left unallocated on purpose — never allocate 100% of a VPC on day one.

**Cost.** Asymmetric sizing looks arbitrary until you know why. Hence this entry.

---

### D12 — One NAT gateway in dev/stage, one per AZ in prod

**Why.** A NAT gateway is ~$36/month and is the largest cost difference between the
environments. One shared NAT means losing that AZ removes outbound connectivity for all
three. Dev accepts that; prod pays ~$108/month not to.

**Cost.** Dev does not exercise the multi-NAT routing path, so prod's routing is less
tested. Mitigated by the module handling both cases from the same code.

---

## Cluster

### D13 — Terraform owns AWS; kustomize owns cluster contents

**Decision.** No `kubernetes` or `helm` provider. No StorageClass, namespaces, or
manifests in Terraform.

**Why.** Two reasons, and the second is the one that bites. First, clean ownership —
`kubectl apply -k` is the only thing that changes what runs in the cluster. Second, a
`kubernetes` provider configured from `module.eks` outputs cannot be configured during the
**first** plan, because those outputs do not exist yet. That is the well-known
"cannot create REST client: no client config" failure, and the cure is a lifetime of
two-stage `-target` applies. Not creating the dependency is cheaper than managing it.

**Cost.** The gp3 StorageClass has to live in kustomize. EKS ships a default gp2 class, so
nothing breaks meanwhile.

---

### D14 — Access entries in `API` mode, not the aws-auth ConfigMap

**Decision.** `authentication_mode = "API"`, access defined in `access_entries`.

**Why.** There are two separate gates and people conflate them constantly: **IAM** decides
whether you may call the EKS API at all; **Kubernetes RBAC** decides what you may do once
connected. An access entry is the bridge. The legacy path was a hand-edited YAML ConfigMap
inside the cluster with no history and no review — one bad edit locked everyone out. In
Terraform, "who can touch this cluster" has an auditable answer in git.

**Cost.** `API` mode drops aws-auth entirely, so anything still expecting it must migrate.

---

### D15 — IRSA rather than permissions on the node role

**Situation.** The EBS CSI driver needs AWS permissions. The easy answer is to attach the
policy to the node role.

**Decision.** A dedicated IAM role trusted by exactly one Kubernetes service account.

**Why.** A permission on the node role belongs to **every pod on that node**, including
anything compromised. IRSA scopes it to one service account, with no stored credential —
the cluster mints a short-lived JWT, IAM trusts the cluster's signing key, the pod trades
the JWT for temporary credentials.

The trust policy needs **both** conditions:

| Condition | Omitting it means |
|---|---|
| `:sub` | **any** service account in the cluster can assume the role |
| `:aud` | a token minted for a different audience is accepted |

Neither omission produces an error. They silently over-grant. This is the first thing a
security reviewer checks.

**Cost.** More moving parts, and a typo in the `sub` claim fails closed with an
`AccessDenied` that does not say which side is wrong.

---

### D16 — No KMS key in dev/stage

**Decision.** `cluster_encryption_enabled = false` outside prod.

**Why.** Not mainly the ~$1/month. A KMS key **cannot be deleted immediately** — it enters
a 7–30 day pending-deletion window and bills throughout. Destroying and rebuilding a dev
cluster nightly would strand a new key every single day, and two weeks later you are
paying for fourteen keys you cannot delete.

**Cost.** Kubernetes Secrets are not envelope-encrypted in dev/stage. Acceptable given
nothing real is stored there; not acceptable in prod, which has it on.

---

### D17 — SPOT in dev/stage, ON_DEMAND in prod

**Why.** SPOT is ~70% cheaper. An interruption reclaims the node on two minutes' notice —
irrelevant in dev, unacceptable in prod. `node_max_size` also caps how much a runaway
autoscaler can spend.

---

### D18 — `enable_cluster_creator_admin_permissions = true`

**Why.** The module defaults it to `false`, which produces a cluster that its own creator
cannot access. Combined with the default `endpoint_public_access = false`, a first apply
gives you an unreachable cluster you have no rights on.

**Cost.** This is genuinely questionable for production — access should come from named
access entries, not from whoever happened to run `apply`. Flagged as a checklist item in
`live/prod/README.md` rather than silently left on.

---

## Questions you should be able to answer

Not trivia. These are the follow-ups an interviewer or reviewer actually asks.

**Why three state files instead of one?**
Blast radius. The workload layer physically cannot plan a change to the VPC.

**Why not workspaces for environments?**
Shared backend config, and applying to the wrong one is one forgotten command away.

**What breaks if two environments share a CIDR?**
Nothing — until you need peering or a transit gateway, and then you are renumbering
something live.

**Why is the node role's trust principal `ec2.amazonaws.com`?**
The EC2 instance assumes it, not the EKS service. The control plane role is the one
trusting `eks.amazonaws.com`.

**Explain IRSA in four sentences.**
The cluster runs an OIDC provider and gives each pod a short-lived signed JWT naming its
service account. IAM is configured to trust that provider. A role's trust policy pins
`:sub` to one namespace/service-account and `:aud` to `sts.amazonaws.com`. The pod calls
`AssumeRoleWithWebIdentity` with its JWT and gets temporary credentials — no stored secret.

**Why not just put the policy on the node role?**
Then every pod on that node gets it, including anything compromised.

**What does an EKS access entry do that IAM does not?**
IAM decides whether you can call the EKS API. The access entry maps your IAM principal to
Kubernetes RBAC — what you can do once connected.

**Why one NAT gateway in dev and three in prod?**
~$36/month each. One shared NAT means its AZ failing takes outbound away from all three.
Dev accepts that risk; prod buys the availability.

**Your plan says `forces replacement` on a subnet. What now?**
Stop. Find out why — usually `count` re-indexing after an AZ list change. Recreating a
subnet detaches everything in it.

**Why does `terraform plan` have to say "No changes" after an apply?**
Otherwise the config never converges with reality, which means nobody can review a plan
and know what it will do.

---

## Why this shape matters at Apple IS&T

Mapping to the role, honestly — including the gaps.

| JD item | Where it shows up | Status |
|---|---|---|
| Kubernetes, `kubectl` + **kustomize** | EKS cluster; kustomize overlays | cluster done, kustomize next |
| **Terraform** | this directory | done |
| **AWS: EKS, VPC, EC2** | all three | done |
| Automation to remove manual toil | `Makefile`, destroy/rebuild loop | partial — Python wrapper would be stronger |
| **Incident triage and RCA** | troubleshooting tables | needs a written RCA |
| Multi-cloud / on-prem | — | **gap** |
| **Ansible** | — | **gap** |
| **Grafana** | — | **gap** |
| Python for automation | — | **gap** |

**Three things a reviewer will actually notice.**

*Small, reviewable changes.* Three state files and thin `live/` directories mean a PR
touches one layer of one environment. "This change cannot affect the network" is the
sentence that makes a senior relax about a junior's PR.

*Decisions with trade-offs attached.* Every entry above names what it costs. Juniors
who list benefits sound like they read a blog post; engineers who name the downside sound
like they have operated the thing.

*Cost as an engineering constraint.* The KMS pending-deletion trap, single-vs-triple NAT,
SPOT in dev — infrastructure engineers who think about the bill are rarer than they should
be, and at Apple's scale it is a first-class concern.

**The honest gaps**, worth saying out loud rather than hoping nobody asks: no CI/CD yet
(applies still run from a laptop, which is the biggest one), no monitoring, no
progressive delivery, no Ansible, and prod has never actually been applied.
