# =============================================================================
# Root Terragrunt Configuration
#
# Inherited by all child modules via: include "root" { path = find_in_parent_folders() }
#
# Responsibilities:
#   - Generate the AWS provider block for each module
#   - Configure the S3 remote state backend for each module
#   - Read common.hcl and account.hcl to build shared locals
# =============================================================================

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  account = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  aws_region   = local.common.locals.aws_region
  company_name = local.common.locals.company_name
  environment  = local.account.locals.environment
  account_id   = local.account.locals.account_id
  aws_profile  = local.account.locals.aws_profile

  # GitHub Actions sets CI=true. When running in CI, configure-aws-credentials@v4
  # injects OIDC credentials as environment variables — not a named profile.
  # Setting profile = "..." in the provider would override those env vars and cause
  # a "profile not found" error. Omit the profile directive entirely in CI.
  is_ci = get_env("CI", "false") == "true"
}

# -----------------------------------------------------------------------------
# Generate provider.tf in the working directory for each module.
# The module's versions.tf only declares required_providers; the actual
# provider configuration lives here so it can be parameterised per environment.
# -----------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      # In CI (GitHub Actions), configure-aws-credentials@v4 sets AWS_* env vars.
      # The profile directive must be absent so Terraform reads those env vars.
      # Locally, the named profile is used for developer authentication.
      ${local.is_ci ? "# profile: omitted — OIDC ambient credentials active (CI=true)" : "profile = \"${local.aws_profile}\""}

      default_tags {
        tags = {
          Environment = "${local.environment}"
          Project     = "bootstrap"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Minimum Terragrunt version
# -----------------------------------------------------------------------------
terraform_version_constraint  = ">= 1.10.0"
terragrunt_version_constraint = ">= 0.67.0"
