# =============================================================================
# Common configuration shared across ALL environments.
#
# Edit these values once; all environment units inherit them automatically.
# =============================================================================

locals {
  aws_region   = "eu-west-1"
  company_name = "yourcompany"     # S3 bucket pattern: tfstate-{company}-{env}-{account}
  github_org   = "your-github-org" # GitHub organisation name
  github_repo  = "*"           # "*" = all repos in org; or a specific repo name

  # Branch restriction settings (applied to every environment)
  enable_branch_restriction = false
  allowed_branches          = ["main", "develop", "release/*", "feature/*"]
}
