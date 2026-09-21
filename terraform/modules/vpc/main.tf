#
# ============================================================================
#  YOUR WORK GOES IN THIS FILE.
# ============================================================================
#
#  Ten TODOs below, in dependency order. Write them top to bottom — each one
#  needs the one above it. Run `terraform validate` after every TODO and keep
#  it green; do not write all ten and then debug.
#
#  Everything is commented out so the module starts valid. Uncomment and fill
#  in as you go.
#
#  Docs: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
#  Look up every resource. Do not guess argument names.
# ============================================================================

# ----------------------------------------------------------------------------
# CIDR math — given to you, because a silent overlap here is miserable to debug.
# Read it until you can explain it, then move on.
# ----------------------------------------------------------------------------
#
# cidrsubnet(prefix, newbits, netnum) carves a subnet out of a larger block.
#   newbits = how many bits to ADD to the prefix length
#   netnum  = which of the resulting blocks you want (0-indexed)
#
# With cidr_block = 10.0.0.0/16:
#
#   cidrsubnet("10.0.0.0/16", 4, 0) -> 10.0.0.0/20    (16 + 4 = /20)
#   cidrsubnet("10.0.0.0/16", 2, 1) -> 10.0.64.0/18   (16 + 2 = /18)
#
# The plan:
#   PUBLIC  /20 each, netnum 0,1,2  -> 10.0.0.0/20,  10.0.16.0/20,  10.0.32.0/20
#   PRIVATE /18 each, netnum 1,2,3  -> 10.0.64.0/18, 10.0.128.0/18, 10.0.192.0/18
#
# Public subnets are small on purpose — they hold load balancers and NAT
# gateways, not pods. Private subnets are large because every pod burns a real
# VPC IP under the AWS VPC CNI. That asymmetry is a deliberate design decision
# and a good thing to be able to justify out loud.
#
# 10.0.48.0 - 10.0.63.255 is left spare. Deliberate: room to grow without
# renumbering. Never allocate 100% of a VPC on day one.

locals {
  # Tags applied to everything this module creates.
  tags = merge(
    var.tags,
    {
      Module = "vpc"
    }
  )

  # Subnet CIDRs, computed per AZ.
  public_subnet_cidrs  = [for i, az in var.azs : cidrsubnet(var.cidr_block, 4, i)]
  private_subnet_cidrs = [for i, az in var.azs : cidrsubnet(var.cidr_block, 2, i + 1)]

  # How many NAT gateways to actually create.
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0

  # EKS discovers subnets by tag. These get merged onto the subnets below.
  # An empty map when eks_cluster_name is "" means "no EKS tags at all".
  eks_cluster_tag = var.eks_cluster_name == "" ? {} : {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }
}


# ----------------------------------------------------------------------------
# TODO 1 — The VPC itself.
#   resource "aws_vpc" "this"
#
# Arguments you need: cidr_block, enable_dns_support, enable_dns_hostnames, tags.
#
# GOTCHA: enable_dns_hostnames MUST be true. EKS worker nodes register with the
# cluster using their private DNS name. Leave it false (the default) and nodes
# join and then mysteriously go NotReady. This is a genuine day-ruiner.
#
# Name it with: tags = merge(local.tags, { Name = var.name })
# ----------------------------------------------------------------------------

resource "aws_vpc" "vpc_main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = var.name })
}


# ----------------------------------------------------------------------------
# TODO 2 — Internet Gateway.
#   resource "aws_internet_gateway" "this"
#
# One per VPC. This is what makes a subnet "public" — not the subnet itself, but
# a route table pointing 0.0.0.0/0 at this IGW. Remember that distinction; it is
# the most common conceptual gap in AWS networking interviews.
# ----------------------------------------------------------------------------

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.vpc_main.id
  tags   = merge(local.tags, { Name = "${var.name}-igw" })
}


# ----------------------------------------------------------------------------
# TODO 3 — Public subnets (one per AZ).
#   resource "aws_subnet" "public"
#
# Use count = length(var.azs) and index with count.index.
#   cidr_block        = local.public_subnet_cidrs[count.index]
#   availability_zone = var.azs[count.index]
#
# Set map_public_ip_on_launch = true.
#
# REQUIRED TAGS — merge these in, EKS will not work without them:
#   "kubernetes.io/role/elb" = "1"      <- lets the LB controller place
#                                          internet-facing load balancers here
#   plus local.eks_cluster_tag
#
# Name them so you can tell them apart in the console:
#   Name = "${var.name}-public-${var.azs[count.index]}"
#
# NOTE ON count VS for_each: count is fine here and simpler to read. Be aware
# that if you ever REMOVE an AZ from the middle of the list, count re-indexes and
# Terraform will destroy and recreate subnets. for_each keyed by AZ name avoids
# that. Know the trade-off; use count today.
# ----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.vpc_main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    local.tags,
    {
      Name                     = "${var.name}-public-${var.azs[count.index]}"
      "kubernetes.io/role/elb" = "1"
    },
    local.eks_cluster_tag
  )
}

