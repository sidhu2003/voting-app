#
# Remote state backend.
#
# Everything else in this repo stores its state in the bucket created here.
# Run this ONCE, then never think about it again.
#
# Why remote state at all: state is the source of truth mapping your HCL to real
# AWS resources. On your laptop it is a single file you can lose, cannot share, and
# cannot lock. In S3 it is versioned, encrypted, shared with CI, and locked so two
# applies cannot race.
#

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # Guardrail: makes `terraform destroy` refuse to delete this bucket.
  # Deleting your state bucket orphans every resource in every layer — Terraform
  # forgets they exist but AWS keeps billing you.
  #
  # To genuinely tear this down: comment this block out, apply, THEN destroy.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is the one that actually saves you. If a bad apply corrupts state,
# you restore the previous object version. Without it, there is no undo.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State files contain secrets in plaintext — DB passwords, tokens, private keys.
# Encrypting at rest is non-negotiable.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old state versions pile up forever otherwise. Keep 90 days of undo, then expire.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
