variable "project" {
  description = "Short project slug. Used as a prefix for all resource names."
  type        = string
  default     = "voting-app"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "project must be lowercase alphanumeric with hyphens only (it ends up in an S3 bucket name)."
  }
}

variable "state_bucket_name" {
  description = <<-EOT
    Name of the S3 bucket holding Terraform state.

    S3 bucket names are globally unique across ALL AWS accounts, so the account ID
    suffix is what keeps this from colliding with a stranger's bucket.
  EOT
  type        = string
  default     = "terraform-state-voting-825979909451"
}

variable "region" {
  description = "AWS region for the state bucket. Keep this the same as your workload region."
  type        = string
  default     = "ap-south-1"
}

variable "owner" {
  description = "Who owns this infrastructure. Shows up in cost reports and in the 'who do I page' question."
  type        = string
  default     = "venkata"
}
