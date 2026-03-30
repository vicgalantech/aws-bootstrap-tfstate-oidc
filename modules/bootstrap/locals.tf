locals {
  account_id              = data.aws_caller_identity.current.account_id
  region                  = data.aws_region.current.name
  tfstate_bucket_name     = "tfstate-${var.company_name}-${var.environment}-${local.account_id}"
  access_logs_bucket_name = "tfstate-${var.company_name}-${var.environment}-${local.account_id}-logs"
  cloudtrail_bucket_name  = "cloudtrail-${var.company_name}-${var.environment}-${local.account_id}"

  # OIDC subject claim pattern
  oidc_subject_claim = var.github_repo != "*" ? [
    "repo:${var.github_org}/${var.github_repo}:*"
    ] : [
    "repo:${var.github_org}/*"
  ]

  # Branch-restricted subject claims
  oidc_subject_claim_branches = [
    for branch in var.allowed_branches :
    var.github_repo != "*" ?
    "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${branch}" :
    "repo:${var.github_org}/*:ref:refs/heads/${branch}"
  ]
}
