#
# stage — production-shaped, dev-priced.
#
# The point of stage is to catch things dev cannot: real access entries, real
# log types, a rolling node upgrade. It is NOT a capacity rehearsal, so the
# instances stay small.
#
environment = "stage"

# Still no KMS key. Stage gets rebuilt often enough that stranded keys in a
# pending-deletion window would accumulate.
cluster_encryption_enabled = false

# Cheap log types only. "audit" is the expensive one and is left to prod.
enabled_log_types  = ["api", "authenticator"]
log_retention_days = 14

node_instance_types = ["t3.medium"]
node_capacity_type  = "SPOT"
node_min_size       = 1
node_max_size       = 4
node_desired_size   = 2
node_disk_size      = 20

endpoint_public_access = true
# TODO: narrow to your IP — curl -s https://checkip.amazonaws.com
endpoint_public_access_cidrs = ["0.0.0.0/0"]

# Exercise the access-entry path here rather than discovering it in prod.
admin_principal_arns  = []
viewer_principal_arns = []
viewer_namespaces     = ["voting"]
