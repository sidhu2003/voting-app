variable "name" {
  description = "Name prefix for the roles, e.g. 'voting-app-dev'."
  type        = string
}

variable "oidc_issuer_url" {
  description = "The cluster's OIDC issuer URL, from the EKS module output `cluster_oidc_issuer_url`."
  type        = string
}

variable "service_accounts" {
  description = <<-EOT
    Map of IRSA roles to create, keyed by a short name.

    One OIDC provider is created for the cluster, then one IAM role per entry here.
    Instantiate this module ONCE per cluster and add entries to the map — a second
    instantiation would try to create a duplicate OIDC provider and fail.

    Example:
      {
        ebs_csi = {
          namespace       = "kube-system"
          service_account = "ebs-csi-controller-sa"
          policy_arns     = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
        }
      }
  EOT
  type = map(object({
    namespace       = string
    service_account = string
    policy_arns     = optional(list(string), [])
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
