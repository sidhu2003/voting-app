# Module: `vpc`

Hand-written VPC for the voting-app EKS cluster. Written by hand deliberately — see
the note at the bottom.

## What it creates

| Resource | Count | Notes |
|---|---|---|
| VPC | 1 | DNS support + DNS hostnames both on (EKS requires it) |
| Internet Gateway | 1 | |
| Public subnets | one per AZ | `/20` each, tagged for internet-facing load balancers |
| Private subnets | one per AZ | `/18` each, tagged for internal load balancers, nodes live here |
| Elastic IPs | 1 or N | one per NAT gateway |
| NAT Gateways | 1 or N | controlled by `single_nat_gateway` |
| Route tables | 1 public + 1 or N private | |
| Flow logs | 1 | to CloudWatch Logs |

## Usage

```hcl
module "vpc" {
  source = "../../../modules/vpc"

  name             = "voting-app-dev"
  cidr_block       = "10.0.0.0/16"
  azs              = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  eks_cluster_name = "voting-app-dev"

  single_nat_gateway = true # cost control for dev

  tags = {
    Environment = "dev"
  }
}
```

## Address plan

VPC `10.0.0.0/16`:

| Purpose | AZ a | AZ b | AZ c |
|---|---|---|---|
| Public `/20` | `10.0.0.0/20` | `10.0.16.0/20` | `10.0.32.0/20` |
| Private `/18` | `10.0.64.0/18` | `10.0.128.0/18` | `10.0.192.0/18` |

`10.0.48.0/20` is intentionally unallocated — room to grow without renumbering.

Private subnets are much larger than public ones because the AWS VPC CNI assigns a
real VPC IP address to **every pod**. Public subnets only hold load balancers and NAT
gateways, so they stay small.

## Cost

With `single_nat_gateway = true`, the NAT Gateway is the only meaningful cost here at
roughly **$0.045/hour plus data processing** — about **$32/month** if left running.
Everything else in this module is free.

Set `enable_nat_gateway = false` to drop that to zero, at the cost of private subnets
having no outbound internet (your nodes will not be able to pull images from public
registries).

## Why this is hand-written

`terraform-aws-modules/vpc` is excellent and is what you would use in production. This
module exists so its author understands what that one is doing — subnet tagging, NAT
placement, route table association, and the DNS hostname requirement are all things you
only really learn by getting them wrong once.
