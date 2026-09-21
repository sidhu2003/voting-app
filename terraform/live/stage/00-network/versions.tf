terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "terraform-state-voting-825979909451"

    # The key is the path inside the bucket. Mirror your directory layout here so
    # that finding a layer's state is obvious. Every layer MUST have a unique key —
    # two layers sharing a key will overwrite each other's state, which is about the
    # worst thing that can happen to you in Terraform.
    key    = "stage/00-network/terraform.tfstate"
    region = "ap-south-1"

    encrypt = true

    # State locking via a lockfile object in S3 itself.
    # Prevents two applies (you and CI) racing and corrupting state.
    #
    # Older tutorials tell you to create a DynamoDB table for this. That was the
    # only way before Terraform 1.10; it is deprecated now. If an interviewer asks
    # about DynamoDB state locking, this is the answer that shows you are current.
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Layer       = "00-network"
      Owner       = var.owner
      Repo        = "venkata-siddardha/voting-app"
    }
  }
}
