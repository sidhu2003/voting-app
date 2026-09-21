#
# Account-scoped: the container registry.
#
# Deliberately NOT per-environment. All three environments pull the SAME image;
# duplicating the registry per environment would break the guarantee that what
# runs in prod is byte-identical to what ran in stage.
#
# The GitHub OIDC provider and CI role are managed by hand, outside Terraform.
# See docs/ECR-OIDC.md.
#

data "aws_caller_identity" "current" {}

locals {
  registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name = "voteapp-${each.value}"

  # IMMUTABLE. A tag, once pushed, can never be repointed at different content.
  #
  # Deploys reference digests, so this is defence in depth rather than the
  # primary control — but it costs nothing and it closes the gap where someone
  # later deploys by tag and silently loses the guarantee.
  #
  # This requires tags to be unique per BUILD, not per commit: rebuilding the
  # same source against a patched base image produces different bytes and must
  # therefore get a different tag. CI tags with ${GITHUB_SHA}-${GITHUB_RUN_NUMBER}
  # for exactly that reason.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # Free basic scanning on every push.
    scan_on_push = true
  }

  # Stops `terraform destroy` deleting images the cluster is still running.
  force_delete = false

  tags = { Name = "voteapp-${each.value}" }
}

# Images accumulate forever otherwise, at $0.10/GB/month. Rules are evaluated in
# priority order and each image matches at most one.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the ${var.image_retention_count} most recent tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
