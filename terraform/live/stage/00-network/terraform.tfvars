#
# stage network.
#
environment = "stage"

# Different block from dev (10.0) and prod (10.2). Non-overlapping CIDRs are
# what make VPC peering possible later.
vpc_cidr = "10.1.0.0/16"

# Still one NAT. Stage validates behaviour, not AZ-failure resilience.
single_nat_gateway = true
