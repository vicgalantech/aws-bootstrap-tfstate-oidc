# Managing dev / qa / prod Environments with Terragrunt

This document explains how to manage multiple environments (dev, qa, prod) for this bootstrap
using **Terragrunt**. It also explains why Terragrunt is the recommended approach and how to
migrate from the current branch-based CI/CD setup.

---

## The Problem: Environment Configuration Drift

The current setup runs Terraform directly from the `bootstrap/` directory, detecting the target
environment from the Git branch. This works, but as the infrastructure grows you will face:

| Problem | Manifestation |
|---|---|
| **Copy-paste explosion** | `terraform.tfvars` for each env differs by 2 lines but must be fully repeated |
| **No local multi-env plan** | You cannot plan all 3 environments simultaneously from your laptop |
| **State isolation is implicit** | The bucket name changes per env, but nothing enforces consistent backend config |
| **Module reuse is hard** | When you extract the bootstrap into a module for other projects, calling it per-env requires duplicated root modules |

---

## Options Compared

| Approach | Isolation | DRY | Local control | Complexity |
|---|---|---|---|---|
| **Terraform Workspaces** | ❌ Shared state backend | ✅ Single codebase | ⚠️ `terraform workspace select` | Low |
| **Multiple root modules** (`envs/dev/`, `envs/qa/`) | ✅ Separate state | ❌ Duplicated HCL | ✅ Full | Medium |
| **Terragrunt** | ✅ Separate state per env | ✅ DRY via `include` | ✅ `run-all` | Medium |

**Workspaces are not recommended** for this project because workspaces share the same backend
bucket, making it impossible to restrict the dev role from reading prod state. Full state isolation
requires separate buckets, which means separate backends — and that is exactly what Terragrunt
manages for you.

---

## Install Terragrunt

```bash
# macOS / Linux via Homebrew
brew install terragrunt

# Windows via Chocolatey
choco install terragrunt

# Or download the binary directly
# https://github.com/gruntwork-io/terragrunt/releases
```

Verify:
```bash
terragrunt --version    # Should print >= 0.67.0
terraform --version     # Should print >= 1.10.0
```

---

## Repository Structure (Target Layout)

After adopting Terragrunt, the recommended layout is:

```
terraform-aws-github-oidc/
│
├── modules/                          ← Reusable Terraform modules (5.3)
│   └── github-oidc-bootstrap/        ← The bootstrap extracted as a module
│       ├── main.tf                   (symlink or copy of bootstrap/*.tf)
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── README.md
│
├── environments/                     ← Terragrunt environment roots
│   ├── terragrunt.hcl                ← Root config (shared backend + provider defaults)
│   ├── dev/
│   │   └── bootstrap/
│   │       └── terragrunt.hcl        ← dev-specific inputs
│   ├── qa/
│   │   └── bootstrap/
│   │       └── terragrunt.hcl        ← qa-specific inputs
│   └── prod/
│       └── bootstrap/
│           └── terragrunt.hcl        ← prod-specific inputs
│
├── bootstrap/                        ← Kept for backward-compat / CI-CD direct use
├── .github/workflows/
│   └── terraform-deploy.yml
└── docs/
```

> **Note:** You can evolve to this layout incrementally. The `bootstrap/` directory continues
> to work as-is for CI/CD while you build out `environments/` and `modules/` locally.

---

## Step 1: Extract the Bootstrap as a Reusable Module

Create `modules/github-oidc-bootstrap/` with the same `.tf` files from `bootstrap/` (minus the
backend configuration — backends are managed by Terragrunt, not the module):

```bash
mkdir -p modules/github-oidc-bootstrap
cp bootstrap/*.tf modules/github-oidc-bootstrap/
# Remove the backend block from providers.tf — Terragrunt injects it
```

The module's `variables.tf` already has the correct interface. The module has no backend block:

```hcl
# modules/github-oidc-bootstrap/providers.tf
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

---

## Step 2: Root Terragrunt Configuration

Create `environments/terragrunt.hcl`. This is the **shared configuration** inherited by all
environments — it defines the remote state backend pattern.

```hcl
# environments/terragrunt.hcl

locals {
  # Parse the environment name from the directory path
  # environments/dev/bootstrap  →  "dev"
  env = reverse(split("/", path_relative_to_include()))[1]

  aws_region   = "eu-west-1"
  company_name = "victorgalantech"

  # Derive account ID from the caller identity (requires AWS credentials)
  account_id = run_cmd("--terragrunt-quiet", "aws", "sts", "get-caller-identity",
    "--query", "Account", "--output", "text")
}

# Remote state backend — one bucket per environment, one key per module
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = "tfstate-${local.company_name}-${local.env}-${local.account_id}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

