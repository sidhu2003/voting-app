# Workflows

| File | Purpose |
|---|---|
| `terraform.yml` | The pipeline. Static checks, cost diff, plan on PR, apply dev on merge, manual promote to stage/prod. |
| `terraform-stack.yml` | Reusable workflow that plans or applies **one** stack. Called six ways rather than duplicated six times. |
| `terraform-drift.yml` | Nightly sweep. Detects infrastructure that no longer matches the code. |
| `app.yml` | Application CI. Check, build multi-arch, scan, push to ECR, write the digest into the dev overlay. |

## What runs when

| Event | Jobs |
|---|---|
| **Pull request** | fmt · validate (10 dirs) · tflint · trivy, then `plan` for every environment the diff touches — each posting its own PR comment |
| **Merge to main** | the same checks, then `apply` dev: `00-network` then `10-platform`, in that order |
| **Manual dispatch** | `apply` to stage or prod, choosing the layer |

## Two design decisions worth knowing

**Stage and prod are never applied by a merge.** Applying production infrastructure because
someone merged a pull request is how outages happen. Promotion is a deliberate
`workflow_dispatch` where a human picks the environment, and the GitHub Environment's
required reviewers gate it a second time before the job starts.

**Layers apply sequentially, never in parallel.** `10-platform` reads `00-network`'s remote
state, so applying both at once is a race. The `needs:` between them is the ordering.

## Path filtering

A change under `terraform/modules/**` affects all three environments, so all three are
planned. A change under `terraform/live/dev/**` plans dev only. Without this, every PR
plans six stacks and the signal drowns.

## Enabling the AWS jobs

Everything except plan/apply runs with no credentials. Those two skip themselves until the
repository variable `AWS_ROLE_ARN` is set.

1. Create an IAM OIDC provider for `token.actions.githubusercontent.com`, audience
   `sts.amazonaws.com`.
2. Create a role trusting it, with a condition pinning
   `token.actions.githubusercontent.com:sub` to this repository, e.g.
   `repo:venkata-siddardha/voting-app:*`. **Without that condition any repository on GitHub
   could assume the role.**
3. Attach the permissions the Terraform needs.
4. `gh variable set AWS_ROLE_ARN --body arn:aws:iam::<acct>:role/<role>`

No access keys anywhere — OIDC mints a short-lived token per run.

## Approval gates

Create GitHub Environments named `dev`, `stage` and `prod` under repo settings. Add required
reviewers to `stage` and `prod`. Those jobs then wait for a human.

The gate lives in **repository settings, not in this YAML** — so it cannot be bypassed by
editing the workflow in the same pull request. That is the separation-of-duties property,
and it is the reason to use Environments rather than an `if:` condition.

## Cost estimation (Infracost)

Runs on every pull request and comments the **change** in monthly spend. `+$96/month` is
actionable; an absolute figure needs someone to remember yesterday's.

Infracost parses the HCL directly, so it needs **no AWS credentials** — only an API key
(free tier). Two settings to enable it:

```bash
gh secret set INFRACOST_API_KEY --body "<key from infracost.io>"
gh variable set INFRACOST_ENABLED --body true
```

Two, because a job-level `if:` can only read the `github`, `needs`, `vars` and `inputs`
contexts — `secrets` and `env` are not available there. The variable switches the job on;
the secret is used inside it.

Which stacks get priced is in `infracost.yml` at the repo root. `modules/` is excluded (no
instantiated resources to cost) and so is `bootstrap/` (an S3 bucket holding a few KB
rounds to zero and would only add noise).

## Drift detection

`terraform-drift.yml` runs at 02:30 UTC daily, or on demand.

It runs `terraform plan -refresh-only -detailed-exitcode` against all six stacks.
`-refresh-only` is the important flag: it asks *"does reality match state?"* rather than
*"what would my code change?"*. Without it, code that is merged but not yet applied would
be reported as drift, which it is not.

Exit codes: `0` clean, `2` drift, `1` error.

Results roll up into **one** GitHub issue labelled `drift`, updated on each run and closed
automatically once everything is clean. One issue per stack would mean six issues on a bad
day and nobody reading any of them.

This is the Terraform equivalent of INCIDENT-001, where a live `kubectl patch` left the
cluster disagreeing with git and nothing noticed until users did.

## Known gaps

- `trivy` reports without blocking (`exit-code: 0`). Flip it to `1` once the current
  findings are triaged. A gate that always fails gets ignored.
- Drift detection *reports*; it does not auto-remediate. That is deliberate — drift is
  sometimes a fix someone applied during an incident, and reverting it blindly would undo
  the fix.


---

# app.yml

```
changes ──┬─► check      (per changed service: syntax + dependency resolution)
          ├─► kustomize  (all 3 overlays must render; selectors must stay clean)
          └─► build      (PR: single-arch + trivy.  main: multi-arch → ECR → digest)
                              │
                              └─► update-dev-overlay   (commit the digest)
```

## The handoff

The last job writes image digests into `kubernetes/overlays/dev/kustomization.yaml` and
commits. **That commit is the deployment** — Argo CD reconciles from it. Nothing in this
pipeline runs `kubectl`.

Only dev updates automatically. Promotion to stage and prod is a pull request moving the
same digest, reviewed by a human.

## Why the PR and main builds differ

| | platforms | push | why |
|---|---|---|---|
| PR | `linux/amd64` | no | buildx cannot `--load` a multi-platform image into a single-arch daemon, and Trivy needs a loaded image to scan |
| main | `linux/amd64,linux/arm64` | yes | EKS nodes are x86_64, local machines are arm64. A single-arch image fails at runtime with `exec format error` — on the node, not in CI |

## Digests, not tags

The image is tagged with the commit SHA, but the overlay references it **by digest**:

```
programmer175/voteapp_vote=<registry>/voteapp-vote@sha256:abc...
```

A tag can be repointed at different content. A digest cannot. It is the only way
"which code is in production?" has a truthful answer.

`provenance: true` and `sbom: true` attach a SLSA build attestation and a software bill of
materials to each pushed image.

## The commit loop

CI commits to the same repo it is triggered by. Two guards, deliberately redundant:

- `paths-ignore: ['kubernetes/overlays/**']` on the push trigger
- `[skip ci]` in the commit message

With a separate GitOps repo this problem does not exist, which is one of the reasons that
split is the norm at scale.

## Enabling the ECR half

`check` and `kustomize` run today with no credentials. The build/push/commit path needs:

```bash
gh variable set ECR_REGISTRY --body "<acct>.dkr.ecr.ap-south-1.amazonaws.com"
```

plus `AWS_ROLE_ARN` (shared with the Terraform pipeline) and the ECR repositories
themselves, which come from the not-yet-written `terraform/live/*/20-workload` layer.

## Honest gaps

- **There are no tests.** `npm test` exits 1 by design; vote and worker have none. The
  `check` job does syntax and dependency-resolution checks, which catch real breakage but
  are not tests. Calling them tests would be a lie.
- **`result` has no `package-lock.json`**, so its dependency versions are not reproducible
  between builds. `npm ci` cannot be used until that exists.
- **Trivy image scanning reports without blocking.** Tighten once the base images are
  current.
