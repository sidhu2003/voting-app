#
# Identical in every environment. All differences live in terraform.tfvars.
#

variable "project" {
  description = "Project slug."
  type        = string
  default     = "voting-app"
}

variable "environment" {
  description = "Environment name. Part of every resource name, so keep it short."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "venkata"
}

variable "vpc_cidr" {
  description = <<-EOT
    CIDR for this environment's VPC.

    Every environment MUST use a different block. They work fine in isolation
    with the same CIDR, right up until someone wants VPC peering or a transit
    gateway between them — at which point overlapping ranges make it impossible
    and you are renumbering a live environment.
  EOT
  type        = string
}

variable "azs" {
  description = "Availability zones to use."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "single_nat_gateway" {
  description = <<-EOT
    Route all private subnets through ONE NAT gateway.

    true  = ~$32/month, but that AZ becomes a single point of failure.
    false = ~$32/month PER AZ, survives an AZ outage.

    true for dev/stage, false for prod.
  EOT
  type        = bool
  default     = true
}
