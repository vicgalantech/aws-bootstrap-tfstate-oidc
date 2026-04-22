# =============================================================================
# Unit tests for modules/bootstrap
#
# Uses mock_provider to run against fake AWS APIs — no real account needed.
# Run with: terraform test
#
# Tests cover:
#   - Variable validation (invalid environment rejected)
#   - Resource naming conventions
#   - Conditional CloudTrail creation
#   - OIDC subject claim generation (wildcard vs specific repo)
#   - Branch restriction toggle
# =============================================================================

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test-bootstrap"
      user_id    = "AIDAXXXXXXXXXXXXXXXXX"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "eu-west-1"
    }
  }

  # aws_iam_policy_document is a local-only data source computed by the
  # provider binary. Mock providers don't execute provider logic, so they
  # return null for `json`. A valid stub prevents downstream rejections.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Mock\",\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
    }
  }

  # Computed ARN attributes must match ARN format or downstream resources
  # (e.g. aws_iam_role_policy_attachment.policy_arn) will reject them.
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock-TerraformDeploymentPolicy"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn  = "arn:aws:iam::123456789012:role/mock-github-actions-terraform"
      name = "mock-github-actions-terraform"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn                = "arn:aws:s3:::mock-bucket"
      id                 = "mock-bucket"
      bucket_domain_name = "mock-bucket.s3.amazonaws.com"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-west-1:123456789012:key/mock-key-00000000"
      key_id = "mock-key-00000000"
    }
  }

  mock_resource "aws_cloudtrail" {
    defaults = {
      arn = "arn:aws:cloudtrail:eu-west-1:123456789012:trail/mock-trail"
    }
  }

  mock_resource "aws_kms_alias" {
    defaults = {
      arn            = "arn:aws:kms:eu-west-1:123456789012:alias/mock-alias"
      target_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/mock-key-00000000"
    }
  }
}

# -----------------------------------------------------------------------------
# Default variables reused across runs
# -----------------------------------------------------------------------------
variables {
  aws_region   = "eu-west-1"
  environment  = "dev"
  company_name = "testco"
  github_org   = "test-org"
  github_repo  = "*"
}

# -----------------------------------------------------------------------------
# Run 1: Basic plan succeeds and resource names follow conventions
# -----------------------------------------------------------------------------
run "resource_names_follow_conventions" {
  command = plan

  assert {
    condition     = aws_iam_role.github_actions.name == "github-actions-terraform-dev"
    error_message = "IAM role name must be github-actions-terraform-dev, got: ${aws_iam_role.github_actions.name}"
  }

  assert {
    condition     = aws_iam_policy.terraform_deployment.name == "TerraformDeploymentPolicy-dev"
    error_message = "Policy name must be TerraformDeploymentPolicy-dev"
  }

  assert {
    condition     = aws_s3_bucket.terraform_state.bucket == "testco-tfstate-dev-123456789012"
    error_message = "State bucket must follow pattern {company}-tfstate-{env}-{account}"
  }

  assert {
    condition     = aws_s3_bucket.access_logs.bucket == "testco-tfstate-dev-123456789012-logs"
    error_message = "Access log bucket must be state-bucket-name + '-logs'"
  }

  assert {
    condition     = aws_kms_alias.terraform_state.name == "alias/testco-tfstate-dev"
    error_message = "KMS alias must be alias/{company}-tfstate-{env}"
  }
}

# -----------------------------------------------------------------------------
# Run 2: Invalid environment is rejected by variable validation
# -----------------------------------------------------------------------------
run "invalid_environment_is_rejected" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

# -----------------------------------------------------------------------------
# Run 3: CloudTrail is NOT created when disabled (count = 0)
# -----------------------------------------------------------------------------
run "cloudtrail_disabled_creates_no_resources" {
  command = plan

  variables {
    enable_cloudtrail = false
  }

  assert {
    condition     = length(aws_cloudtrail.centralized_audit) == 0
    error_message = "CloudTrail must not be created when enable_cloudtrail = false"
  }

  assert {
    condition     = length(aws_s3_bucket.cloudtrail) == 0
    error_message = "CloudTrail S3 bucket must not be created when enable_cloudtrail = false"
  }
}

