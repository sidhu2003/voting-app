#
# These outputs are how tomorrow's EKS layer finds the network.
#
# It will read them with a terraform_remote_state data source pointed at this
# layer's state file. That is the seam between layers — keep it small and stable.
#

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes go here."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Public IPs the cluster's outbound traffic originates from."
  value       = module.vpc.nat_gateway_public_ips
}

output "availability_zones" {
  description = "AZs in the same order as the subnet ID lists."
  value       = module.vpc.availability_zones
}

output "eks_cluster_name" {
  description = "Cluster name the subnets were tagged for. The EKS layer must use this exact name."
  value       = local.name
}
