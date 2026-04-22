# =============================================================================
# QA environment — account-specific settings
# =============================================================================

locals {
  environment = "qa"
  account_id  = get_aws_account_id() # Dynamically retrieved from AWS credentials
  aws_profile = "bootstrap-qa"       # AWS CLI profile with bootstrap-qa IAM user credentials
}
