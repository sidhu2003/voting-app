#
# Module input contract.
#
# These are already written for you — treat them as the interface you must satisfy.
# Read every one before you write a single resource: the variables tell you what the
# module is supposed to do.
#

variable "name" {
  description = "Name prefix for all resources in this VPC, e.g. 'voting-app-dev'."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR for the VPC. Use a /16 — EKS pods consume real VPC IPs and you will run out with anything smaller."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR, e.g. 10.0.0.0/16."
  }

  validation {
    condition     = tonumber(split("/", var.cidr_block)[1]) <= 16
    error_message = "Use /16 or larger. The VPC CNI assigns a VPC IP per pod; a /20 will strand you at a few hundred pods."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. Two minimum for an ALB, three for a proper quorum story."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Pick 2 or 3 AZs. One is not highly available; more than three is money you are not using."
  }
}

variable "enable_nat_gateway" {
  description = "Whether private subnets get outbound internet access via NAT."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = <<-EOT
    Route all private subnets through ONE NAT Gateway instead of one per AZ.

    true  = ~$32/month, but the NAT's AZ becomes a single point of failure.
    false = ~$32/month PER AZ, survives an AZ outage.

    Keep this true for learning. Flip it to false in prod and be able to explain
    the trade-off — this exact question gets asked in interviews.
  EOT
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = <<-EOT
    Name of the EKS cluster that will live in this VPC. Used only for subnet tagging.
    Leave empty if you are not running EKS here.

    Yes, this is a slightly leaky abstraction — a network module should not know about
    Kubernetes. It is the pragmatic norm because EKS discovers subnets BY TAG, and the
    tags must exist before the cluster is created.
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags merged onto every resource in this module."
  type        = map(string)
  default     = {}
}
