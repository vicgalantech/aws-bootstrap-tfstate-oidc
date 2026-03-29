# =============================================================================
# Prod environment — account-specific settings
# =============================================================================

locals {
  environment = "prod"
  account_id  = "YOUR_PROD_ACCOUNT_ID" # Replace with your AWS account ID
  aws_profile = "bootstrap-prod"       # AWS CLI profile with bootstrap-prod IAM user credentials
}
