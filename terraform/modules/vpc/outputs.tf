#
# Module output contract.
#
# Outputs are the module's PUBLIC API. Tomorrow's EKS layer consumes these, so
# think of them as a promise: once something is an output and another layer reads
# it, renaming it is a breaking change.
#
# Rule of thumb: export IDs and ARNs, not whole objects. Exporting
# `aws_vpc.vpc_main` leaks every attribute and makes the module impossible to
# refactor without breaking callers.
#

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.vpc_main.id
}

output "vpc_cidr_block" {
  description = "CIDR of the VPC. EKS security group rules need this."
  value       = aws_vpc.vpc_main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs — internet-facing load balancers and NAT live here."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS worker nodes go here."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IPs your cluster's outbound traffic appears to come from. You will need these for allowlisting."
  value       = aws_eip.nat[*].public_ip
}

# Added for the EKS layer: the cluster's control plane security group needs to allow
# traffic from the node subnets, and the AWS Load Balancer Controller needs the AZ
# list to spread load balancer ENIs.
output "availability_zones" {
  description = "AZs the subnets were created in, in the same order as the subnet ID lists."
  value       = var.azs
}
