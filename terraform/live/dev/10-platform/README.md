# dev / 10-platform

EKS cluster, worker nodes, IAM roles, IRSA, and cluster access management.

- **How to run it, cost, troubleshooting:** [`terraform/README.md`](../../../README.md)
- **Why it is built this way:** [`terraform/DECISIONS.md`](../../../DECISIONS.md)

## Depends on

`live/dev/00-network` must be applied first — this layer reads its state for the VPC and
subnet IDs. If you see `outputs is object with no attributes`, the network layer is
destroyed or was never applied.

## Quick reference

```bash
terraform init
terraform plan -out=tfplan     # ~35 resources
terraform apply tfplan         # 15-20 min, mostly waiting on the control plane

aws eks update-kubeconfig --region ap-south-1 --name voting-app-dev
kubectl get nodes
```

Destroy this layer **before** the network layer.

## What it creates

| | |
|---|---|
| `module.eks_iam` | cluster role, node role (hand-written) |
| `module.eks` | EKS control plane, one managed node group, core addons |
| `module.irsa` | OIDC provider, IRSA role for the EBS CSI driver |
| `aws_eks_addon.ebs_csi` | EBS CSI driver — glue between the two modules |

Environment differences live entirely in `terraform.tfvars`.
