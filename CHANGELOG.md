# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

### Added
- **Hybrid Terragrunt/Terraform CI/CD architecture** - Local development uses Terragrunt, CI/CD uses pure Terraform with dynamic variable extraction from HCL files
- **ADR-0004** - Architecture Decision Record documenting the hybrid approach rationale
- **Deploy job configuration verification** - Documentation in README Step 7 about ensuring workflow matches terragrunt.hcl
- **Backend.tf generation in CI/CD** - Workflow generates backend configuration dynamically to match Terragrunt behavior
- **Checkov security scanning** - Added security-scan job with SARIF output for GitHub Security tab integration
- **Checkov skip list documentation** - Documented all 12 skipped checks with justifications in README.md
- **Pre-commit hooks** - `.pre-commit-config.yaml` with terraform_fmt, terraform_validate, terraform_docs, tflint, checkov, terragrunt-hclfmt, detect-secrets
- **Future Improvements section** - Documented planned enhancements: Infracost cost estimation, scheduled drift detection, CloudTrail with CloudWatch/SNS alerting
- **TFLint configuration** - `.tflint.hcl` with AWS plugin and recommended rules
- **Terraform validate step** - Added to validate job in CI/CD workflow
- **SSM Parameter exports** - New `exports.tf` with SSM parameters for S3 bucket, KMS key, and IAM role ARNs for use by downstream projects
- **SSM permissions** - Added SSM Parameter Store read/write permissions to GitHub Actions IAM policy
- **ADR-0005** - Architecture Decision Record documenting SSM Parameter Store for cross-project exports

### Changed
- **State key path** - Changed from `{env}/bootstrap/terraform.tfstate` to `bootstrap/terraform.tfstate` (environment already in bucket name)
- **S3 Lifecycle (CKV_AWS_300)** - Added `abort_incomplete_multipart_upload` to CloudTrail and access_logs bucket lifecycle configurations
- **Terraform formatting** - Fixed formatting in `iam-policies.tf` and `s3-state.tf`
- **KMS Key Policy** - Removed explicit `terraform_state_kms_policy` document and `policy` attribute from `aws_kms_key.terraform_state`; using AWS default policy which grants root account full access and delegates to IAM policies

### Removed
- **ManagedBy tags** - Removed `ManagedBy` tag from all configuration files (terragrunt.hcl, workflow, variables.tf)
- **Separate Terragrunt plan step** - Removed to avoid variable mismatch errors with saved plans

### Fixed
- **Variable mismatch errors** - Resolved "Can't change variable when applying a saved plan" by switching to pure Terraform in CI/CD
- **Terraform wrapper incompatibility** - Bypassed `setup-terraform` wrapper issues that caused `signal: broken pipe` errors with Terragrunt
- **Backend configuration** - Fixed "Missing backend configuration" warning by generating `backend.tf` instead of using CLI flags

## [0.1.0] - 2026-04-09

### Added
- **Initial AWS Bootstrap module** with:
  - OIDC Identity Provider for GitHub Actions
  - IAM Role (`github-actions-terraform-{env}`) with OIDC trust policy
  - IAM Policy (`TerraformDeploymentPolicy-{env}`) with ARN-scoped permissions
  - S3 State Bucket (`tfstate-{company}-{env}-{account-id}`) with versioning and KMS encryption
  - S3 Access Log Bucket for audit trail
  - KMS Customer Managed Key for state encryption
  - Optional CloudTrail for OIDC + API audit logging

- **Terragrunt configuration** for multi-environment deployment:
  - Root configuration (`live/terragrunt.hcl`) with provider and backend generation
  - Common configuration (`live/common.hcl`) for shared variables
  - Environment-specific configurations (`live/dev/`, `live/qa/`, `live/prod/`)

- **GitHub Actions workflow** (`terraform-deploy.yml`):
  - Environment detection from branch names
  - Terraform validation and format checking
  - Security scanning with Checkov
  - Automated plan and apply

- **Architecture Decision Records (ADRs)**:
  - ADR-0001: ARN-based environment isolation instead of ABAC
  - ADR-0002: S3 native state locking instead of DynamoDB
  - ADR-0003: Organisation-wide OIDC role with broad IAM permissions

- **Documentation**:
  - Comprehensive README with deployment guide
  - Runbooks for common operations
  - Terragrunt environments documentation

### Security
- ARN-based environment isolation prevents cross-environment access
- KMS CMK with automatic rotation for state encryption
- S3 bucket policies enforce TLS 1.2+, block public access
- Session tagging required for audit trail
- Branch restrictions on OIDC role assumption
