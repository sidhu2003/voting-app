terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    random = {
      source = "hashicorp/random"
    }

    tls = {
      source = "hashicorp/tls"
    }

    cloudinit = {
      source = "hashicorp/cloudinit"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }

  backend "s3" {
    bucket = "terraform-backend175"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}