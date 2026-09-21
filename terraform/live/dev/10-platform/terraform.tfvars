#
# dev — cheapest safe configuration. Destroyed and rebuilt frequently.
#
environment = "dev"

# Cost switches
cluster_encryption_enabled = false # no KMS key: it cannot be deleted quickly
enabled_log_types          = []    # no control plane logs
log_retention_days         = 7

# Nodes: SPOT is ~70% cheaper. An interruption in dev costs nothing.
node_instance_types = ["t3.medium"]
node_capacity_type  = "SPOT"
node_min_size       = 1
node_max_size       = 3
node_desired_size   = 2
node_disk_size      = 20

# API endpoint
endpoint_public_access = true

# TODO: replace with your own IP so the API server is not open to the internet.
#   curl -s https://checkip.amazonaws.com
# then set: endpoint_public_access_cidrs = ["1.2.3.4/32"]
endpoint_public_access_cidrs = ["0.0.0.0/0"]

# Access management — you already get admin as the cluster creator.
admin_principal_arns  = []
viewer_principal_arns = []