# Generate a versions.tf so the module does not need to repeat it
generate "versions" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.10.0"
}
EOF
}
```

---

## Step 3: Per-Environment Configuration

Each environment directory contains a thin `terragrunt.hcl` that:
1. Inherits the root config via `include`
2. Points at the shared module
3. Passes environment-specific inputs

### `environments/dev/bootstrap/terragrunt.hcl`

```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//github-oidc-bootstrap"
}

inputs = {
  aws_region   = "eu-west-1"
  environment  = "dev"
  company_name = "victorgalantech"

  github_org                = "victorgalantech"
  github_repo               = "*"
  enable_branch_restriction = true
  allowed_branches          = ["main", "develop", "release/*", "feature/*"]

  enable_cloudtrail         = false
  cloudtrail_retention_days = 1

  tags = {
    ManagedBy   = "Terragrunt"
    Team        = "DevOps"
    Project     = "bootstrap"
    environment = "dev"
  }
}
```

### `environments/qa/bootstrap/terragrunt.hcl`

```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//github-oidc-bootstrap"
}

inputs = {
  aws_region   = "eu-west-1"
  environment  = "qa"
  company_name = "victorgalantech"

  github_org                = "victorgalantech"
  github_repo               = "*"
  enable_branch_restriction = true
  allowed_branches          = ["main", "release/*"]

  enable_cloudtrail         = false
  cloudtrail_retention_days = 1

  tags = {
    ManagedBy   = "Terragrunt"
    Team        = "DevOps"
    Project     = "bootstrap"
    environment = "qa"
  }
}
```

### `environments/prod/bootstrap/terragrunt.hcl`

```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//github-oidc-bootstrap"
}

inputs = {
  aws_region   = "eu-west-1"
  environment  = "prod"
  company_name = "victorgalantech"

  github_org                = "victorgalantech"
  github_repo               = "*"
  enable_branch_restriction = true
  allowed_branches          = ["main"]   # Only main can deploy to prod

  enable_cloudtrail         = true
  cloudtrail_retention_days = 90

  tags = {
    ManagedBy   = "Terragrunt"
    Team        = "DevOps"
    Project     = "bootstrap"
    environment = "prod"
  }
}
```

---

## Step 4: Local Deployment Commands

### Deploy a single environment

```bash
# Authenticate to the target environment first (e.g., using AWS SSO or env vars)
export AWS_PROFILE=victorgalantech-dev

cd environments/dev/bootstrap

# Preview changes
terragrunt plan

# Apply changes
terragrunt apply

# Destroy (use with caution)
terragrunt destroy
```

### Deploy all environments at once

```bash
cd environments/

# Plan all environments in parallel (reads-only, safe)
terragrunt run-all plan

# Apply all environments sequentially (safe ordering)
terragrunt run-all apply --terragrunt-non-interactive
```

### Output values for a specific environment

```bash
cd environments/prod/bootstrap
terragrunt output
```

---

## Step 5: Authentication per Environment

Each environment maps to a different AWS role / profile. Configure your local `~/.aws/config`:

```ini
[profile victorgalantech-dev]
sso_start_url  = https://victorgalantech.awsapps.com/start
sso_region     = eu-west-1
sso_account_id = 111111111111
sso_role_name  = AdministratorAccess
region         = eu-west-1

[profile victorgalantech-qa]
sso_start_url  = https://victorgalantech.awsapps.com/start
sso_region     = eu-west-1
sso_account_id = 222222222222
sso_role_name  = AdministratorAccess
region         = eu-west-1

[profile victorgalantech-prod]
sso_start_url  = https://victorgalantech.awsapps.com/start
sso_region     = eu-west-1
sso_account_id = 333333333333
sso_role_name  = AdministratorAccess
region         = eu-west-1
```

Then deploy with:

```bash
AWS_PROFILE=victorgalantech-prod terragrunt apply
```

> **Multi-account vs single-account:** If all environments share one AWS account,
> use IAM roles instead of separate accounts. The bootstrap already creates per-environment
> IAM roles (`github-actions-terraform-dev`, etc.) — use `aws sts assume-role` locally
> or configure named profiles that assume those roles.

---

## Step 6: CI/CD Integration

The existing `terraform-deploy.yml` workflow can be kept for the `bootstrap/` root module
(backward-compatible). To add Terragrunt-based jobs, add a new workflow:

```yaml
# .github/workflows/terragrunt-deploy.yml
name: Terragrunt Deploy

on:
  push:
    branches: [main, develop, "release/*"]
    paths:
      - 'environments/**'
      - 'modules/**'
  pull_request:
    paths:
      - 'environments/**'
      - 'modules/**'

permissions: {}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

