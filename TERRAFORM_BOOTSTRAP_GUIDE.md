# Terragrunt Bootstrap Guide for GitHub Actions OIDC

This guide walks you through bootstrapping your **complete AWS CI/CD infrastructure** using **Terragrunt** with the `bootstrap-{env}` user credentials. Terragrunt wraps Terraform to manage dev/qa/prod environments from a single DRY module with no duplicated configuration.

**Repository:** `terraform-aws-github-oidc`

> **Start here:** [README.md](README.md) — project overview, architecture, and documentation index.

**Structure:**
```
modules/bootstrap/       ← Terraform module (edit for logic changes)
live/
  common.hcl             ← Shared: company_name, github_org, region
  terragrunt.hcl         ← Root: remote_state + provider generation
  dev/
    account.hcl          ← Dev account_id, aws_profile
    bootstrap/
      terragrunt.hcl     ← Dev inputs (CloudTrail, branch restrictions)
  qa/  ...               ← Same pattern
  prod/ ...              ← Same pattern
```

## 📋 Table of Contents

- [Why Terraform Bootstrap?](#why-terraform-bootstrap)
- [Prerequisites](#prerequisites)
- [Step 1: Configure Terragrunt](#step-1-configure-terragrunt)
- [Step 2: First-Time Deploy (local state)](#step-2-first-time-deploy-local-state)
- [Step 3: Migrate State to S3](#step-3-migrate-state-to-s3)
- [Step 4: Verify Setup](#step-4-verify-setup)
- [Step 5: Configure GitHub Variables](#step-5-configure-github-variables)
- [Step 6: Test GitHub Actions Workflow](#step-6-test-github-actions-workflow)
- [Multi-Environment Setup](#multi-environment-setup)
- [Troubleshooting](#troubleshooting)
- [State Migration Rollback](#state-migration-rollback)
- [Next Steps](#next-steps)
- [Best Practices](#best-practices)
- [Summary](#summary)

---

## Why Terraform Bootstrap?

### Benefits Over Manual Setup

- ✅ **Declarative Infrastructure** - All resources defined in code
- ✅ **Repeatable** - Deploy identical setups across dev/qa/prod
- ✅ **Version Controlled** - Track infrastructure changes in git
- ✅ **State Management** - Automatic state backend creation and migration
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Less Error-Prone** - Reduces manual configuration mistakes

### What Gets Created

This **single repository** creates your complete CI/CD foundation:

1. **AWS OIDC Identity Provider** — `token.actions.githubusercontent.com`
2. **IAM Role** — `github-actions-terraform-{environment}` with session tagging support
3. **IAM Policy** — `TerraformDeploymentPolicy-{environment}` with ARN-based scoping and `aws:PrincipalTag/environment` cross-environment isolation
4. **S3 State Bucket** — `{company}-tfstate-{environment}-{account-id}` (versioned, KMS-encrypted, S3 native locking, lifecycle rules, public access blocked, TLS 1.2+ enforced)
5. **CloudTrail** *(optional)* — `centralized-audit-trail-{environment}` (immutable Object Lock, configurable retention, multi-region)
6. **Automated State Migration** — Seamless local → S3 transition

**Security model:** ARN patterns embed the environment name (`{company}-*-{env}-*`). The dev role cannot reach qa or prod resources at the IAM policy level.

---

## Prerequisites

### 1. Required Tools

- **Terraform** >= 1.10.0 ([Install](https://developer.hashicorp.com/terraform/downloads))
- **Terragrunt** >= 0.67.0 ([Install](https://terragrunt.gruntwork.io/docs/getting-started/install/))
- **AWS CLI** >= 2.x ([Install](https://aws.amazon.com/cli/))
- **Git** (for version control)

Verify installations:

```bash
terraform version
terragrunt --version
aws --version
git --version
```

### 2. Create bootstrap-{env} User with Required Permissions

**IMPORTANT**: This is a prerequisite step that must be completed **before** setting up OIDC. You need to create an IAM user with specific permissions to manage OIDC providers and IAM roles.

### Why This User?

The `bootstrap-{env}`, for example `bootstrap-dev` user will have explicit permissions to:
- Create and manage OIDC identity providers
- Create and manage IAM roles and policies
- Create and manage CloudTrail
- Create and manage S3 for terraform state bucket
- **Does NOT** include resource provisioning permissions (EC2, Lambda, etc.) or PassRole capability

### Create the User in AWS Console

**In EACH AWS account (dev, qa, prod):**

1. Go to **IAM Console** → **Users** → **Create user**
2. Set username: `bootstrap-{env}`
3. Select **Attach policies directly**
4. Click **Create policy** (opens in new tab)

### Create the bootstrap-{env}-policy

5. In the policy editor, select the **JSON** tab
6. Paste the following policy:

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
                "iam:UntagPolicy",
                "iam:CreatePolicyVersion",
                "iam:UntagRole",
                "iam:DeletePolicyVersion",
                "iam:GetRolePolicy"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageCloudTrail",
            "Effect": "Allow",
            "Action": [
                "cloudtrail:CreateTrail",
                "cloudtrail:DeleteTrail",
                "cloudtrail:UpdateTrail",
                "cloudtrail:StartLogging",
                "cloudtrail:StopLogging",
                "cloudtrail:LookupEvents",
                "cloudtrail:DescribeTrails",
                "cloudtrail:GetTrailStatus",
                "cloudtrail:GetEventSelectors",
                "cloudtrail:PutEventSelectors",
                "cloudtrail:ListTags",
                "cloudtrail:AddTags",
                "cloudtrail:RemoveTags"
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
                "s3:ListAllMyBuckets",
                "s3:GetBucketCORS",
                "s3:GetBucketWebsite",
                "s3:GetBucketAcl",
                "s3:GetAccelerateConfiguration",
                "s3:GetBucketRequestPayment",
                "s3:GetBucketLogging",
                "s3:GetReplicationConfiguration",
                "s3:GetEncryptionConfiguration",
                "s3:GetBucketObjectLockConfiguration",
                "s3:PutEncryptionConfiguration"
            ],
            "Resource": [
                "arn:aws:s3:::*-tfstate-*",
                "arn:aws:s3:::*-tfstate-*/*"
            ]
        },
{
            "Sid": "ManageS3ForCloudTrail",
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:PutBucketPolicy",
                "s3:GetBucketPolicy",
                "s3:PutBucketPublicAccessBlock",
                "s3:ListBucket",
                "s3:GetBucketTagging",
                "s3:GetBucketAcl",
                "s3:GetBucketCORS",
                "s3:GetBucketWebsite",
                "s3:GetBucketVersioning",
                "s3:GetAccelerateConfiguration",
                "s3:GetBucketRequestPayment",
                "s3:GetBucketLogging",
                "s3:GetReplicationConfiguration",
                "s3:GetEncryptionConfiguration",
                "s3:GetBucketObjectLockConfiguration",
                "s3:GetLifecycleConfiguration",
                "s3:DeleteBucket",
                "s3:PutBucketTagging",
                "s3:GetBucketPublicAccessBlock",
                "s3:PutLifecycleConfiguration",
                "s3:DeleteBucketPolicy"
            ],
            "Resource": "arn:aws:s3:::cloudtrail-logs-*"
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
        }
    ]
}
```

7. Click **Next**
8. Set policy details:
   - **Policy name**: `bootstrap-{env}-policy`
   - **Description**: `Grants permissions to manage OIDC identity providers, IAM roles and policies, CloudTrail logging, and policy simulation.`
9. Click **Create policy**

### Attach Policy to User

10. Return to the **Create user** tab
11. Refresh the policy list and search for `bootstrap-{env}-policy`
12. Select the checkbox next to `bootstrap-{env}-policy`
13. Click **Next** → **Create user**

### Create Access Keys

14. Go to the newly created `bootstrap-{env}` user
15. Navigate to **Security credentials** tab
16. Click **Create access key**
17. Select **Command Line Interface (CLI)**
18. Check the confirmation box
19. Click **Create access key**
20. **Save the credentials securely** - you'll need them for AWS CLI configuration

### Configure AWS CLI Profile

```bash
# Configure the bootstrap-{env} profile
aws configure --profile bootstrap-{env}
# Enter the Access Key ID and Secret Access Key from step 20 above
# Set default region (e.g., eu-west-1)
# Set output format (json)

# Verify the profile
aws sts get-caller-identity --profile bootstrap-{env}
```

**Expected output:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "111111111111",
    "Arn": "arn:aws:iam::111111111111:user/bootstrap-{env}"
}
```

**Repeat this process** for QA and Prod AWS accounts to create the bootstrap-qa and bootstrap-prod profiles. (Note: You may wish to verify Dev is fully working first)

### 4. GitHub Information

You'll need:
- GitHub organization name
- GitHub repository name (or use `*` for all repos in org)
- Repository admin access (to set GitHub variables)

---

## Step 1: Configure Terragrunt

All configuration is in `live/` — **no `terraform.tfvars` files needed**.

### 1.1: Edit common.hcl (shared settings)

Open `live/common.hcl` and set values shared across all environments:

```hcl
locals {
  aws_region   = "eu-west-1"
  company_name = "yourcompany"     # Prefix for S3 buckets: {company}-tfstate-{env}-{account}
  github_org   = "your-github-org" # GitHub organisation name
  github_repo  = "*"               # "*" = all repos in org

  enable_branch_restriction = false
  allowed_branches          = ["main", "develop", "release/*", "feature/*"]
}
```

### 1.2: Edit dev/account.hcl (dev-specific settings)

Open `live/dev/account.hcl`:

```hcl
locals {
  environment = "dev"
  account_id  = "111111111111"  # Your dev AWS account ID
  aws_profile = "bootstrap-dev" # AWS CLI profile
}
```

Repeat for `live/qa/account.hcl` and `live/prod/account.hcl` with their respective account IDs.

### 1.3: Review per-env inputs (optional)

Open `live/dev/bootstrap/terragrunt.hcl` to adjust environment-specific settings:

```hcl
inputs = {
  enable_cloudtrail         = false  # Set to true to enable audit logging
  cloudtrail_retention_days = 90
  # ... other overrides
}
```

**Important Notes:**
- `company_name` is the S3 bucket prefix: `{company}-tfstate-{env}-{account-id}`
- `aws:PrincipalTag/environment` prevents cross-environment operations in IAM
- Prod has `enable_cloudtrail = true` pre-configured in `live/prod/bootstrap/terragrunt.hcl`
- The `account_id` in `account.hcl` must exactly match the AWS account ID for the S3 bucket name to resolve correctly

### 1.4: Validate Configuration

```bash
# Check HCL formatting
terragrunt hclfmt --terragrunt-check --terragrunt-working-dir live/

# Verify no placeholder values remain
grep -r "YOUR_" live/
```

---

## Step 2: First-Time Deploy (local state)

> **Why local state first?** The S3 bucket that stores Terraform state is created BY this module. On first run, it doesn't exist yet, so we deploy with a local backend then migrate.

### 2.1: Navigate to the dev environment

```bash
cd live/dev/bootstrap
export AWS_PROFILE=bootstrap-dev
```

### 2.2: Apply with local state

```bash
# --terragrunt-no-auto-init skips remote state init
# -backend=false uses local state for this first apply
terragrunt apply --terragrunt-no-auto-init -backend=false
```

Type `yes` when prompted.

**What Terragrunt does:**
1. Downloads `modules/bootstrap` source
2. Generates `provider.tf` (from root `live/terragrunt.hcl`)
3. Passes `inputs = {}` from `live/dev/bootstrap/terragrunt.hcl` as Terraform variables
4. Runs `terraform apply`

**Expected output:**
```
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:
  github_actions_role_arn = "arn:aws:iam::111111111111:role/github-actions-terraform-dev"
  terraform_state_bucket  = "yourcompany-tfstate-dev-111111111111"
  ...
```

### 2.3: Save outputs

```bash
# Note the role ARN and bucket name from the output above
terragrunt output -json > /tmp/bootstrap-outputs-dev.json
cat /tmp/bootstrap-outputs-dev.json
```

---

## Step 3: Migrate State to S3

### 3.1: Initialise with S3 backend

```bash
# Still in live/dev/bootstrap/
terragrunt init -migrate-state
```

Terragrunt generates `backend.tf` pointing to `{company}-tfstate-dev-{account-id}` and Terraform migrates the local state to S3.

**You will be prompted:**
```
Do you want to copy existing state to the new backend?
Enter a value: yes
```

**Expected output:**
```
Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

### 3.2: Verify state in S3

```bash
BUCKET=$(terragrunt output -raw terraform_state_bucket)
aws s3 ls s3://${BUCKET}/live/dev/bootstrap/ --profile bootstrap-dev
```

**Expected output:**
```
2026-01-07 20:00:00      12345 terraform.tfstate
```

### 3.3: Verify Resources Created

```bash
# Verify OIDC provider
aws iam list-open-id-connect-providers --profile bootstrap-dev

# Verify IAM role
aws iam get-role --role-name github-actions-terraform-dev --profile bootstrap-dev

# Verify S3 bucket
aws s3 ls --profile bootstrap-dev | grep tfstate
```

---

## Step 4: Verify Setup

### 4.1: Run plan to confirm no changes

```bash
# Still in live/dev/bootstrap/ with AWS_PROFILE=bootstrap-dev
terragrunt plan
```

**Expected output:** `No changes. Your infrastructure matches the configuration.`

### 4.2: Verify Terraform State

```bash
terragrunt state list
```

**Expected output:**
```
data.aws_caller_identity.current
data.aws_region.current
aws_iam_openid_connect_provider.github_actions
aws_iam_policy.terraform_deployment
aws_iam_role.github_actions
aws_iam_role_policy.allow_session_tagging
aws_iam_role_policy_attachment.github_actions_terraform_deployment
aws_kms_key.terraform_state
aws_s3_bucket.terraform_state
aws_s3_bucket_lifecycle_configuration.terraform_state
aws_s3_bucket_logging.terraform_state
aws_s3_bucket_policy.terraform_state
aws_s3_bucket_public_access_block.terraform_state
aws_s3_bucket_server_side_encryption_configuration.terraform_state
aws_s3_bucket_versioning.terraform_state
```

### 4.3: Test IAM Role Trust Policy

```bash
aws iam get-role \
  --role-name github-actions-terraform-dev \
  --query 'Role.AssumeRolePolicyDocument' \
  --profile bootstrap-dev
```

### 4.4: Simulate IAM Policy

```bash
ROLE_ARN=$(terragrunt output -raw github_actions_role_arn)
BUCKET=$(terragrunt output -raw terraform_state_bucket)

aws iam simulate-principal-policy \
  --policy-source-arn "${ROLE_ARN}" \
  --action-names s3:PutObject \
  --resource-arns "arn:aws:s3:::${BUCKET}/*" \
  --profile bootstrap-dev
# Should show: EvalDecision: allowed
```

---

## Step 5: Configure GitHub Variables

### 5.1: Get Role ARN

```bash
terragrunt output github_actions_role_arn
```

Copy the output (e.g., `arn:aws:iam::111111111111:role/github-actions-terraform-dev`)

---

### 5.2: Set GitHub Repository Variables

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **Variables** tab → **New repository variable**
4. Add:
   - `AWS_ROLE_ARN_DEV` = `arn:aws:iam::111111111111:role/github-actions-terraform-dev`
   - `COMPANY_NAME` = your company prefix (from `live/common.hcl`)

### 5.3: Verify

Go back to the Variables page and confirm both variables are listed.

---

## Step 6: Test GitHub Actions Workflow

### 6.1: Push changes and trigger the workflow

```bash
git add live/ modules/ .github/
git commit -m "feat: Terragrunt bootstrap implementation"
git push origin develop
```

This triggers `.github/workflows/terraform-deploy.yml` which:
1. Detects branch `develop` → `dev` environment
2. Runs `terragrunt plan` in `live/dev/bootstrap/`
3. Posts plan diff to the PR (if it's a PR)
4. Applies if there are changes and it's a push (not PR)

### 6.2: Monitor Workflow

1. Go to **Actions** tab in GitHub
2. Click the `Terraform Deploy - Bootstrap` run
3. Verify `Terragrunt Plan` and `Terragrunt Apply` steps pass

**Expected output in "Terragrunt Apply" step:**
```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
(no changes — state already matches)
```

---

## Multi-Environment Setup

With Terragrunt the structure is already in place — you just need to fill in account details and repeat the first-time deploy for each environment.

### For each environment (qa, prod):

1. Create `bootstrap-qa` / `bootstrap-prod` IAM users (see [Prerequisites](#2-create-bootstrap-env-user-with-required-permissions))
2. Fill in `live/qa/account.hcl` and `live/prod/account.hcl` with the correct `account_id`
3. First-time deploy:
   ```bash
   cd live/qa/bootstrap
   export AWS_PROFILE=bootstrap-qa
   terragrunt apply --terragrunt-no-auto-init -backend=false
   terragrunt init -migrate-state
   ```
4. Add GitHub variables: `AWS_ROLE_ARN_QA`, `AWS_ROLE_ARN_PROD`

### Deploy all environments at once (after first-time setup)

```bash
# Run plan across all environments in parallel
terragrunt run-all plan --terragrunt-working-dir live/

# Apply all environments in dependency order
terragrunt run-all apply --terragrunt-working-dir live/
```

> `run-all` respects Terragrunt dependency blocks. All three environments run in parallel since they have no inter-dependencies.

---

## Troubleshooting

### Issue: "Error creating S3 bucket: BucketAlreadyExists"

**Cause:** S3 bucket names must be globally unique.

**Solution:** Change `company_name` in `live/common.hcl` to something more unique.

### Issue: "AccessDenied" when running terraform apply

**Cause:** bootstrap-dev user lacks required permissions.

**Solution:** Verify bootstrap-dev policy includes all required permissions (see [Prerequisites - Create bootstrap-dev User](#2-create-bootstrap-dev-user-with-required-permissions)).

### Issue: State migration fails

**Cause:** Backend configuration incorrect or S3 bucket not accessible.

**Solution:**
1. Verify `account_id` in `live/dev/account.hcl` matches your actual AWS account
2. Check S3 bucket exists: `aws s3 ls --profile bootstrap-dev | grep tfstate`
3. Restore from backup: `cp terraform.tfstate.backup terraform.tfstate`

### Issue: "Error acquiring the state lock"

A previous Terraform run was killed mid-execution, leaving a `.tflock` file in S3.

**Solution:**
```bash
# Inspect the lock file
BUCKET=$(terragrunt output -raw terraform_state_bucket)
aws s3 cp s3://${BUCKET}/live/dev/bootstrap/terraform.tfstate.tflock /tmp/lock.json --profile bootstrap-dev
cat /tmp/lock.json

# Remove the lock file (only if the holder's process is confirmed dead)
aws s3 rm s3://${BUCKET}/live/dev/bootstrap/terraform.tfstate.tflock --profile bootstrap-dev

# Or use Terraform's built-in unlock
terragrunt force-unlock <LOCK_ID>
```

For full recovery procedures see [docs/runbooks/state-bucket-recovery.md](docs/runbooks/state-bucket-recovery.md).

### Issue: GitHub Actions workflow fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause:** Trust policy doesn't match repository or branch.

**Solution:**
1. Check trust policy: `terragrunt output` to see configuration
2. Verify GitHub org/repo name is correct
3. Ensure workflow is running from expected branch
4. Check `enable_branch_restriction` setting

---

## State Migration Rollback

If the first-time state migration fails:

### Restore Local State

```bash
# Remove the generated backend.tf and Terragrunt cache
rm -f backend.tf
rm -rf .terragrunt-cache

# Restore state file from backup if needed
cp terraform.tfstate.backup terraform.tfstate

# Re-apply with local state
terragrunt apply --terragrunt-no-auto-init -backend=false
```

### Verify State

```bash
terragrunt state list
```

For detailed recovery procedures see [docs/runbooks/state-bucket-recovery.md](docs/runbooks/state-bucket-recovery.md).

---

## Next Steps

### 1. Review Architecture Decisions
Understand why the project is built the way it is:
- [ADR-0001](docs/adr/0001-arn-based-isolation-vs-abac.md) — ARN-based isolation vs ABAC resource tags
- [ADR-0002](docs/adr/0002-s3-native-locking-vs-dynamodb.md) — S3 native locking vs DynamoDB
- [ADR-0003](docs/adr/0003-organisation-wide-oidc-role.md) — Organisation-wide OIDC role (accepted risk)

### 2. CloudTrail (Optional)
Set `enable_cloudtrail = true` in `terraform.tfvars`. CloudTrail logs every `AssumeRoleWithWebIdentity` call and all API operations, stored in an S3 bucket with Object Lock (immutable for `cloudtrail_retention_days`).

### 3. Use This Bootstrap for Your Applications

For each new project (e.g., `marketing-ai`, `dataplatform`):

1. **Create project repository** with Terraform code
2. **Configure backend** to use the shared state bucket:
   ```hcl
   terraform {
     backend "s3" {
       bucket       = "yourcompany-tfstate-dev-123456"
       key          = "marketing-ai/terraform.tfstate"
       region       = "eu-west-1"
       encrypt      = true
       use_lockfile = true
     }
   }
   ```
3. **Pass session tags** in the GitHub Actions workflow:
   ```yaml
   - uses: aws-actions/configure-aws-credentials@v4
     with:
       role-to-assume: ${{ vars.AWS_ROLE_ARN_DEV }}
       role-session-tags: |
         Project=marketing-ai
         environment=dev
   ```
4. **Expand `iam-policies.tf`** to add permissions for the new project's services, scoped by ARN and protected by `aws:PrincipalTag/environment`.

**Supported Services:** Lambda, ECS/Fargate, Glue, Bedrock, RDS, API Gateway — any Terraform-managed AWS infrastructure.

### 4. Expand to QA and Prod
- Follow [Multi-Environment Setup](#multi-environment-setup) to repeat the bootstrap for each environment
- Or adopt Terragrunt for a DRY multi-env setup: [docs/terragrunt-environments.md](docs/terragrunt-environments.md)

### 5. Set Up Branch Protection
Configure GitHub repository settings:
- Require pull request reviews before merging to `main`
- Enforce status checks (successful CI/CD)
- Require branches to be up to date before merging

---

## Best Practices

### 1. State File Security

- ✅ **Never commit** `terraform.tfstate` to git (already in `.gitignore`)
- ✅ **Enable versioning** on S3 state bucket (already done by bootstrap)
- ✅ **Enable encryption** on S3 state bucket (already done by bootstrap)
- ✅ **Backup state files** before major changes

### 2. Access Control

- ✅ Use separate `bootstrap-{env}` user per environment
- ✅ Rotate access keys regularly
- ✅ Enable MFA on bootstrap-{env} user
- ✅ Use CloudTrail to monitor bootstrap-{env} activities
- ✅ Always pass `Project` and `environment` session tags in workflows via `role-session-tags`
- ✅ Tag all resources with `Project`, `environment`, `ManagedBy`

### 3. Infrastructure Changes

- ✅ Always run `terraform plan` before `apply`
- ✅ Review plan output carefully — watch for unexpected deletions
- ✅ Use feature branches for infrastructure changes
- ✅ Peer review Terraform code changes via PR

### 4. State Locking

- ✅ Never disable state locking (`use_lockfile = true` in backend config)
- ✅ Use `terraform force-unlock` only when the holder's process is confirmed dead
- ✅ See [docs/runbooks/state-bucket-recovery.md](docs/runbooks/state-bucket-recovery.md) for recovery steps

---

## Summary

You have successfully:

- ✅ Created OIDC provider, IAM role, and deployment policy with Terraform
- ✅ Implemented ARN-based policy scoping + `aws:PrincipalTag/environment` cross-environment isolation
- ✅ Configured immutable CloudTrail audit logging (Object Lock COMPLIANCE mode, optional)
- ✅ Migrated Terraform state from local to S3 with native locking (no DynamoDB)
- ✅ Configured GitHub variables for OIDC authentication
- ✅ Tested GitHub Actions workflow with AWS access

**Your infrastructure is now fully automated, secure, and ready for multi-project CI/CD deployments.**

---

## References

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [docs/adr/](docs/adr/) — Architecture Decision Records
- [docs/runbooks/state-bucket-recovery.md](docs/runbooks/state-bucket-recovery.md) — State recovery runbook
- [docs/terragrunt-environments.md](docs/terragrunt-environments.md) — Multi-environment Terragrunt guide
