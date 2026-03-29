# =============================================================================
# Dev environment — account-specific settings
# =============================================================================

locals {
  environment = "dev"
  account_id  = "002332700133"  # Replace with your AWS account ID
  aws_profile = "bootstrap-dev" # AWS CLI profile with bootstrap-dev IAM user credentials
}
