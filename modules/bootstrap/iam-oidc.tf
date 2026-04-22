# ================================================
# OIDC Identity Provider for GitHub Actions
# ================================================

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = merge(var.tags, {
    Name = "github-actions-oidc-provider"
  })
}

# ================================================
# IAM Role for GitHub Actions with OIDC
# ================================================

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.enable_branch_restriction ? local.oidc_subject_claim_branches : local.oidc_subject_claim
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-terraform-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  description        = "GitHub Actions OIDC role for ${var.environment} environment"

  tags = merge(var.tags, {
    Name = "github-actions-terraform-${var.environment}"
  })
}

# ================================================
# Policy Attachment
# ================================================

resource "aws_iam_role_policy_attachment" "github_actions_terraform_deployment" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_deployment.arn
}
