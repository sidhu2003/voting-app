output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL. Any future IRSA role needs this."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN."
  value       = module.irsa.oidc_provider_arn
}

output "irsa_role_arns" {
  description = "IRSA role ARNs by key."
  value       = module.irsa.role_arns
}

output "service_account_annotations" {
  description = "Annotate each ServiceAccount with eks.amazonaws.com/role-arn = <value>."
  value       = module.irsa.service_account_annotations
}

output "cluster_iam_role_arn" {
  description = "Control plane role ARN."
  value       = module.eks_iam.cluster_role_arn
}

output "node_iam_role_arn" {
  description = "Worker node role ARN."
  value       = module.eks_iam.node_role_arn
}

output "node_security_group_id" {
  description = "Security group attached to worker nodes. The workload layer needs this for database rules."
  value       = module.eks.node_security_group_id
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
