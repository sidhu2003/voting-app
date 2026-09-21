terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# NOTE: a module declares which providers it REQUIRES but must never CONFIGURE one.
# No `provider "aws" { ... }` block belongs in here. The calling layer configures the
# provider and passes it down implicitly. A module with its own provider block cannot
# be used twice with different regions, and cannot be cleanly destroyed.
