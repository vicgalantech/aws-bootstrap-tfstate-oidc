# =============================================================================
# Common configuration shared across ALL environments.
#
# Edit these values once; all environment units inherit them automatically.
# =============================================================================

locals {
  aws_region   = "eu-west-1"
  company_name = "vicgalantech" # Prefix for S3 buckets: {company}-tfstate-{env}-{account}
  github_org   = "vicgalantech" # GitHub organisation name
  github_repo  = "*"               # "*" = all repos in org; or a specific repo name

  # Branch restriction settings (applied to every environment)
  enable_branch_restriction = false
  allowed_branches          = ["main", "develop", "release/*", "feature/*"]
}
