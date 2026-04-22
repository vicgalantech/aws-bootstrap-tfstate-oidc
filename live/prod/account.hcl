# =============================================================================
# Prod environment — account-specific settings
# =============================================================================

locals {
  environment = "prod"
  account_id  = get_aws_account_id() # Dynamically retrieved from AWS credentials
  aws_profile = "bootstrap-prod"     # AWS CLI profile with bootstrap-prod IAM user credentials
}
