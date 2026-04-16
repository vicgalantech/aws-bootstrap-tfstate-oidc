# ================================================
# SSM Parameter Store Exports
# ================================================
# Export infrastructure values to SSM Parameter Store for use by other projects.
# This enables loose coupling between the bootstrap module and downstream projects.
# Note: Using String type (not SecureString) because these are non-sensitive infrastructure
# references (ARNs, bucket names, region) that need to be easily readable by other projects.

# checkov:skip=CKV2_AWS_34:Parameter contains non-sensitive infrastructure references, not secrets
resource "aws_ssm_parameter" "tfstate_bucket_name" {
  name        = "/${var.environment}/bootstrap/tfstate-bucket-name"
  description = "Terraform state S3 bucket name for ${var.environment}"
  type        = "String"
  value       = aws_s3_bucket.terraform_state.id

  tags = merge(var.tags, {
    Name          = "tfstate-bucket-name-${var.environment}"
    resource-type = "ssm-parameter"
  })
}

# checkov:skip=CKV2_AWS_34:Parameter contains non-sensitive infrastructure references, not secrets
resource "aws_ssm_parameter" "tfstate_bucket_arn" {
  name        = "/${var.environment}/bootstrap/tfstate-bucket-arn"
  description = "Terraform state S3 bucket ARN for ${var.environment}"
  type        = "String"
  value       = aws_s3_bucket.terraform_state.arn

  tags = merge(var.tags, {
    Name          = "tfstate-bucket-arn-${var.environment}"
    resource-type = "ssm-parameter"
  })
}

# checkov:skip=CKV2_AWS_34:Parameter contains non-sensitive infrastructure references, not secrets
resource "aws_ssm_parameter" "tfstate_kms_key_arn" {
  name        = "/${var.environment}/bootstrap/tfstate-kms-key-arn"
  description = "KMS key ARN for Terraform state encryption in ${var.environment}"
  type        = "String"
  value       = aws_kms_key.terraform_state.arn

  tags = merge(var.tags, {
    Name          = "tfstate-kms-key-arn-${var.environment}"
    resource-type = "ssm-parameter"
  })
}

# checkov:skip=CKV2_AWS_34:Parameter contains non-sensitive infrastructure references, not secrets
resource "aws_ssm_parameter" "tfstate_kms_key_alias" {
  name        = "/${var.environment}/bootstrap/tfstate-kms-key-alias"
  description = "KMS key alias for Terraform state encryption in ${var.environment}"
  type        = "String"
  value       = aws_kms_alias.terraform_state.name

  tags = merge(var.tags, {
    Name          = "tfstate-kms-key-alias-${var.environment}"
    resource-type = "ssm-parameter"
  })
}

# checkov:skip=CKV2_AWS_34:Parameter contains non-sensitive infrastructure references, not secrets
resource "aws_ssm_parameter" "github_actions_role_arn" {
  name        = "/${var.environment}/bootstrap/github-actions-role-arn"
  description = "GitHub Actions IAM role ARN for ${var.environment}"
  type        = "String"
  value       = aws_iam_role.github_actions.arn

  tags = merge(var.tags, {
    Name          = "github-actions-role-arn-${var.environment}"
    resource-type = "ssm-parameter"
  })
}

# checkov:skip=CKV2_AWS_34:Parameter contains non-sensitive infrastructure references, not secrets
resource "aws_ssm_parameter" "aws_region" {
  name        = "/${var.environment}/bootstrap/aws-region"
  description = "AWS region for ${var.environment}"
  type        = "String"
  value       = local.region

  tags = merge(var.tags, {
    Name          = "aws-region-${var.environment}"
    resource-type = "ssm-parameter"
  })
}
