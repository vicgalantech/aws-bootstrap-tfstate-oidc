# =============================================================================
# QA environment — account-specific settings
# =============================================================================

locals {
  environment = "qa"
  account_id  = "YOUR_QA_ACCOUNT_ID" # Replace with your AWS account ID
  aws_profile = "bootstrap-qa"       # AWS CLI profile with bootstrap-qa IAM user credentials
}
