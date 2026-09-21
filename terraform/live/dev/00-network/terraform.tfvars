#
# dev network.
#
environment = "dev"
vpc_cidr    = "10.0.0.0/16"

# One NAT for all three AZs. ~$32/month instead of ~$96.
single_nat_gateway = true
