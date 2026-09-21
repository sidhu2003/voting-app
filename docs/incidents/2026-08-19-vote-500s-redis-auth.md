# INCIDENT-001 — Users unable to cast votes

| | |
|---|---|
| **Date** | 2026-08-19 |
| **Severity** | Sev-2 — core user journey unavailable, no data loss |
| **Duration** | ~18 minutes (14:24 → 14:42 UTC) |
| **Detected by** | User report |
| **Author** | Venkata Siddardha |
| **Status** | Resolved |

---

## Summary

A Redis password rotation was applied directly to the live Kubernetes Secret. Only the
`vote` Deployment was restarted afterwards, so `vote` authenticated with the new password
while the Redis server and the `worker` still held the old one. Every attempt to cast a
vote returned HTTP 500. The results dashboard and the vote page itself continued to return
HTTP 200 throughout, and all pods reported `Running` and `Ready`, so no automated signal
fired.

---

## Impact

- **Users could not vote.** `POST /` returned HTTP 500 for the full duration.
- **No data was lost.** Votes already in Redis and Postgres were unaffected; the failure
  was at the point of accepting new votes, before anything was queued.
- **No user-visible error page.** The vote form rendered normally; only submission failed.
- **The results dashboard appeared healthy**, showing a stale but plausible tally.

---

## Timeline (UTC)

| Time | Event |
|---|---|
| 14:06:40 | `redis-secret` created via `kubectl apply` with `REDIS_PASSWORD=s3cr3t-redis-pw`. Redis, vote and worker all start with this value. |
| 14:24:11 | `redis-secret` modified directly on the cluster via `kubectl patch` to a new value. No corresponding change in git. |
| ~14:24 | `vote-deployment` restarted. New pods read the **new** password. Redis and worker keep the **old** one — their pods were not restarted. |
| ~14:25 | Vote submissions begin returning HTTP 500. No alert fires. |
| ~14:30 | User reports "the vote button does nothing". |
| ~14:33 | `kubectl logs deploy/vote-deployment` shows `redis.exceptions.AuthenticationError: invalid username-password pair`. |
| ~14:38 | Live Secret compared against `kubernetes/redis_secret.yaml`; values differ. `printenv` inside each pod confirms vote holds the new password, Redis and worker the old. |
| ~14:42 | Secret re-applied from git; `vote-deployment` restarted. Service restored. Redis and worker deliberately untouched. |

*(Times after 14:24 are approximate — reconstruct from your shell history if you want them
exact. The first two are precise, taken from `metadata.managedFields`.)*

---

## Root cause

**A partially-completed credential rotation.**

Redis authentication requires the server and every client to hold the same password.
Environment variables are read **once, at container start** — changing a Secret does not
update running pods. Restarting only one of the three consumers left the system in a split
state that no single component could detect.

---

## Contributing factors

> *Write these in your own words — this section is the RCA. Prompts below; delete them.*

**1. The change bypassed git.**
`kubectl patch` modifies the cluster directly, so `git diff` showed nothing and the repo no
longer described reality.
*What made this possible, and what would prevent it?*

**2. Kubernetes does not propagate Secret changes to running pods.**
*Why is this surprising? What should a rotation procedure have looked like?*

**3. `vote`'s readiness probe does not exercise Redis.**
The probe is `GET /`, which renders the page without touching Redis, so pods reported
`Ready` while every vote failed.
*What is a readiness probe actually supposed to mean?*

**4. `result` never touches Redis, so the dashboard masked the outage.**
The read path was entirely healthy while the write path was down.
*What does this say about monitoring the thing users see versus the thing users do?*

**5. No alerting on the write path.**
Detection was a user report. Redis queue depth and vote error rate were both unmonitored.
*Which single metric would have caught this fastest?*

---

## Detection

Found by a user, not by monitoring. Every automated signal was green:

- all 7 pods `Running`, `Ready`, **0 restarts**
- vote page HTTP 200
- results dashboard HTTP 200

The only observable that moved was the application error log.

---

## Resolution

Rolled back rather than rolling forward:

1. Re-applied `kubernetes/redis_secret.yaml` from git, restoring the original password.
2. Restarted `vote-deployment` only.
3. Left Redis and `worker` untouched — both already held the correct password, and
   restarting Redis would have been an unnecessary datastore restart during an incident.

Verified by casting a vote (HTTP 200), confirming the Redis queue drained to zero, and
confirming the Postgres row count increased.

**Why rollback and not "finish the rotation":** restoring a known-good state has a smaller
blast radius than rolling forward through a change that had already misbehaved. Completing
the rotation properly is planned work for a change window, not an incident action.

---

## What went well / what went poorly

> *Your call — a few lines each. Be honest about the poorly.*

**Went well**

-
-

**Went poorly**

-
-

---

## Action items

> *Add owners and dates. Delete anything you would not actually do — a list of aspirations
> is worse than a short list you complete.*

| # | Action | Why | Owner | Due |
|---|---|---|---|---|
| 1 | Alert on Redis `LLEN votes` growth | The only signal that moves before users notice | | |
| 2 | Alert on `vote` HTTP 5xx rate | Detects the write path directly | | |
| 3 | Deploy a reloader so Secret changes restart their consumers | Removes the manual step that was missed | | |
| 4 | Document the Redis rotation runbook: server **and** both clients restart | The procedure did not exist | | |
| 5 | Adopt GitOps so direct cluster edits are reverted automatically | Removes the drift class entirely | | |
| 6 | Decide whether `vote` readiness should test Redis | Currently `Ready` means very little | | |

---

## Appendix — commands that produced the evidence

```bash
# who last modified each field, and when
kubectl get secret redis-secret -n voting \
  -o jsonpath='{range .metadata.managedFields[*]}{.manager}{"\t"}{.time}{"\n"}{end}'

# what the last `kubectl apply` sent, vs what is live
kubectl get secret redis-secret -n voting \
  -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}'
kubectl get secret redis-secret -n voting -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d

# what each container is ACTUALLY using
kubectl exec -n voting redis-statefulset-0      -- printenv REDIS_PASSWORD
kubectl exec -n voting deploy/vote-deployment   -- printenv REDIS_PASSWORD
kubectl exec -n voting deploy/worker-deployment -- printenv REDIS_PASSWORD
```

`managedFields` recorded `manager=kubectl-patch` at 14:24:11 — the change was attributable
on the object itself the whole time.
