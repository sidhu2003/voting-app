#
# Identical in every environment. All differences live in terraform.tfvars.
# Defaults here are the SAFE/CHEAP option, so a forgotten value costs nothing.
#

variable "project" {
  description = "Project slug."
  type        = string
  default     = "voting-app"
}

variable "environment" {
  description = "Environment name. Also selects the network layer's state key."
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

variable "state_bucket" {
  description = "S3 bucket holding remote state. Must match the backend block."
  type        = string
  default     = "terraform-state-voting-825979909451"
}

# --- Cluster -----------------------------------------------------------------

variable "kubernetes_version" {
  description = "EKS control plane version. Pin it; never let this float."
  type        = string
  default     = "1.33"
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API server publicly. Needed for kubectl from a laptop."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public API endpoint.

    0.0.0.0/0 means the whole internet can attempt to authenticate. It is the
    module default and it is not what you want. Set your own IP:
      curl -s https://checkip.amazonaws.com
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Cost / safety switches --------------------------------------------------

variable "cluster_encryption_enabled" {
  description = <<-EOT
    Envelope-encrypt Kubernetes Secrets with a customer-managed KMS key.

    Costs ~$1/month, and a KMS key CANNOT be deleted immediately — it sits in a
    7-30 day pending-deletion window while still billing. Leave false anywhere
    you destroy and rebuild often, or you strand a key per cycle.
  EOT
  type        = bool
  default     = false
}

variable "enabled_log_types" {
  description = <<-EOT
    EKS control plane log types shipped to CloudWatch.

    Module default is ["audit","api","authenticator"]. Audit is verbose and
    bills per GB ingested. Empty list = no control plane logging.
  EOT
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch retention for control plane logs. Never use 0 (= keep forever)."
  type        = number
  default     = 7
}

# --- Node group --------------------------------------------------------------

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is ~70% cheaper and fine for dev/stage."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum nodes. A ceiling on how much a runaway autoscaler can cost you."
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Nodes to run now."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "EBS volume size per node, GB."
  type        = number
  default     = 20
}

# --- Access management -------------------------------------------------------

variable "admin_principal_arns" {
  description = <<-EOT
    IAM principals granted cluster-admin via an access entry.

    Whoever runs `terraform apply` already gets admin through
    enable_cluster_creator_admin_permissions, so this is for OTHER people.
  EOT
  type        = list(string)
  default     = []
}

variable "viewer_principal_arns" {
  description = "IAM principals granted read-only access, scoped to viewer_namespaces."
  type        = list(string)
  default     = []
}

variable "viewer_namespaces" {
  description = "Namespaces the read-only principals can see."
  type        = list(string)
  default     = ["voting"]
}
