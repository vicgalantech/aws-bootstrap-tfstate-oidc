# =============================================================================
# Prod bootstrap Terragrunt unit
#
# Deploys: modules/bootstrap → prod AWS account
#
# First-time deploy (bucket does not exist yet):
#   export AWS_PROFILE=bootstrap-prod
#   terragrunt apply --terragrunt-no-auto-init -backend=false
#   terragrunt init -migrate-state
#
# Subsequent deploys (bucket exists):
#   export AWS_PROFILE=bootstrap-prod
#   terragrunt plan
#   terragrunt apply
# =============================================================================

include "root" {
  path = find_in_parent_folders()
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

terraform {
  source = "../../../modules/bootstrap"
}

# -----------------------------------------------------------------------------
# Remote state configuration — COMMENTED for first-time deployment
#
# FIRST-TIME DEPLOY: Keep this commented. Use local state to create the bucket.
# AFTER BUCKET EXISTS: Uncomment this block and run `terragrunt init -migrate-state`
# -----------------------------------------------------------------------------
# remote_state {
#   backend = "s3"
#   generate = {
#     path      = "backend.tf"
#     if_exists = "overwrite_terragrunt"
#   }
#   config = {
#     bucket       = "tfstate-${local.common.locals.company_name}-${local.account.locals.environment}-${local.account.locals.account_id}"
#     key          = "bootstrap/terraform.tfstate"
#     region       = local.common.locals.aws_region
#     encrypt      = true
#     use_lockfile = true

#     # Do NOT let Terragrunt auto-create the bucket — the bootstrap module owns it.
#     skip_bucket_versioning             = true
#     skip_bucket_ssencryption           = true
#     skip_bucket_accesslogging          = true
#     skip_bucket_root_access            = true
#     skip_bucket_enforced_tls           = true
#     skip_bucket_public_access_blocking = true
#   }
# }

inputs = {
  aws_region   = local.common.locals.aws_region
  environment  = local.account.locals.environment
  company_name = local.common.locals.company_name
  github_org   = local.common.locals.github_org
  github_repo  = local.common.locals.github_repo

  enable_branch_restriction = local.common.locals.enable_branch_restriction
  allowed_branches          = local.common.locals.allowed_branches

  enable_cloudtrail         = false # Enable for prod audit compliance
  cloudtrail_retention_days = 365

  tags = {
    Environment = local.account.locals.environment
    Team        = "DevOps"
    Project     = "bootstrap"
  }
}
