#
# The seam between layers.
#
# Reads 00-network's state and pulls out its outputs. Note what it does NOT do:
# it does not manage those resources, cannot modify them, and cannot destroy
# them. Read-only, one direction. That is the point of splitting state — this
# layer physically cannot break your VPC.
#
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/00-network/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}"

  # Pulled out so the rest of the config reads cleanly and there is exactly one
  # place to look when an output name changes.
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr_block     = data.terraform_remote_state.network.outputs.vpc_cidr_block
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.network.outputs.public_subnet_ids

  # The subnets were tagged for THIS cluster name in the network layer. It must
  # match, or the tags point at a cluster that does not exist and load balancer
  # placement fails.
  cluster_name = data.terraform_remote_state.network.outputs.eks_cluster_name

  # --------------------------------------------------------------------------
  # Access entries: which IAM principals may talk to the cluster, and what they
  # may do once inside.
  #
  # Two separate gates, routinely conflated:
  #   IAM        — may you call the EKS API at all?
  #   Kubernetes — once connected, what may you do?
  # An access entry is the bridge between them.
  #
  # Keys are derived from the principal name so that reordering the list does
  # not churn resources.
  # --------------------------------------------------------------------------
  admin_entries = {
    for arn in var.admin_principal_arns : "admin-${basename(arn)}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Read-only, and scoped to named namespaces rather than the whole cluster.
  # This is the right default for anyone who does not need more — start here and
  # widen deliberately.
  viewer_entries = {
    for arn in var.viewer_principal_arns : "viewer-${basename(arn)}" => {
      principal_arn = arn
      policy_associations = {
        view = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            type       = "namespace"
            namespaces = var.viewer_namespaces
          }
        }
      }
    }
  }

  access_entries = merge(local.admin_entries, local.viewer_entries)
}
