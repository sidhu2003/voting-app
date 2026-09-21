output "cluster_role_arn" {
  description = "ARN of the EKS control plane role."
  value       = aws_iam_role.cluster.arn
}

output "cluster_role_name" {
  description = "Name of the EKS control plane role."
  value       = aws_iam_role.cluster.name
}

output "node_role_arn" {
  description = "ARN of the worker node role."
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the worker node role."
  value       = aws_iam_role.node.name
}
