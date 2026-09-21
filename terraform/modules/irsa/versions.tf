terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Needed to read the OIDC endpoint's TLS certificate for the thumbprint.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
