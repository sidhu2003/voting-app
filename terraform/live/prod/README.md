# ⚠️ prod — DO NOT APPLY CASUALLY

**Approximate cost if applied and left running: ~$365/month.**

| Item | Monthly |
|---|---|
| EKS control plane | ~$73 |
| 3 × NAT gateway (one per AZ) | ~$108 |
| 3 × t3.large ON_DEMAND | ~$182 |
| KMS key | ~$1 |
| CloudWatch logs (audit enabled) | variable |

This environment exists so the repository shows what production **should** look like.
Reading it teaches you more than running it. Nothing here needs to be applied for the
project to be complete.

## What makes prod different from dev

| | dev | prod | Why |
|---|---|---|---|
| NAT gateways | 1 | 3 (one per AZ) | One shared NAT means losing that AZ kills outbound for all three |
| Node capacity | SPOT | ON_DEMAND | Spot reclaims a node on two minutes' notice |
| Node count | 2 | 3 (min 3) | A drain during upgrade must not take you to zero |
| Secrets encryption | off | KMS | Envelope encryption of Kubernetes Secrets at rest |
| Control plane logs | none | all five types | `audit` is the only record of who called the API |
| Log retention | 7 days | 90 days | Incident investigation window |
| CIDR | `10.0.0.0/16` | `10.2.0.0/16` | Non-overlapping so peering stays possible |

## Before this is ever applied for real

- [ ] `endpoint_public_access_cidrs` — currently `0.0.0.0/0`, which is wrong for prod.
      Replace with office/VPN egress ranges, or set `endpoint_public_access = false`
      and reach the API through a bastion or VPN.
- [ ] `enable_cluster_creator_admin_permissions` — convenient in dev, questionable in
      prod. Production access should come from named access entries, not from whoever
      happened to run `apply`.
- [ ] Populate `admin_principal_arns` / `viewer_principal_arns` so cluster access has
      an auditable answer in git.
- [ ] Apply from CI, not a laptop.