# ----------------------------------------------------------------------------
# TODO 4 — Private subnets (one per AZ).
#   resource "aws_subnet" "private"
#
# Same shape as TODO 3 but:
#   cidr_block = local.private_subnet_cidrs[count.index]
#   NO map_public_ip_on_launch
#   tag "kubernetes.io/role/internal-elb" = "1"   <- note: internal-elb
#   plus local.eks_cluster_tag
# ----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.vpc_main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(
    local.tags,
    {
      Name                              = "${var.name}-private-${var.azs[count.index]}"
      "kubernetes.io/role/internal-elb" = "1"
    },
    local.eks_cluster_tag
  )
}


# ----------------------------------------------------------------------------
# TODO 5 — Elastic IPs for the NAT gateway(s).
#   resource "aws_eip" "nat"
#
# count = local.nat_gateway_count
# Set domain = "vpc".
#
# GOTCHA: an EIP that is ALLOCATED BUT NOT ATTACHED bills you hourly. If a NAT
# gateway fails to create and you walk away, the EIP keeps charging. Check the
# console after a failed apply.
# ----------------------------- -----------------------------------------------

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name}-nat-eip-${count.index}" })
}


# ----------------------------------------------------------------------------
# TODO 6 — NAT Gateway(s).
#   resource "aws_nat_gateway" "this"
#
# count = local.nat_gateway_count
# allocation_id = aws_eip.nat[count.index].id
# subnet_id     = aws_subnet.public[count.index].id
#
# READ THAT LAST LINE AGAIN. A NAT gateway lives in a PUBLIC subnet. Its whole
# job is to sit in the public subnet and forward traffic outward on behalf of
# private ones. Putting it in a private subnet is the classic mistake and it
# fails in a confusing way.
#
# Add: depends_on = [aws_internet_gateway.this]
# The NAT needs the IGW to exist first, and Terraform cannot infer that
# dependency because there is no direct reference between them. This is one of
# the few legitimate uses of depends_on — most uses are a smell.
# ----------------------------------------------------------------------------

resource "aws_nat_gateway" "nat" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, { Name = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.gateway]
}


# ----------------------------------------------------------------------------
# TODO 7 — Public route table + its default route.
#   resource "aws_route_table" "public"
#   resource "aws_route"       "public_internet"   (0.0.0.0/0 -> IGW)
#
# One public route table is enough for all AZs — they all exit the same way.
#
# STYLE NOTE: you can write routes inline inside aws_route_table, or as separate
# aws_route resources. Do not mix the two on the same table — they fight each
# other and Terraform will show perpetual diffs. Pick separate aws_route here.
# ----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc_main.id

  tags = merge(local.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gateway.id
}


# ----------------------------------------------------------------------------
# TODO 8 — Private route table(s) + default route(s).
#   resource "aws_route_table" "private"
#   resource "aws_route"       "private_nat"   (0.0.0.0/0 -> NAT)
#
# THINK BEFORE YOU TYPE. How many private route tables do you need?
#
#   single_nat_gateway = true  -> all AZs share one NAT, so ONE table works
#   single_nat_gateway = false -> each AZ must exit via ITS OWN NAT, so you need
#                                 one table PER AZ
#
# If you give every AZ its own NAT but only one shared route table, you have
# paid for three NATs and are using one. Costs triple, resilience does not
# improve. Work out the count expression yourself — this is the reasoning the
# whole module is here to teach.
#
# Hint: count = var.single_nat_gateway ? 1 : length(var.azs)
# and index the NAT with the same expression when you write the route.
# ----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : length(var.azs)

  vpc_id = aws_vpc.vpc_main.id

  tags = merge(local.tags, { Name = "${var.name}-private-rt-${count.index}" })
}

resource "aws_route" "private_nat" {
  count = local.nat_gateway_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}


# ----------------------------------------------------------------------------
# TODO 9 — Route table associations.
#   resource "aws_route_table_association" "public"
#   resource "aws_route_table_association" "private"
#
# A route table attached to nothing does nothing. This is the step people forget,
# and the symptom is "my subnet has no internet but the route table looks right".
#
# For private, the route table index depends on your TODO 8 decision.
# ----------------------------------------------------------------------------

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}


# ----------------------------------------------------------------------------
# TODO 10 — VPC Flow Logs (to CloudWatch Logs).
#   resource "aws_flow_log"                     "this"
#   resource "aws_cloudwatch_log_group"         "flow_logs"
#   resource "aws_iam_role"                     "flow_logs"
#   resource "aws_iam_role_policy"              "flow_logs"
#
# Do this one LAST, and only after 1-9 apply cleanly.
#
# Why it matters: flow logs are how you answer "did that packet arrive?" during
# an incident. Every security review at a company like Apple asks for them. It is
# also your first IAM trust policy — the service principal is
# vpc-flow-logs.amazonaws.com. Good warm-up for tomorrow.
#
# Set retention_in_days on the log group. The default is "never expire", which
# is a slow-motion bill.
#
# If you are short on time today, skip 10 and tell me — it is the one item here
# that is genuinely optional for a learning cluster.
# ----------------------------------------------------------------------------
