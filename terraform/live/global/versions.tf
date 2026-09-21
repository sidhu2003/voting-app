terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  backend "s3" {
    bucket = "terraform-state-voting-825979909451"
    # No environment prefix. This layer is ACCOUNT-scoped, not per-environment:
    # every environment pulls the same image from the same registry, which is
    # what makes "promote the digest, never rebuild" possible.
    key          = "global/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Layer     = "global"
      Owner     = var.owner
      Repo      = "venkata-siddardha/voting-app"
    }
  }
}
