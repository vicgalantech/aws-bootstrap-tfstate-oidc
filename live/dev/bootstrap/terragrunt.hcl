# =============================================================================
# Dev bootstrap Terragrunt unit
#
# Deploys: modules/bootstrap → dev AWS account
#
# First-time deploy (bucket does not exist yet):
#   export AWS_PROFILE=bootstrap-dev
#   terragrunt apply --terragrunt-no-auto-init
#   terragrunt init -migrate-state
#
# Subsequent deploys (bucket exists):
#   export AWS_PROFILE=bootstrap-dev
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

inputs = {
  aws_region   = local.common.locals.aws_region
  environment  = local.account.locals.environment
  company_name = local.common.locals.company_name
  github_org   = local.common.locals.github_org
  github_repo  = local.common.locals.github_repo

  enable_branch_restriction = local.common.locals.enable_branch_restriction
  allowed_branches          = local.common.locals.allowed_branches

  enable_cloudtrail         = false
  cloudtrail_retention_days = 90

  tags = {
    ManagedBy   = "Terragrunt"
    Environment = local.account.locals.environment
    Team        = "DevOps"
    Project     = "bootstrap"
  }
}
