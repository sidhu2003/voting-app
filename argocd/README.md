# Argo CD

GitOps for the `voting-dev` environment. Argo runs **inside** the cluster and pulls from
GitHub — nothing outside needs credentials to reach in. That is the whole security argument
for the pull model, and it is why CI never runs `kubectl`.

## Install

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

One CRD will fail with `metadata.annotations: Too long`. `kubectl apply` stores the whole
object in a `last-applied-configuration` annotation and annotations cap at 256KB. Re-run
with server-side apply, which does not use that annotation:

```bash
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## The Application

```bash
kubectl apply -f argocd/app-dev.yaml
```

Points at `kubernetes/overlays/dev` on `main`. Argo detects kustomize automatically.

## UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080  (accept the self-signed cert)
# user: admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Delete `argocd-initial-admin-secret` once you have set a real password.

## Sync is AUTOMATED

Enabled only after the app reported `Synced`/`Healthy` on a manual sync. That order matters —
see below.

```yaml
syncPolicy:
  automated:
    prune: true        # delete resources git no longer declares
    selfHeal: true     # revert changes made directly against the cluster
    allowEmpty: false  # never prune everything if a render comes back empty
```

**selfHeal verified working.** `kubectl scale result-deployment --replicas=5` was reverted to
the value in git within 10 seconds. That is the control that would have caught INCIDENT-001
on its own: the live `kubectl patch` on `redis-secret` would have been undone in seconds
rather than waiting for a user to report that voting was broken.

It is also why the `ignoreDifferences` entries below are load-bearing. With `selfHeal` on, an
un-ignored HPA replica count puts Argo in a permanent fight with the autoscaler.

## Why it started manual

Enabling `automated` with `prune: true` before confirming a clean sync is how people delete
a running namespace on their first day: Argo reconciles the cluster to whatever git says,
and if git is behind, "reconcile" means "delete". At the time, the repo was 11 commits
behind the working tree — turning this on first would have destroyed the namespace.

Argo **adopts** resources that already exist. It matches on kind/name/namespace, not on who
created them, so the workloads applied by hand with `kubectl apply -k` were picked up
without being recreated.


## ignoreDifferences — two fields Argo must not fight

Both cause a **permanent** OutOfSync that syncing cannot fix, because something other than
git legitimately owns the value.

**`/spec/replicas` on vote-deployment.** The HPA owns replica count. git said 2, the HPA had
scaled to 3, and both were correct. Without this, `selfHeal` would actively fight the
autoscaler in a loop — scale to 2, HPA scales to 3, repeat.

**`/spec/volumeClaimTemplates` on StatefulSets.** The API server defaults
`volumeMode: Filesystem` and adds `status: {}`. git has neither, so the difference reappears
the moment it is "fixed". `volumeClaimTemplates` is immutable on an existing StatefulSet
anyway, so there is nothing to sync.

Recognising which diffs are *real* and which are API-server defaulting is most of what
running Argo well consists of.

## Useful commands

```bash
kubectl get application -n argocd
kubectl get application voting-app-dev -n argocd -o yaml | less

# what does Argo think differs? (same view kubectl gives)
kubectl diff -k kubernetes/overlays/dev

# force a refresh from git without syncing
kubectl annotate application voting-app-dev -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Rollback

`git revert` the commit and let Argo reconcile. The cluster follows git; there is no
separate rollback mechanism to learn, which is the point.

## The loop, end to end

Verified working on 2026-08-25:

```
push to vote/  →  CI builds amd64+arm64
               →  pushes to ECR
               →  captures digest sha256:27999f84...
               →  commits it to overlays/dev  (3edd52d)
               →  Argo syncs
               →  pods pull from ECR by digest in 2.4s
```

The pods now run `825979909451.dkr.ecr.ap-south-1.amazonaws.com/voteapp-vote@sha256:...`,
authenticated by the `ecr-creds` pull secret.

## Not done yet

- only `dev` has an Application; stage and prod would each get one
- no Argo Rollouts, so deploys are rolling updates rather than blue-green
- no webhook, so Argo polls every 3 minutes rather than syncing on push
- no SSO; single local admin account