env:
  AWS_REGION: 'eu-west-1'
  TG_VERSION: '0.67.0'
  TF_VERSION: '1.10.0'

jobs:
  detect-environment:
    name: Detect Environment
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
    outputs:
      environment: ${{ steps.detect.outputs.environment }}
      env_dir:     ${{ steps.detect.outputs.env_dir }}
    steps:
      - id: detect
        run: |
          if [[ "${{ github.ref }}" == "refs/heads/main" ]]; then
            ENV="prod"
          elif [[ "${{ github.ref }}" == refs/heads/release/* ]]; then
            ENV="qa"
          else
            ENV="dev"
          fi
          echo "environment=${ENV}" >> $GITHUB_OUTPUT
          echo "env_dir=environments/${ENV}" >> $GITHUB_OUTPUT

  plan:
    name: Terragrunt Plan (${{ needs.detect-environment.outputs.environment }})
    runs-on: ubuntu-latest
    needs: detect-environment
    timeout-minutes: 20
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    env:
      ENV: ${{ needs.detect-environment.outputs.environment }}
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Setup Terragrunt
        run: |
          curl -sLo /usr/local/bin/terragrunt \
            "https://github.com/gruntwork-io/terragrunt/releases/download/v${{ env.TG_VERSION }}/terragrunt_linux_amd64"
          chmod +x /usr/local/bin/terragrunt

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars[format('AWS_ROLE_ARN_{0}', needs.detect-environment.outputs.environment)] }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Terragrunt Plan
        run: terragrunt run-all plan --terragrunt-non-interactive -no-color 2>&1 | tee /tmp/plan.txt
        working-directory: environments/${{ env.ENV }}

      - name: Comment PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const out = fs.readFileSync('/tmp/plan.txt', 'utf8');
            const truncated = out.length > 60000 ? out.slice(-60000) : out;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `<details><summary>📋 Terragrunt Plan — ${{ env.ENV }}</summary>\n\n\`\`\`\n${truncated}\n\`\`\`\n</details>`
            });
```

---

## Branch → Environment Mapping

The same mapping used by `terraform-deploy.yml` applies to Terragrunt:

| Git branch | Environment | AWS Profile / Role |
|---|---|---|
| `feature/*`, `develop` | `dev` | `github-actions-terraform-dev` |
| `release/*` | `qa` | `github-actions-terraform-qa` |
| `main` | `prod` | `github-actions-terraform-prod` |

`release/*` and `main` require PR approval before merge — this enforces the human gate on
qa and prod deployments.

---

## Migrating from the Current Setup

You do not need to migrate everything at once. The recommended phased approach:

### Phase 1 — Keep CI/CD as-is, add Terragrunt locally (week 1)
1. Create `environments/` and `modules/` directories.
2. Extract `bootstrap/` into `modules/github-oidc-bootstrap/`.
3. Write per-env `terragrunt.hcl` files.
4. Verify `terragrunt plan` locally matches what CI/CD produces.

### Phase 2 — Add Terragrunt CI/CD job (week 2)
1. Add `terragrunt-deploy.yml` workflow (see [CI/CD Integration](#step-6-cicd-integration)).
2. Run both workflows in parallel for one sprint.
3. Confirm outputs are identical.

### Phase 3 — Retire the old workflow (week 3)
1. Remove `bootstrap/terraform-deploy.yml` or disable it.
2. Point all documentation at the new Terragrunt workflow.
3. Archive the `bootstrap/` directory or keep it as a reference.

---

## Common Terragrunt Commands Reference

```bash
# Plan a single module
terragrunt plan

# Apply a single module
terragrunt apply

# Plan all modules under the current directory (recursive)
terragrunt run-all plan

# Apply all modules, respecting dependency order
terragrunt run-all apply

# Destroy a single environment (CAREFUL)
terragrunt run-all destroy --terragrunt-non-interactive

# Show the generated backend.tf and versions_override.tf
terragrunt render-json

# Clear the Terragrunt cache
find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null

# Validate all configs
terragrunt run-all validate

# Force unlock a stuck state (replace LOCK_ID with value from error message)
terragrunt force-unlock LOCK_ID
```

---

## Further Reading

- [Terragrunt documentation](https://terragrunt.gruntwork.io/docs/)
- [Gruntwork Reference Architecture](https://gruntwork.io/reference-architecture/)
- [ADR-0001: Why ARN-based isolation instead of ABAC](adr/0001-arn-based-isolation-vs-abac.md)
- [ADR-0002: Why S3 native locking instead of DynamoDB](adr/0002-s3-native-locking-vs-dynamodb.md)
- [State bucket recovery runbook](runbooks/state-bucket-recovery.md)