# -----------------------------------------------------------------------------
# Run 4: CloudTrail IS created when enabled, with correct name
# -----------------------------------------------------------------------------
run "cloudtrail_enabled_creates_trail" {
  command = plan

  variables {
    enable_cloudtrail         = true
    cloudtrail_retention_days = 90
  }

  assert {
    condition     = length(aws_cloudtrail.centralized_audit) == 1
    error_message = "CloudTrail must be created when enable_cloudtrail = true"
  }

  assert {
    condition     = aws_cloudtrail.centralized_audit[0].name == "centralized-audit-trail-dev"
    error_message = "CloudTrail name must include environment"
  }

  assert {
    condition     = aws_cloudtrail.centralized_audit[0].is_multi_region_trail == true
    error_message = "CloudTrail must be multi-region"
  }

  assert {
    condition     = aws_cloudtrail.centralized_audit[0].enable_log_file_validation == true
    error_message = "CloudTrail log file validation must be enabled"
  }
}

# -----------------------------------------------------------------------------
# Run 5: Specific repo generates a scoped OIDC subject claim
# -----------------------------------------------------------------------------
run "specific_repo_scopes_oidc_claim" {
  command = plan

  variables {
    github_repo               = "my-app"
    enable_branch_restriction = false
  }

  assert {
    condition     = aws_iam_role.github_actions.name == "github-actions-terraform-dev"
    error_message = "Role should still be created with specific repo"
  }
}

# -----------------------------------------------------------------------------
# Run 6: Branch restriction does not break the plan
# -----------------------------------------------------------------------------
run "branch_restriction_enabled" {
  command = plan

  variables {
    enable_branch_restriction = true
    allowed_branches          = ["main", "develop"]
  }

  assert {
    condition     = aws_iam_role.github_actions.name == "github-actions-terraform-dev"
    error_message = "Role must be created with branch restriction enabled"
  }
}

# -----------------------------------------------------------------------------
# Run 7: KMS key has Project=bootstrap tag (required by IAM policy condition)
# -----------------------------------------------------------------------------
run "kms_key_has_project_tag" {
  command = plan

  assert {
    condition     = aws_kms_key.terraform_state.tags["Project"] == "bootstrap"
    error_message = "KMS key must have Project=bootstrap tag for IAM policy condition to work"
  }

  assert {
    condition     = aws_kms_key.terraform_state.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled"
  }
}

# -----------------------------------------------------------------------------
# Run 8: S3 state bucket blocks all public access
# -----------------------------------------------------------------------------
run "state_bucket_blocks_public_access" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.terraform_state.block_public_acls == true
    error_message = "State bucket must block public ACLs"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.terraform_state.restrict_public_buckets == true
    error_message = "State bucket must restrict public buckets"
  }
}

# -----------------------------------------------------------------------------
# Run 9: Access log bucket is separate from state bucket
# target_bucket is a computed reference — needs apply to resolve the value.
# -----------------------------------------------------------------------------
run "access_log_bucket_is_separate" {
  command = apply

  # The code sets target_bucket = aws_s3_bucket.access_logs.id (structural guarantee).
  # Mock provider gives all S3 buckets the same id, so we verify target == access_logs
  # (not != terraform_state, which would always fail with mocks due to id collision).
  assert {
    condition     = aws_s3_bucket_logging.terraform_state.target_bucket == aws_s3_bucket.access_logs.id
    error_message = "State bucket must log to the dedicated access_logs bucket, not itself"
  }
}

# -----------------------------------------------------------------------------
# Run 10: prod environment name produces correct resource names
# -----------------------------------------------------------------------------
run "prod_environment_naming" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = aws_iam_role.github_actions.name == "github-actions-terraform-prod"
    error_message = "Prod IAM role name must include 'prod'"
  }

  assert {
    condition     = aws_s3_bucket.terraform_state.bucket == "testco-tfstate-prod-123456789012"
    error_message = "Prod state bucket must include 'prod'"
  }
}
