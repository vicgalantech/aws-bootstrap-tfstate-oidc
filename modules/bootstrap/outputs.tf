output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = local.region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "cloudtrail_name" {
  description = "CloudTrail name (if enabled)"
  value       = var.enable_cloudtrail ? aws_cloudtrail.centralized_audit[0].name : null
}

output "cloudtrail_bucket" {
  description = "CloudTrail S3 bucket name (if enabled)"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].id : null
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN (if enabled)"
  value       = var.enable_cloudtrail ? aws_cloudtrail.centralized_audit[0].arn : null
}

output "terraform_state_kms_alias" {
  description = "KMS alias ARN for the state bucket encryption key"
  value       = aws_kms_alias.terraform_state.arn
}

output "terraform_state_access_logs_bucket" {
  description = "S3 bucket receiving access logs for the state bucket"
  value       = aws_s3_bucket.access_logs.id
}

output "backend_config" {
  description = "Backend configuration for downstream projects"
  value = {
    bucket       = aws_s3_bucket.terraform_state.id
    key          = "bootstrap/terraform.tfstate"
    region       = local.region
    encrypt      = true
    use_lockfile = true
  }
}

output "cloudtrail_kms_alias" {
  description = "KMS alias ARN for CloudTrail log encryption (null when CloudTrail is disabled)"
  value       = var.enable_cloudtrail ? aws_kms_alias.cloudtrail[0].arn : null
}

output "github_variable_setup" {
  description = "GitHub repository variable to set: name → value"
  value = {
    name  = "AWS_ROLE_ARN_${upper(var.environment)}"
    value = aws_iam_role.github_actions.arn
  }
}

output "next_steps" {
  description = "Next steps after bootstrap"
  value       = <<-EOT

  ========================================
  Bootstrap Complete!
  ========================================

  Resources Created:
  - OIDC Provider: ${aws_iam_openid_connect_provider.github_actions.arn}
  - IAM Role: ${aws_iam_role.github_actions.name}
  - S3 State Bucket: ${aws_s3_bucket.terraform_state.id}
  ${var.enable_cloudtrail ? "- CloudTrail: ${aws_cloudtrail.centralized_audit[0].name} (enabled)" : "- CloudTrail: disabled"}

  Next: Set GitHub variable AWS_ROLE_ARN_${upper(var.environment)} = ${aws_iam_role.github_actions.arn}

  EOT
}
