variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, qa, prod)"
  type        = string
  validation {
    condition     = can(regex("^(dev|qa|prod)$", var.environment))
    error_message = "Environment must be dev, qa, or prod."
  }
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (optional - if not provided, allows all repos in org)"
  type        = string
  default     = "*"
}

variable "company_name" {
  description = "Company name prefix for S3 buckets (lowercase alphanumeric and hyphens only, 2-20 chars)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,18}[a-z0-9]$", var.company_name))
    error_message = "company_name must be 2-20 chars, lowercase alphanumeric and hyphens only, no leading/trailing hyphens. S3 bucket names inherit this prefix."
  }
}

variable "enable_branch_restriction" {
  description = "Enable branch-based restrictions in trust policy"
  type        = bool
  default     = false
}

variable "allowed_branches" {
  description = "List of allowed branch patterns (only used if enable_branch_restriction is true)"
  type        = list(string)
  default     = ["main", "develop", "release/*"]
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail logging for OIDC authentication and AWS API calls"
  type        = bool
  default     = true
}

variable "cloudtrail_retention_days" {
  description = "Number of days to retain CloudTrail logs in S3"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose = "GitHubActionsOIDC"
  }
}
