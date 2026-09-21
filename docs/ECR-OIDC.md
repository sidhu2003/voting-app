# ECR + GitHub OIDC

ECR repositories are Terraform (`terraform/live/global`). The OIDC provider and CI role are
created **by hand** — they need broad IAM permissions that the Terraform user does not have,
and they are a one-time setup.

## What exists already

```
825979909451.dkr.ecr.ap-south-1.amazonaws.com/voteapp-vote
                                             /voteapp-result
                                             /voteapp-worker
```

Scan-on-push enabled. Lifecycle: untagged images expire after 1 day, only the 10 most recent
are kept. Without that, images accumulate forever at $0.10/GB/month.

## 1. Create the OIDC provider

Console → IAM → Identity providers → Add provider → OpenID Connect

| Field | Value |
|---|---|
| Provider URL | `https://token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |

Or:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

AWS stopped verifying the thumbprint for this provider, but the field is still required.

## 2. Create the role

Trust policy — **read the `sub` condition before pasting it**:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::825979909451:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:venkata-siddardha/voting-app:*"
      }
    }
  }]
}
```

> ### The `sub` claim may contain numeric IDs
>
> If your GitHub org has **immutable OIDC IDs** enabled, the claim is not what the docs show.
> It looks like this:
>
> ```
> repo:venkata-siddardha@197880870/voting-app@1333217466:ref:refs/heads/main
>                       ^^^^^^^^^^           ^^^^^^^^^^^
> ```
>
> Those are the org and repository **database IDs**. The format pins the claim to identities
> that cannot be renamed, so nobody can take over a freed-up repo name and inherit your trust
> policy. It is more secure — and it silently breaks any policy written against the name-based
> form, with an `AccessDenied` that never says why.
>
> **Do not guess which format you are on.** CloudTrail records the exact claim AWS received:
>
> ```bash
> aws cloudtrail lookup-events \
>   --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
>   --max-results 1 --region ap-south-1 \
>   --query 'Events[0].CloudTrailEvent' --output text | python3 -m json.tool | grep userName
> ```
>
> Then write the trust policy against whatever that prints.
>
> **The `sub` condition is the whole security model.** Omit it and **any repository on
> GitHub — anyone's — can assume this role.** The `aud` check alone is not enough; every
> GitHub Actions token has that same audience.
>
> `:*` allows any branch and any pull request, which CI needs because it runs on PRs.
> A production deploy role should tighten this to
> `repo:venkata-siddardha/voting-app:ref:refs/heads/main`.

## 3. Attach the permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrLogin",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PushToOwnReposOnly",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories"
      ],
      "Resource": [
        "arn:aws:ecr:ap-south-1:825979909451:repository/voteapp-vote",
        "arn:aws:ecr:ap-south-1:825979909451:repository/voteapp-result",
        "arn:aws:ecr:ap-south-1:825979909451:repository/voteapp-worker"
      ]
    }
  ]
}
```

`GetAuthorizationToken` is account-level and cannot be scoped — it returns the `docker login`
token. Everything else is pinned to these three repositories, so a compromised CI run cannot
touch any other registry in the account.

## 4. Wire up GitHub

```bash
gh variable set ECR_REGISTRY --body 825979909451.dkr.ecr.ap-south-1.amazonaws.com
gh variable set ECR_ROLE_ARN --body arn:aws:iam::825979909451:role/<role-name>
```

**Both** variables are required. `app.yml` gates every ECR step on
`vars.ECR_REGISTRY != '' && vars.ECR_ROLE_ARN != ''`.

Setting only one used to let the step run with no `role-to-assume`, which fails as:

```
Error: Credentials could not be loaded, please check your action inputs:
Could not load credentials from any providers
```

That message says nothing about the real cause. The tell is the action's `with:` block in
the log — if `role-to-assume` is absent from it, the variable is empty or misnamed.

Note this is **`ECR_ROLE_ARN`, not `AWS_ROLE_ARN`.** They are deliberately separate: this
role can only push to three ECR repositories, while the Terraform pipeline's role can create
infrastructure. Sharing one variable would mean setting it here also switches on the
Terraform plan and apply jobs, which would then fail on permissions.

## 5. Let the local cluster pull

**On EKS this step does not exist.** The node role carries
`AmazonEC2ContainerRegistryReadOnly` (already attached by `modules/eks-iam`) and the kubelet
authenticates itself. A pull secret is purely a local-cluster workaround — do not carry it
into the EKS manifests.

`kubectl create secret` has **no `--docker-password-stdin`** — that flag belongs to
`docker login`. Use command substitution:

```bash
kubectl create secret docker-registry ecr-creds \
  --docker-server=825979909451.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region ap-south-1)" \
  -n voting-dev --dry-run=client -o yaml | kubectl apply -f -

# attach to the namespace's default ServiceAccount so every pod inherits it,
# rather than editing five pod specs
kubectl patch serviceaccount default -n voting-dev \
  -p '{"imagePullSecrets":[{"name":"ecr-creds"}]}'
```

The `--dry-run=client -o yaml | kubectl apply -f -` pattern makes it idempotent — plain
`kubectl create secret` fails once the secret already exists, which matters when you re-run
this daily.

> Note the token lands in your shell history and briefly in the process list. Acceptable for
> a 12-hour credential on a local cluster; on a shared machine, prefer the CronJob below.

**That token expires after 12 hours.** Re-run it each session, or put it on a CronJob:

```yaml
# refreshes every 8h from inside the cluster, using IRSA on EKS or a mounted
# credential locally. Sketch only -- the ServiceAccount and RBAC are omitted.
apiVersion: batch/v1
kind: CronJob
metadata: { name: ecr-creds-refresh, namespace: voting-dev }
spec:
  schedule: "0 */8 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: refresh
              image: amazon/aws-cli:latest
              command: ["/bin/sh","-c"]
              args:
                - |
                  TOKEN=$(aws ecr get-login-password --region ap-south-1)
                  kubectl create secret docker-registry ecr-creds \
                    --docker-server=$REGISTRY --docker-username=AWS \
                    --docker-password="$TOKEN" \
                    --dry-run=client -o yaml | kubectl apply -f -
```

This is the one genuinely annoying part of pulling from ECR into a non-EKS cluster, and it
is why the step does not exist on EKS at all.

## Cost

| | |
|---|---|
| Storage | $0.10/GB/month — 3 images ≈ 800MB ≈ **$0.08** |
| Transfer out | $0.09/GB — a few pulls to a laptop ≈ **cents** |

Under $1/month, versus ~$165/month for a real EKS cluster. This is why the local cluster plus
real ECR is the right shape for learning: the registry, the OIDC, the digests and the Argo
sync are all genuinely real. Only the compute is local.
