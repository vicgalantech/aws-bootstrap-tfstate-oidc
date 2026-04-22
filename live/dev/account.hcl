# =============================================================================
# Dev environment — account-specific settings
# =============================================================================

locals {
  environment = "dev"
  account_id  = get_aws_account_id() # Dynamically retrieved from AWS credentials
  aws_profile = "bootstrap-dev"      # AWS CLI profile with bootstrap-dev IAM user credentials
}
