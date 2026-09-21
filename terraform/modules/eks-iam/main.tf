#
# IAM roles that must exist BEFORE an EKS cluster can be created.
#
# Two different things act on your behalf, so there are two roles:
#
#   1. The EKS control plane (AWS-managed) creates ENIs and load balancers in
#      YOUR account. It assumes the CLUSTER role.
#   2. Your worker EC2 instances join the cluster, wire up pod networking, and
#      pull images. They assume the NODE role.
#
# Both are "service roles": the trust policy names an AWS SERVICE as principal,
# not a user. The most common first-EKS mistake is swapping the two principals.
#

locals {
  tags = merge(var.tags, { Module = "eks-iam" })

  # Attached to the node role. Each one is load-bearing:
  #   WorkerNodePolicy - kubelet registers the node with the cluster
  #   CNI_Policy       - VPC CNI attaches ENIs and hands IP addresses to pods
  #   ECRReadOnly      - nodes pull images from ECR
  #
  # Drop CNI_Policy and nodes join but every pod sits in ContainerCreating.
  # Drop ECRReadOnly and it all works until you deploy your own image.
  node_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]
}


# ----------------------------------------------------------------------------
# Cluster role — assumed by the EKS control plane.
# ----------------------------------------------------------------------------

# Trust policies are written as policy documents rather than jsonencode() blobs
# so they are validated at plan time and readable in a diff.
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    sid     = "EKSControlPlaneAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  description        = "EKS control plane role for ${var.name}"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.tags, { Name = "${var.name}-eks-cluster" })
}

# AmazonEKSServicePolicy is legacy and not needed on clusters created today.
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ----------------------------------------------------------------------------
# Node role — assumed by the worker EC2 instances.
# ----------------------------------------------------------------------------

# Principal is ec2.amazonaws.com, NOT eks.amazonaws.com. The instance assumes
# this role, not the EKS service. Getting this wrong produces nodes that never
# appear, with an error that never mentions the trust policy.
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    sid     = "EC2InstanceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node"
  description        = "EKS worker node role for ${var.name}"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(local.tags, { Name = "${var.name}-eks-node" })
}

# for_each over the list rather than three near-identical resource blocks.
# Adding a policy later becomes a one-line change in locals.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset(local.node_policy_arns)

  role       = aws_iam_role.node.name
  policy_arn = each.value
}
