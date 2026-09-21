#
# prod network.
#
# ⚠️  ~$96/month for NAT gateways alone. See prod/README.md before applying.
#
environment = "prod"

# Distinct from dev (10.0) and stage (10.1).
vpc_cidr = "10.2.0.0/16"

# One NAT PER AZ. This is the single biggest cost difference between prod and
# the other environments, and it is deliberate: with one shared NAT, losing that
# AZ takes outbound connectivity away from all three. Availability is the thing
# prod is paying for.
single_nat_gateway = false
