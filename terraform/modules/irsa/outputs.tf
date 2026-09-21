output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for this cluster."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "role_arns" {
  description = <<-EOT
    Map of role key to role ARN.

    Put the ARN on the Kubernetes ServiceAccount as the annotation
    eks.amazonaws.com/role-arn — that annotation is what links the two halves.
  EOT
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "service_account_annotations" {
  description = "Ready-to-paste annotation value per role, keyed by 'namespace/serviceaccount'."
  value = {
    for k, sa in var.service_accounts :
    "${sa.namespace}/${sa.service_account}" => aws_iam_role.this[k].arn
  }
}
