# Layer: 20-workload (dev)

**Later this week.** Application-facing infrastructure — the layer that changes most
often, which is exactly why it has its own state file.

Will contain:

- ECR repositories for `vote`, `result`, `worker`
- IRSA roles for anything in-cluster that needs AWS permissions
  (AWS Load Balancer Controller, External Secrets, EBS CSI driver)
- Optionally: RDS for Postgres instead of the in-cluster StatefulSet

Backend key will be `dev/20-workload/terraform.tfstate`.
