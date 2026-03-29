# Terraform AWS OIDC Bootstrap

[![AWS](https://img.shields.io/badge/AWS-IAM%20%7C%20OIDC-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Terraform](https://img.shields.io/badge/Terraform-1.10%2B-7B42BC?logo=terraform)](https://www.terraform.io/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Bootstraps the complete AWS CI/CD foundation for GitHub Actions: keyless OIDC authentication, scoped IAM roles, encrypted S3 state backend, and optional CloudTrail audit logging — all managed by Terraform.

---

## What It Creates

Per AWS account (run once per environment), managed by Terragrunt:

| Resource | Name pattern | Purpose |
|---|---|---|
| OIDC Identity Provider | `token.actions.githubusercontent.com` | Keyless GitHub Actions auth |
| IAM Role | `github-actions-terraform-{env}` | CI/CD role assumed by workflows |
| IAM Policy | `TerraformDeploymentPolicy-{env}` | Scoped permissions (ARN + env isolation) |
| S3 State Bucket | `{company}-tfstate-{env}-{account-id}` | Versioned, KMS-encrypted Terraform state |
| CloudTrail *(optional)* | `centralized-audit-trail-{env}` | Immutable OIDC + API audit logs |

**Security model:** environment name is embedded in every resource ARN. The dev role cannot touch QA or prod resources — enforced by IAM policy, not by convention.

**Repository structure:**
```
modules/bootstrap/   ← Terraform module (single source of truth)
live/
  common.hcl         ← Shared: company_name, github_org, region
  dev/
    account.hcl      ← Dev: account_id, aws_profile
    bootstrap/
      terragrunt.hcl ← Dev deploy unit
  qa/  ...           ← Same pattern
  prod/ ...          ← Same pattern
```

---

## Prerequisites

- Terraform `>= 1.10.0` (for S3 native state locking — no DynamoDB needed)
- Terragrunt `>= 0.67.0` ([install](https://terragrunt.gruntwork.io/docs/getting-started/install/))
- AWS CLI `>= 2.x` configured with a bootstrap IAM user
- GitHub repository with Actions enabled

See [TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md) for how to create the bootstrap IAM user and its required permissions.

---

## Quick Start

**~10 minutes per environment.** Test dev before replicating to qa and prod.

**1. Configure shared settings:**
```bash
# Edit live/common.hcl — set company_name, github_org, aws_region
# Edit live/dev/account.hcl — set your AWS account_id
```

**2. First-time deploy (S3 bucket doesn't exist yet):**
```bash
export AWS_PROFILE=bootstrap-dev
cd live/dev/bootstrap

# Apply with local state (bucket doesn't exist yet)
terragrunt apply --terragrunt-no-auto-init -backend=false

# Migrate state to the S3 bucket just created
terragrunt init -migrate-state
```

**3. All subsequent deploys (CI/CD or manual):**
```bash
terragrunt plan
terragrunt apply
```

**4. Set GitHub variables:**

Go to **Settings → Secrets and variables → Actions → Variables** and add:
- `AWS_ROLE_ARN_DEV` — from `terragrunt output github_actions_role_arn`
- `COMPANY_NAME` — your company prefix

**5. Push to a branch — CI/CD runs automatically via `live/{env}/bootstrap/`.**

> Full step-by-step with verification commands: [TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md)

---

## Architecture

```
GitHub Actions Workflow
        │
        │ 1. Request OIDC JWT (no stored credentials)
        ↓
GitHub Token Service → signs JWT with repo, branch, actor claims
        │
        │ 2. Exchange JWT for temporary AWS credentials
        ↓
AWS STS — validates JWT against OIDC provider trust policy
        │
        │ 3. Temporary credentials (1 hour TTL)
        ↓
GitHub Actions — runs terraform plan / apply
        │
        │ 4. All AWS API calls logged
        ↓
CloudTrail → S3 audit bucket (optional, Object Lock immutable)
```

### Branch → Environment Mapping

| Git branch | Environment | IAM Role assumed |
|---|---|---|
| `feature/*`, `develop` | `dev` | `github-actions-terraform-dev` |
| `release/*` | `qa` | `github-actions-terraform-qa` |
| `main` | `prod` | `github-actions-terraform-prod` |

Each role is restricted to the OIDC trust policy for its own environment's branches. A `feature/*` branch cannot assume the prod role.

---

## CI/CD Workflow

`.github/workflows/terraform-deploy.yml` runs on every push and PR:

| Job | Trigger | What it does |
|---|---|---|
| `detect-environment` | always | Maps branch to dev / qa / prod |
| `validate` | push / PR | `terraform fmt`, `validate`, TFLint |
| `security-scan` | push / PR | Checkov, tfsec |
| `plan` | push / PR | `terraform plan`, posts diff to PR comment |
| `apply` | push (non-PR) | Applies only if plan has changes (`exitcode == 2`) |
| `drift-detection` | scheduled (Mon 06:00 UTC) | Opens GitHub issue on drift |

---

## Documentation

| Document | Purpose |
|---|---|
| [TERRAFORM_BOOTSTRAP_GUIDE.md](TERRAFORM_BOOTSTRAP_GUIDE.md) | Full step-by-step Terragrunt deployment guide with verification commands |
| [live/common.hcl](live/common.hcl) | Edit here: `company_name`, `github_org`, `aws_region` |
| [live/{env}/account.hcl](live/dev/account.hcl) | Edit here: per-env `account_id`, `aws_profile` |
| [live/{env}/bootstrap/terragrunt.hcl](live/dev/bootstrap/terragrunt.hcl) | Edit here: per-env module inputs (CloudTrail, branch restrictions) |
| [docs/adr/README.md](docs/adr/README.md) | Architecture Decision Records index |
| [docs/adr/0001-arn-based-isolation-vs-abac.md](docs/adr/0001-arn-based-isolation-vs-abac.md) | Why ARN-based isolation replaced ABAC resource tags |
| [docs/adr/0002-s3-native-locking-vs-dynamodb.md](docs/adr/0002-s3-native-locking-vs-dynamodb.md) | Why S3 native locking (`use_lockfile`) replaced DynamoDB |
| [docs/adr/0003-organisation-wide-oidc-role.md](docs/adr/0003-organisation-wide-oidc-role.md) | Why the OIDC role has broad IAM permissions (accepted risk) |
| [docs/runbooks/state-bucket-recovery.md](docs/runbooks/state-bucket-recovery.md) | How to recover from state bucket deletion or corruption |

---

## Expanding to New Projects

Once bootstrapped, any project in your GitHub org can reuse the same role:

```hcl
# In your application's Terraform backend
terraform {
  backend "s3" {
    bucket       = "yourcompany-tfstate-dev-123456789"
    key          = "my-project/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

```yaml
# In your application's GitHub Actions workflow
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN_DEV }}
    role-session-tags: |
      Project=my-project
      environment=dev
```

Add project-specific IAM permissions by extending `bootstrap/iam-policies.tf`.

---

## Contributing

1. Fork → feature branch → PR against `develop`
2. Run `pre-commit install` (see [.pre-commit-config.yaml](.pre-commit-config.yaml))
3. CI must pass before merge
