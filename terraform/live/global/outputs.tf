output "ecr_registry" {
  description = "Registry host. Set this as the GitHub repo variable ECR_REGISTRY."
  value       = local.registry
}

output "ecr_repository_urls" {
  description = "Full push URL per service."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
