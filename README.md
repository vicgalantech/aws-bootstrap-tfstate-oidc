# AWS Bootstrap: Terraform State & GitHub OIDC

[![AWS](https://img.shields.io/badge/AWS-IAM%20%7C%20OIDC-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.10%2B-7B42BC?logo=terraform)](https://www.terraform.io/)
[![Terragrunt](https://img.shields.io/badge/Terragrunt-0.67%2B-7B42BC)](https://terragrunt.gruntwork.io/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Production-ready Terragrunt implementation for AWS GitHub OIDC federation with keyless CI/CD authentication. Deploys IAM roles, S3 state buckets, KMS encryption, and CloudTrail audit logging across multi-environment infrastructure (dev/qa/prod).

**🎯 What this solves:** Eliminates long-lived AWS access keys in GitHub Secrets. Every `terraform plan` and `apply` uses temporary credentials (1-hour TTL) issued by AWS STS via OIDC federation.

---

## 📋 Table of Contents

- [What It Creates](#what-it-creates)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start (10 minutes)](#quick-start-10-minutes)
- [Complete Deployment Guide](#complete-deployment-guide)
  - [Step 1: Create Bootstrap IAM User](#step-1-create-bootstrap-iam-user)
  - [Step 2: Configure Terragrunt](#step-2-configure-terragrunt)
  - [Step 3: First-Time Deploy](#step-3-first-time-deploy)
  - [Step 4: Migrate State to S3](#step-4-migrate-state-to-s3)
  - [Step 5: Verify Setup](#step-5-verify-setup)
  - [Step 6: Configure GitHub Secrets](#step-6-configure-github-secrets)
  - [Step 7: Test GitHub Actions](#step-7-test-github-actions)
- [Architecture](#architecture)
- [Multi-Environment Setup](#multi-environment-setup)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Expanding to New Projects](#expanding-to-new-projects)
- [Contributing](#contributing)

---

## What It Creates

Per AWS account (run once per environment), managed by Terragrunt:

| Resource | Name Pattern | Purpose |
|---|---|---|
| **OIDC Identity Provider** | `token.actions.githubusercontent.com` | Keyless GitHub Actions authentication |
| **IAM Role** | `github-actions-terraform-{env}` | CI/CD role assumed by workflows |
| **IAM Policy** | `TerraformDeploymentPolicy-{env}` | ARN-scoped permissions with environment isolation |
| **S3 State Bucket** | `tfstate-{company}-{env}-{account-id}` | Versioned, KMS-encrypted, S3 native locking |
| **S3 Access Log Bucket** | `tfstate-{company}-{env}-{account-id}-logs` | Audit trail for state bucket access (prevents self-logging loop) |
| **KMS CMK** | `terraform-state-{env}` | Customer-managed key for state encryption |
| **CloudTrail** *(optional)* | `centralized-audit-trail-{env}` | Immutable OIDC + API audit logs (Object Lock) |

**Security Features:**
- ✅ ARN-based environment isolation — dev role cannot access qa/prod resources
- ✅ `aws:PrincipalTag/environment` condition keys prevent cross-environment operations
- ✅ KMS CMK with automatic rotation for state encryption
- ✅ S3 bucket policies enforce TLS 1.2+, block public access
- ✅ Versioning + lifecycle rules (90-day noncurrent object expiration)
- ✅ Session tagging required (`Project`, `environment`, `github-actor`)

---

## Repository Structure

```
aws-bootstrap-tfstate-oidc/
├── modules/bootstrap/          # Terraform module (single source of truth)
│   ├── iam-oidc.tf            # OIDC provider + GitHub Actions role
│   ├── iam-policies.tf        # Deployment policy (ARN-scoped)
│   ├── s3-state.tf            # State bucket + KMS key + access logs
│   ├── cloudtrail.tf          # Optional audit trail
│   ├── variables.tf
│   ├── outputs.tf
│   └── tests/unit.tftest.hcl  # Terraform test suite (10/10 passing)
│
├── live/                       # Terragrunt environment configuration
│   ├── terragrunt.hcl         # Root: provider + backend generation
│   ├── common.hcl             # Shared: company_name, github_org, region
│   ├── dev/
│   │   ├── account.hcl        # account_id, aws_profile
│   │   └── bootstrap/terragrunt.hcl
│   ├── qa/ ...
│   └── prod/ ...
│
├── .github/workflows/
│   └── terraform-deploy.yml   # CI/CD: validate, scan, plan, apply, drift
│
└── README.md                   # This file
```

---

## Prerequisites

### Required Tools

| Tool | Version | Install |
|---|---|---|
| **Terraform** | ≥ 1.10.0 | [Official](https://developer.hashicorp.com/terraform/downloads) or `tfenv` |
| **Terragrunt** | ≥ 0.67.0 | [Releases](https://github.com/gruntwork-io/terragrunt/releases) |
| **AWS CLI** | ≥ 2.x | [Official](https://aws.amazon.com/cli/) |
| **Git** | any | Included on most systems |

Verify installations:
```bash
terraform version
terragrunt --version
aws --version
git --version
```

### GitHub Requirements

- GitHub organization or personal account
- Repository with Actions enabled
- Admin access (to set repository secrets)

---

## Quick Start (10 minutes)

**Test dev environment first, then replicate to qa/prod.**

### 1. Configure Settings

Edit `live/common.hcl`:
```hcl
locals {
  company_name = "yourcompany"     # S3 bucket pattern: tfstate-{company}-{env}-{account}
  github_org   = "your-github-org"
  aws_region   = "eu-west-1"
}
```

Edit `live/dev/account.hcl`:
```hcl
locals {
  environment = "dev"
  account_id  = get_aws_account_id() # Dynamically retrieved from AWS credentials
  aws_profile = "bootstrap-dev"
}
```

### 2. First-Time Deploy

```bash
# Before doing this step, be sure that you have created the AWS profile "bootstrap-dev". If you do not know how to do it check the step: Create Bootstrap IAM User
export AWS_PROFILE=bootstrap-dev
cd live/dev/bootstrap

# Apply with local state (bucket doesn't exist yet)
# Step 1: Verify you're in the right account
aws sts get-caller-identity
 
# Step 2: Initialize WITHOUT remote backend (local state)
terragrunt init -backend=false
 
# Step 3: Review what will be created
terragrunt plan
 
# Step 4: Create the infrastructure
terragrunt apply

# Migrate state to S3
terragrunt init -migrate-state
```

### 3. Set GitHub Secrets

Go to **Settings → Secrets and variables → Actions → Secrets**:
- `AWS_ROLE_ARN_DEV` = output from `terragrunt output github_actions_role_arn`

### 4. Push & Test

```bash
git push origin develop
```

CI/CD workflow runs automatically. ✅

> **Need more detail?** See [Complete Deployment Guide](#complete-deployment-guide) below.

---

## Complete Deployment Guide

### Step 1: Create Bootstrap IAM User

**Why?** The bootstrap user has permissions to create OIDC providers and IAM roles. This is a one-time manual setup per AWS account.

#### 1.1: Create User in AWS Console

**In EACH AWS account (dev, qa, prod):**

1. Go to **IAM Console** → **Users** → **Create user**
2. Username: `bootstrap-dev` (or `bootstrap-qa`, `bootstrap-prod`)
3. Select **Attach policies directly**
4. Click **Create policy** (opens new tab)

#### 1.2: Create IAM Policy

In the JSON editor, paste:

```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "ManageOIDC",
			"Effect": "Allow",
			"Action": [
				"iam:CreateOpenIDConnectProvider",
				"iam:DeleteOpenIDConnectProvider",
				"iam:GetOpenIDConnectProvider",
				"iam:ListOpenIDConnectProviders",
				"iam:TagOpenIDConnectProvider",
				"iam:UpdateOpenIDConnectProviderThumbprint",
				"iam:UntagOpenIDConnectProvider"
			],
			"Resource": "*"
		},
		{
			"Sid": "ManageRolesAndPolicies",
			"Effect": "Allow",
			"Action": [
				"iam:CreateRole",
				"iam:DeleteRole",
				"iam:UpdateRole",
				"iam:GetRole",
				"iam:ListRoles",
				"iam:TagRole",
				"iam:AttachRolePolicy",
				"iam:ListRolePolicies",
				"iam:DetachRolePolicy",
				"iam:PutRolePolicy",
				"iam:DeleteRolePolicy",
				"iam:CreatePolicy",
				"iam:DeletePolicy",
				"iam:GetPolicy",
				"iam:ListPolicies",
				"iam:ListAttachedRolePolicies",
				"iam:SimulatePrincipalPolicy",
				"iam:TagPolicy",
				"iam:ListInstanceProfilesForRole",
				"iam:GetPolicyVersion",
				"iam:ListPolicyVersions",
				"iam:CreatePolicyVersion",
				"iam:UntagPolicy",
				"iam:UntagRole",
				"iam:DeletePolicyVersion",
				"iam:GetRolePolicy"
			],
			"Resource": "*"
		},
		{
			"Sid": "ListAllBucketsGlobal",
			"Effect": "Allow",
			"Action": [
				"s3:ListAllMyBuckets"
			],
			"Resource": "*"
		},
		{
			"Sid": "ManageS3ForTerraform",
			"Effect": "Allow",
			"Action": [
				"s3:CreateBucket",
				"s3:DeleteBucket",
				"s3:ListBucket",
				"s3:GetBucketLocation",
				"s3:GetBucketVersioning",
				"s3:PutBucketVersioning",
				"s3:GetBucketPublicAccessBlock",
				"s3:PutBucketPublicAccessBlock",
				"s3:GetBucketPolicy",
				"s3:PutBucketPolicy",
				"s3:DeleteBucketPolicy",
				"s3:GetBucketTagging",
				"s3:PutBucketTagging",
				"s3:GetLifecycleConfiguration",
				"s3:PutLifecycleConfiguration",
				"s3:GetBucketAcl",
				"s3:PutBucketAcl",
				"s3:GetObject",
				"s3:PutObject",
				"s3:DeleteObject",
				"s3:GetBucketCORS",
				"s3:GetBucketWebsite",
				"s3:GetAccelerateConfiguration",
				"s3:GetBucketRequestPayment",
				"s3:GetBucketLogging",
				"s3:GetReplicationConfiguration",
				"s3:GetEncryptionConfiguration",
				"s3:GetBucketObjectLockConfiguration",
				"s3:PutEncryptionConfiguration",
				"s3:ListBucketVersions",
				"s3:PutBucketLogging",
				"s3:GetBucketOwnershipControls",
				"s3:PutBucketOwnershipControls"
			],
			"Resource": [
				"arn:aws:s3:::tfstate-*",
				"arn:aws:s3:::tfstate-*/*"
			]
		},
		{
			"Sid": "AuditCloudWatchLogs",
			"Effect": "Allow",
			"Action": [
				"logs:DescribeLogGroups",
				"logs:DescribeLogStreams",
				"logs:FilterLogEvents",
				"logs:GetLogEvents"
			],
			"Resource": "*"
		},
		{
			"Sid": "ManageKMSForS3",
			"Effect": "Allow",
			"Action": [
				"kms:TagResource",
				"kms:CreateKey",
				"kms:EnableKeyRotation",
				"kms:DescribeKey",
				"kms:GetKeyPolicy",
				"kms:GetKeyRotationStatus",
				"kms:ListResourceTags",
				"kms:ScheduleKeyDeletion",
				"kms:CreateAlias",
				"kms:ListAliases",
				"kms:DeleteAlias",
				"kms:GenerateDataKey",
				"kms:Decrypt"
			],
			"Resource": "*"
		}
	]
}
```

Save as `bootstrap-dev-policy` (adjust name for qa/prod).

#### 1.3: Attach Policy & Create Access Keys

1. Return to user creation tab, select `bootstrap-dev-policy`
2. Click **Create user**
3. Go to user → **Security credentials** → **Create access key**
4. Select **CLI** → **Create**
5. **Save credentials** (you'll need them for AWS CLI)

#### 1.4: Configure AWS CLI Profile

```bash
aws configure --profile bootstrap-dev
# Enter Access Key ID + Secret Access Key
# Region: eu-west-1
# Output: json

# Verify
aws sts get-caller-identity --profile bootstrap-dev
```

Expected output:
```json
{
    "Account": "111111111111",
    "Arn": "arn:aws:iam::111111111111:user/bootstrap-dev"
}
```

**Repeat for qa/prod accounts** (create `bootstrap-qa`, `bootstrap-prod` profiles).

---

### Step 2: Configure Terragrunt

All configuration is in `live/` — no `terraform.tfvars` needed.

#### 2.1: Edit Shared Settings

`live/common.hcl`:
```hcl
locals {
  aws_region   = "eu-west-1"
  company_name = "yourcompany"     # Must be globally unique
  github_org   = "your-github-org"
  github_repo  = "*"               # "*" = all repos, or specific name

  enable_branch_restriction = false
  allowed_branches          = ["main", "develop", "release/*", "feature/*"]
}
```

#### 2.2: Edit Environment-Specific Settings

`live/dev/account.hcl`:
```hcl
locals {
  environment = "dev"
  account_id  = get_aws_account_id() # Dynamically retrieved from AWS credentials
  aws_profile = "bootstrap-dev"
}
```

Repeat for `live/qa/account.hcl` and `live/prod/account.hcl`.

#### 2.3: Review Per-Environment Inputs (Optional)

`live/dev/bootstrap/terragrunt.hcl`:
```hcl
inputs = {
  enable_cloudtrail         = false  # Set true for audit logging
  cloudtrail_retention_days = 90
  # CloudTrail adds ~$2/month per environment
}
```

Prod has `enable_cloudtrail = true` by default.

#### 2.4: Validate Configuration

```bash
# Format all HCL files
terragrunt hclfmt --terragrunt-working-dir live/

# Verify no placeholders remain
grep -r "YOUR_" live/
grep -r "yourcompany" live/
```

---

### Step 3: First-Time Deploy

> **Why local state first?** The S3 bucket is created BY this module. On first run it doesn't exist, so we use local state then migrate.

```bash
cd live/dev/bootstrap
export AWS_PROFILE=bootstrap-dev

# Step 1: Verify you're in the right account
aws sts get-caller-identity
 
# Step 2: Initialize WITHOUT remote backend (local state)
terragrunt init -backend=false
 
# Step 3: Review what will be created
terragrunt plan
 
# Step 4: Create the infrastructure
terragrunt apply
```

**Expected output:**
```
Prompted: `Do you want to perform these actions?
 Terraform will perform the actions described above.
 Only 'yes' will be accepted to approve.` → **yes**

Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:
github_actions_role_arn = "arn:aws:iam::111111111111:role/github-actions-terraform-dev"
terraform_state_bucket  = "tfstate-yourcompany-dev-111111111111"
```

Save outputs:
```bash
terragrunt output -json > /tmp/bootstrap-dev-outputs.json
```

---

### Step 4: Migrate State to S3

Now that the S3 bucket exists, enable remote state for this environment.

#### 4.1: Uncomment Remote State Block

Edit `live/dev/bootstrap/terragrunt.hcl` and uncomment the `remote_state` block:

```hcl
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "tfstate-${local.common.locals.company_name}-${local.account.locals.environment}-${local.account.locals.account_id}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.common.locals.aws_region
    encrypt      = true
    use_lockfile = true

    skip_bucket_versioning             = true
    skip_bucket_ssencryption           = true
    skip_bucket_accesslogging          = true
    skip_bucket_root_access            = true
    skip_bucket_enforced_tls           = true
    skip_bucket_public_access_blocking = true
  }
}
```

**Why per-environment?** Each environment (dev/qa/prod) has its own `remote_state` block. This allows independent state migration - deploying dev doesn't affect qa/prod.

#### 4.2: Run State Migration

```bash
# Still in live/dev/bootstrap/
terragrunt init -migrate-state
```

Prompted: `Do you want to copy existing state to the new backend?` → **yes**

**Expected output:**
```
Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

#### 4.3: Verify State in S3

```bash
BUCKET=$(terragrunt output -raw terraform_state_bucket)
aws s3 ls s3://${BUCKET}/dev/bootstrap/ --profile bootstrap-dev
```

Should show `terraform.tfstate`.

---

### Step 5: Verify Setup

#### 5.1: Confirm No Drift

```bash
terragrunt plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

#### 5.2: List Resources

```bash
terragrunt state list
```

Expected resources:
- `aws_iam_openid_connect_provider.github_actions`
- `aws_iam_role.github_actions`
- `aws_iam_policy.terraform_deployment`
- `aws_s3_bucket.terraform_state`
- `aws_kms_key.terraform_state`
- `aws_s3_bucket.terraform_state_access_logs`
- (+ 10 more S3 bucket config resources)

#### 5.3: Test IAM Role Trust Policy

```bash
aws iam get-role \
  --role-name github-actions-terraform-dev \
  --query 'Role.AssumeRolePolicyDocument' \
  --profile bootstrap-dev
```

Should show OIDC conditions for your GitHub org/repo.

---

### Step 6: Configure GitHub Secrets

#### 6.1: Get Role ARN

```bash
terragrunt output github_actions_role_arn
```

Copy the ARN (e.g., `arn:aws:iam::111111111111:role/github-actions-terraform-dev`).

#### 6.2: Set GitHub Organization Secret

1. Go to your GitHub organization
2. **Settings** → **Organization settings** → **Secrets and variables** → **Actions** → **Secrets**
3. Click **New organization secret**
4. Add:
   - Name: `AWS_ROLE_ARN_DEV`
   - Value: `arn:aws:iam::111111111111:role/github-actions-terraform-dev`
   - Repository access: Select your repository or "All repositories"

---

### Step 7: Test GitHub Actions

#### 7.1: Verify Deploy Job Configuration

**⚠️ IMPORTANT:** Before pushing, ensure the `deploy` job in `.github/workflows/terraform-deploy.yml` matches your Terragrunt configuration.

The workflow extracts variables from HCL files and generates `terraform.tfvars`. Verify these match your `live/{env}/bootstrap/terragrunt.hcl`:

| Workflow Variable | Must Match | Source File |
|---|---|---|
| `aws_region` | `local.common.locals.aws_region` | `live/common.hcl` |
| `company_name` | `local.common.locals.company_name` | `live/common.hcl` |
| `github_org` | `local.common.locals.github_org` | `live/common.hcl` |
| `github_repo` | `local.common.locals.github_repo` | `live/common.hcl` |
| `environment` | `local.account.locals.environment` | `live/{env}/account.hcl` |
| `enable_cloudtrail` | `inputs.enable_cloudtrail` | `live/{env}/bootstrap/terragrunt.hcl` |
| `cloudtrail_retention_days` | `inputs.cloudtrail_retention_days` | `live/{env}/bootstrap/terragrunt.hcl` |
| `tags` | `inputs.tags` | `live/{env}/bootstrap/terragrunt.hcl` |
| Backend `key` | `remote_state.config.key` | `live/{env}/bootstrap/terragrunt.hcl` |

**Why this matters:** The CI/CD uses pure Terraform (not Terragrunt) due to wrapper compatibility issues. See [ADR-0004](docs/adr/0004-hybrid-terragrunt-terraform-cicd.md) for details.

If configuration drifts between Terragrunt and the workflow, deployments will fail or create unexpected changes.

#### 7.2: Push Changes

```bash
git add live/ modules/ .github/
git commit -m "feat: AWS bootstrap"
git push
```

#### 7.3: Monitor Workflow

1. Go to **Actions** tab in GitHub
2. Click the running workflow
3. Verify all jobs pass:
   - ✅ detect-environment
   - ✅ validate
   - ✅ security-scan
   - ✅ plan
   - ✅ apply

Expected in `apply` step:
```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

No changes because state already matches.

---

## Architecture

### OIDC Authentication Flow

```
GitHub Actions Workflow
        │
        │ 1. Request OIDC JWT (no stored credentials)
        ↓
GitHub Token Service
  → Signs JWT with:
     - repo: your-org/your-repo
     - ref: refs/heads/develop
     - actor: username
        │
        │ 2. Exchange JWT for AWS credentials
        ↓
AWS STS AssumeRoleWithWebIdentity
  → Validates:
     - JWT signature (GitHub's public key)
     - Audience: sts.amazonaws.com
     - Subject claim matches trust policy
        │
        │ 3. Issue temporary credentials (1-hour TTL)
        ↓
GitHub Actions Runner
  → Runs: terragrunt plan / apply
        │
        │ 4. All API calls logged (if CloudTrail enabled)
        ↓
CloudTrail → S3 (immutable Object Lock)
```

### Branch → Environment Mapping

| Git Branch | Environment | IAM Role |
|---|---|---|
| `feature/*`, `develop` | dev | `github-actions-terraform-dev` |
| `release/*` | qa | `github-actions-terraform-qa` |
| `main` | prod | `github-actions-terraform-prod` |

Each role's trust policy only allows its designated branches. A `feature/*` branch **cannot** assume the prod role.

### CI/CD Workflow Jobs

`.github/workflows/terraform-deploy.yml` runs on every push/PR:

| Job | Trigger | Actions |
|---|---|---|
| **detect-environment** | always | Maps branch → env, sets `AWS_ROLE_ARN_*` variable |
| **validate** | push / PR | `terraform fmt`, `validate`, TFLint |
| **security-scan** | push / PR | Checkov, tfsec |
| **plan** | push / PR | `terragrunt plan -detailed-exitcode`, posts diff to PR |
| **apply** | push (non-PR) | Applies if plan has changes (`exitcode == 2`) |
| **drift-detection** | schedule (Mon 06:00) | Opens GitHub Issue on detected drift |

---

## Multi-Environment Setup

With Terragrunt the structure is already in place.

### For Each Environment (qa, prod):

1. Create `bootstrap-qa` / `bootstrap-prod` IAM users ([Step 1](#step-1-create-bootstrap-iam-user))
2. Configure AWS CLI profiles (`bootstrap-qa`, `bootstrap-prod`)
3. First-time deploy with local state:
   ```bash
   cd live/qa/bootstrap  # or live/prod/bootstrap
   export AWS_PROFILE=bootstrap-qa  # or bootstrap-prod
   
   terragrunt init -backend=false
   terragrunt plan
   terragrunt apply
   ```
4. **Uncomment** `remote_state` block in `live/qa/bootstrap/terragrunt.hcl`
5. Migrate state to S3:
   ```bash
   terragrunt init -migrate-state
   # Type 'yes' when prompted
   ```
6. Add GitHub secrets: `AWS_ROLE_ARN_QA`, `AWS_ROLE_ARN_PROD`

### Deploy All Environments (after first-time setup)

```bash
# Plan all environments in parallel
terragrunt run-all plan --terragrunt-working-dir live/

# Apply all environments
terragrunt run-all apply --terragrunt-working-dir live/
```

---

## Troubleshooting

### Issue: "BucketAlreadyExists"

**Cause:** S3 bucket names must be globally unique.

**Fix:** Change `company_name` in `live/common.hcl` to something more unique.

### Issue: "AccessDenied"

**Cause:** `bootstrap-dev` user lacks permissions.

**Fix:** Verify IAM policy attached (see [Step 1.2](#12-create-iam-policy)).

### Issue: State Migration Fails

**Cause:** Backend misconfiguration or S3 bucket inaccessible.

**Fix:**
```bash
# Verify account ID matches
aws sts get-caller-identity --profile bootstrap-dev

# Check bucket exists
aws s3 ls --profile bootstrap-dev | grep tfstate

# Restore from backup
cp terraform.tfstate.backup terraform.tfstate
```

### Issue: "Error acquiring the state lock"

**Cause:** Previous Terraform run killed mid-execution.

**Fix:**
```bash
BUCKET=$(terragrunt output -raw terraform_state_bucket)
aws s3 rm s3://${BUCKET}/live/dev/bootstrap/terraform.tfstate.tflock --profile bootstrap-dev

# Or force-unlock
terragrunt force-unlock <LOCK_ID>
```

### Issue: GitHub Actions "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause:** Trust policy doesn't match repository or branch.

**Fix:**
1. Verify GitHub org/repo name in `live/common.hcl`
2. Check workflow runs from expected branch
3. Review `enable_branch_restriction` setting

---

## Best Practices

### State File Security

- ✅ Never commit `terraform.tfstate` to Git (already in `.gitignore`)
- ✅ Versioning enabled on S3 state bucket (automatic)
- ✅ Encryption with KMS CMK (automatic)
- ✅ Backup state before major changes: `terraform state pull > backup.tfstate`

### Access Control

- ✅ Separate `bootstrap-{env}` user per environment
- ✅ Rotate access keys every 90 days
- ✅ Enable MFA on bootstrap users
- ✅ Always pass session tags in workflows:
  ```yaml
  role-session-tags: |
    Project=my-project
    environment=dev
    github-actor=${{ github.actor }}
  ```

### Infrastructure Changes

- ✅ Always `terraform plan` before `apply`
- ✅ Review plan output for unexpected deletions
- ✅ Use feature branches for changes
- ✅ Peer review via PR before merge

### State Locking

- ✅ Never disable locking (`use_lockfile = true`)
- ✅ Only force-unlock if holder process confirmed dead
- ✅ Monitor lock duration (> 1 hour = investigate)

---

## Expanding to New Projects

Once bootstrapped, any project in your GitHub org can reuse the infrastructure:

### 1. Configure Backend

In your application's Terraform:
```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-yourcompany-dev-111111111111"
    key          = "my-app/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

### 2. Use OIDC in Workflow

`.github/workflows/deploy.yml`:
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN_DEV }}
    aws-region: eu-west-1
    role-session-tags: |
      Project=my-app
      environment=dev
```

### 3. Extend IAM Permissions

Edit `modules/bootstrap/iam-policies.tf` to add project-specific permissions (Lambda, ECS, RDS, etc.), scoped by ARN and environment tag.

---

## Contributing

See `CONTRIBUTING.md` for:
- PR process and commit conventions
- Local quality checks (`make fmt validate test lint`)
- Pre-commit hooks setup
- SHA pinning for GitHub Actions

---

## Summary

You've successfully deployed:

- ✅ OIDC provider for keyless GitHub Actions authentication
- ✅ IAM role with ARN-based environment isolation
- ✅ S3 state backend with KMS encryption and native locking
- ✅ Optional CloudTrail audit logging
- ✅ Multi-environment Terragrunt structure (dev/qa/prod)

**Your AWS infrastructure is now fully automated, secure, and ready for production CI/CD.**

