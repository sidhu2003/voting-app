#
# prod — correct by design, not cheap.
#
# ⚠️  READ prod/README.md BEFORE APPLYING. Roughly $365/month all-in.
#     This environment exists so the repository shows what production SHOULD
#     look like. Nothing here needs to run for you to learn from it.
#
environment = "prod"

# --- Security ----------------------------------------------------------------

# Envelope-encrypt Kubernetes Secrets with a customer-managed KMS key. ~$1/month
# and worth it on a long-lived cluster. Note the key cannot be deleted quickly —
# that is a reason to avoid it in dev, not in prod.
cluster_encryption_enabled = true

# Every control plane log type. During an incident these are the only record of
# who called the API server and what they did. "audit" is the expensive one and
# also the one that answers the question the security team will actually ask.
enabled_log_types  = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
log_retention_days = 90

# --- Nodes -------------------------------------------------------------------

# ON_DEMAND, not SPOT. A spot interruption reclaims the node with two minutes'
# notice; that is an acceptable trade in dev and not in prod.
node_instance_types = ["t3.large"]
node_capacity_type  = "ON_DEMAND"

# Three nodes so a single node loss still leaves two AZs serving, and a node
# drain during an upgrade never takes you to zero capacity.
node_min_size     = 3
node_max_size     = 6
node_desired_size = 3
node_disk_size    = 50

# --- API endpoint ------------------------------------------------------------

# Public but locked down. The genuinely production-grade answer is
# endpoint_public_access = false plus a bastion or VPN into the VPC; that is
# left as a deliberate next step rather than pretended at.
endpoint_public_access = true

# ⚠️  0.0.0.0/0 IS WRONG FOR PROD. Replace with your office/VPN egress ranges
#     before this is ever applied.
endpoint_public_access_cidrs = ["0.0.0.0/0"]

# --- Access management -------------------------------------------------------

# In a real org these are populated and cluster-admin is rare. The creator of
# the cluster still gets admin via enable_cluster_creator_admin_permissions,
# which is itself something to revisit for a production cluster.
admin_principal_arns  = []
viewer_principal_arns = []
viewer_namespaces     = ["voting"]
