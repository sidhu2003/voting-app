#
# Layer: 00-network (dev)
#
# This is a COMPOSITION layer. Notice how little is here — it wires a module to
# some values and nothing else. That is deliberate and it is what most Terraform
# you write at a large company looks like: the resources live in versioned modules,
# and the live/ directories just say "one of those, configured like this".
#
# If you find yourself writing raw `resource` blocks in a live/ directory, stop and
# ask whether it belongs in a module instead.
#

locals {
  name = "${var.project}-${var.environment}"
}

module "vpc" {
  source = "../../../modules/vpc"

  name       = local.name
  cidr_block = var.vpc_cidr
  azs        = var.azs

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  # The EKS cluster does not exist yet, but its subnets must be tagged with its
  # name BEFORE it is created. So we commit to the name here and reuse it tomorrow.
  eks_cluster_name = local.name

  tags = {
    Environment = var.environment
  }
}
