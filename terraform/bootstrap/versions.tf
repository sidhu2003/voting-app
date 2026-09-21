terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # NO backend block here — this is deliberate.
  #
  # This layer CREATES the S3 bucket that every other layer stores its state in.
  # It cannot store its own state in a bucket that does not exist yet. So this one
  # layer, and only this one, keeps local state.
  #
  # That is the "chicken and egg" of Terraform backends. Everyone hits it once.
}

provider "aws" {
  region = var.region

  # default_tags applies these to every taggable resource this provider creates.
  # Real orgs enforce tagging for cost allocation and ownership — set it once here
  # rather than remembering it on every resource.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Layer     = "bootstrap"
      Owner     = var.owner
    }
  }
}
