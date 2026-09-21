#
# IRSA — IAM Roles for Service Accounts.
#
# THE PROBLEM: a pod needs to call an AWS API. The lazy answers are to bake an
# access key into a Secret, or to attach the permission to the NODE role — which
# hands it to every pod on that node, including anything compromised.
#
# THE MECHANISM: the cluster issues each pod a short-lived signed JWT describing
# its service account. IAM is told to trust that cluster's signing key. The pod
# trades the JWT for temporary AWS credentials. No stored secret, and permissions
# are scoped to exactly one service account.
#
# The chain:
#   1. Cluster publishes an OIDC discovery endpoint     (EKS does this for you)
#   2. IAM is told to trust it                          (aws_iam_openid_connect_provider)
#   3. A role's trust policy names ONE service account  (the conditions below)
#

locals {
  tags = merge(var.tags, { Module = "irsa" })

  # Condition keys in the trust policy use the issuer host without the scheme.
  oidc_host = replace(var.oidc_issuer_url, "https://", "")

  # Flatten {role => [policy...]} into {"role:policy" => {...}} so each
  # attachment gets a stable for_each key. Without a stable key, adding one
  # policy would churn unrelated attachments.
  role_policy_pairs = merge([
    for key, sa in var.service_accounts : {
      for arn in sa.policy_arns : "${key}:${arn}" => {
        role_key   = key
        policy_arn = arn
      }
    }
  ]...)
}


# ----------------------------------------------------------------------------
# Register the cluster as an OIDC identity provider in IAM.
#
# Exactly one per cluster. This is why the EKS module call sets
# enable_irsa = false — otherwise both it and this module create one, and the
# second fails with EntityAlreadyExists.
# ----------------------------------------------------------------------------

data "tls_certificate" "oidc" {
  url = var.oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "this" {
  url = var.oidc_issuer_url

  # The audience the cluster mints tokens for.
  client_id_list = ["sts.amazonaws.com"]

  # AWS stopped verifying this thumbprint for EKS issuers, but the argument is
  # still required. Reading it from the live certificate keeps it honest.
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = merge(local.tags, { Name = "${var.name}-oidc" })
}


# ----------------------------------------------------------------------------
# One role per service account.
#
# The trust policy is the whole lesson. BOTH conditions are required:
#
#   :sub  pins the role to one namespace + service account. Without it, ANY
#         service account in the cluster can assume this role.
#   :aud  pins the token audience. Without it, a token minted for a different
#         audience is accepted.
#
# Neither omission produces an error. They silently over-grant, which is why a
# security reviewer checks this first.
# ----------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  for_each = var.service_accounts

  statement {
    sid     = "AllowServiceAccountToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.service_accounts

  name               = "${var.name}-${each.key}"
  description        = "IRSA role for ${each.value.namespace}/${each.value.service_account}"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = merge(local.tags, {
    Name           = "${var.name}-${each.key}"
    ServiceAccount = "${each.value.namespace}/${each.value.service_account}"
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.role_policy_pairs

  role       = aws_iam_role.this[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
