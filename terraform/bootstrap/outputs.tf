output "state_bucket" {
  description = "Name of the S3 bucket holding remote state. Matches the `bucket` in each layer's backend block."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "Region the state bucket lives in."
  value       = var.region
}

output "account_id" {
  description = "AWS account ID these resources were created in. Sanity-check it is the one you meant."
  value       = data.aws_caller_identity.current.account_id
}
