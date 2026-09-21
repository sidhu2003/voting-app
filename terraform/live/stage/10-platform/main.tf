#
# Layer: 10-platform — the EKS cluster.
#
# Creation order (Terraform infers it from the references; no depends_on needed):
#   1. IAM roles              — must exist before the cluster
#   2. EKS cluster + nodes
#   3. OIDC provider + IRSA   — needs the cluster's issuer URL
#   4. EBS CSI addon          — needs the IRSA role
#
# This file is IDENTICAL in dev, stage and prod. Every environment difference
# lives in terraform.tfvars. If you need to edit this file for one environment
# only, that is a signal the difference belongs in a variable instead.
#

# ----------------------------------------------------------------------------
# 1. IAM roles — hand-written, see modules/eks-iam.
# ----------------------------------------------------------------------------
module "eks_iam" {
  source = "../../../modules/eks-iam"

  name = local.name

  tags = {
    Environment = var.environment
  }
}


# ----------------------------------------------------------------------------
# 2. The cluster and one managed node group.
# ----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id = local.vpc_id

  # Nodes and control plane ENIs live in PRIVATE subnets. Nothing in this
  # cluster gets a public IP; egress is via the NAT gateway.
  subnet_ids = local.private_subnet_ids

  # --- API server endpoint ---------------------------------------------------
  # The module defaults endpoint_public_access to FALSE, which produces a
  # cluster your laptop cannot reach — kubectl just hangs. We enable it, but
  # restrict it by CIDR rather than leaving it open to the internet.
  endpoint_private_access      = true
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # --- Identity --------------------------------------------------------------
  # Use the roles from modules/eks-iam instead of letting the module invent
  # its own, so the permissions are ours to read and audit.
  create_iam_role = false
  iam_role_arn    = module.eks_iam.cluster_role_arn

  # modules/irsa creates the OIDC provider. Leaving this true would make a
  # second one for the same issuer URL and fail with EntityAlreadyExists.
  enable_irsa = false

  # --- Access management -----------------------------------------------------
  # "API" is the current mechanism. "API_AND_CONFIG_MAP" (the module default)
  # also keeps the legacy aws-auth ConfigMap alive, which is a hand-edited YAML
  # blob in the cluster with no audit trail. Access entries live in git instead.
  authentication_mode = "API"

  # Without this, whoever runs `terraform apply` has NO access to the cluster
  # they just created. The module defaults it to false.
  enable_cluster_creator_admin_permissions = true

  access_entries = local.access_entries

  # --- Encryption ------------------------------------------------------------
  # Envelope encryption of Kubernetes Secrets with a customer-managed KMS key.
  #
  # OFF in dev/stage on purpose: a KMS key costs ~$1/month AND cannot be deleted
  # immediately — it enters a 7-30 day pending-deletion window while still
  # billing. Destroying and rebuilding a learning cluster nightly would strand a
  # new key every single day. ON in prod, where the cluster is long-lived and
  # encrypting Secrets at rest is worth a dollar.
  create_kms_key    = var.cluster_encryption_enabled
  encryption_config = var.cluster_encryption_enabled ? {} : null

  # --- Control plane logging -------------------------------------------------
  # Module default is ["audit", "api", "authenticator"]. Audit logs are verbose
  # and bill per GB ingested into CloudWatch, so dev/stage keep a minimal set.
  # Prod keeps all of them — during an incident these are the only record of who
  # called the API server.
  enabled_log_types                      = var.enabled_log_types
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # --- Addons ----------------------------------------------------------------
  # The EBS CSI driver is NOT here: it needs an IRSA role, which needs the
  # cluster's OIDC issuer, which needs this module. Putting it here would be a
  # dependency cycle. It is installed as a separate resource below.
  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      ami_type       = "AL2023_x86_64_STANDARD"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      disk_size = var.node_disk_size

      create_iam_role = false
      iam_role_arn    = module.eks_iam.node_role_arn

      labels = {
        Environment = var.environment
      }
    }
  }

  tags = {
    Environment = var.environment
  }
}


# ----------------------------------------------------------------------------
# 3. OIDC provider + IRSA roles — hand-written, see modules/irsa.
#
# Instantiated ONCE. Add entries to the map for more roles; do not add a second
# module block, or you get a duplicate OIDC provider.
# ----------------------------------------------------------------------------
module "irsa" {
  source = "../../../modules/irsa"

  name            = local.name
  oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  service_accounts = {
    # Provisions EBS volumes for PersistentVolumeClaims. Without this, every
    # StatefulSet pod (Postgres, Redis) sits Pending forever.
    ebs_csi = {
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
      policy_arns     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
    }
  }

  tags = {
    Environment = var.environment
  }
}


# ----------------------------------------------------------------------------
# 4. EBS CSI driver addon.
#
# A raw resource in a live/ directory is normally a smell, but this one is pure
# glue between two modules that cannot reference each other without a cycle.
# ----------------------------------------------------------------------------
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = module.irsa.role_arns["ebs_csi"]

  # If a conflicting setting already exists in the cluster, overwrite it rather
  # than failing the apply.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Environment = var.environment
  }
}


# ----------------------------------------------------------------------------
# DELIBERATELY NOT HERE: anything inside the cluster.
#
# No kubernetes or helm provider, no StorageClass, no namespaces, no manifests.
# The boundary is: Terraform owns AWS resources, kustomize owns cluster contents.
#
# Two reasons, and the second is the one that actually bites:
#
# 1. Clean ownership. `kubectl apply -k` should be the only thing that changes
#    what runs in the cluster, so there is one place to look.
#
# 2. The kubernetes provider would have to be configured from module.eks outputs
#    that do not exist during the FIRST plan. Terraform cannot configure a
#    provider from unknown values, so the initial apply fails with "cannot
#    create REST client: no client config" and you end up doing two-stage
#    -target applies forever. It is a well-known trap and the cheapest fix is
#    to not create the dependency.
#
# The gp3 StorageClass therefore belongs in the kustomize base, not here.
# EKS ships a default gp2 StorageClass, so PVCs still work without it.
# ----------------------------------------------------------------------------
