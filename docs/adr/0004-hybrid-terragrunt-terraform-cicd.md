# ADR-0004: Hybrid Terragrunt/Terraform CI/CD Architecture

## Status

Accepted

## Context

We needed a reliable deployment strategy that supports both local development workflows and automated CI/CD deployments through GitHub Actions.

**Initial Approach: Terragrunt Everywhere**

The original plan was to use Terragrunt for both local development and CI/CD:
- Developers run `terragrunt plan` and `terragrunt apply` locally
- GitHub Actions runs the same Terragrunt commands in CI/CD
- Single workflow, consistent tooling everywhere

**Why Terragrunt in CI/CD Failed:**

We encountered multiple critical issues when attempting to use Terragrunt in GitHub Actions:

**Issue 1: Wrapper Incompatibility**

When running Terragrunt in GitHub Actions with HashiCorp's `setup-terraform` action:

```
Running command: terraform --version
ERROR: signal: broken pipe / exit status 1
```

**Root Cause:**
1. The `setup-terraform` GitHub Action wraps the Terraform binary with a shell script to capture outputs
2. Terragrunt performs internal version checking by executing `terraform --version`
3. The wrapper script breaks this subprocess communication, causing pipe failures
4. This occurs regardless of the `terraform_wrapper: false` setting
5. Without the wrapper: `signal: broken pipe`
6. With the wrapper: `exit status 1`

**Issue 2: Saved Plan Variable Mismatch**

Even when the wrapper issue was bypassed, Terragrunt's internal caching mechanism caused variable mismatch errors:

```
Error: Can't change variable when applying a saved plan

The variable allowed_branches cannot be set using the -var and -var-file
options when applying a saved plan file, because a saved plan includes the
variable values that were set when it was created. The saved plan specifies
"[\"main\",\"develop\",\"release/*\",\"feature/*\"]" as the value whereas
during apply the value tuple with 4 elements was set by an environment
variable.
```

```
Error: Can't change variable when applying a saved plan

The variable tags cannot be set using the -var and -var-file options when
applying a saved plan file, because a saved plan includes the variable
values that were set when it was created. The saved plan specifies
"{\"Environment\":\"dev\",\"ManagedBy\":\"Terragrunt\",\"Project\":\"bootstrap\",\"Team\":\"DevOps\"}"
as the value whereas during apply the value object with 4 attributes was
set by an environment variable.
```

**Root Cause:**
1. Terragrunt caches generated files in `.terragrunt-cache/` including plan files
2. Running `terragrunt plan` followed by `terragrunt apply` creates a saved plan
3. Terragrunt injects variables dynamically during each invocation
4. Terraform's strict validation detects the variable values changed between plan and apply
5. Attempting to clear the cache (`rm -rf .terragrunt-cache`) before apply didn't resolve the issue
6. The problem persisted because Terragrunt's internal plan generation happens before the cache clear

**Alternatives Considered:**

1. **Remove separate plan step** - Run only `terragrunt apply` (which plans internally)
   - **Rejected:** Loses visibility into changes before apply in CI/CD
   
2. **Install Terraform manually without setup-terraform action**
   - **Rejected:** Loses GitHub Actions integration features (automatic output formatting, version caching)
   
3. **Use ephemeral variables** (`ephemeral = true` in Terraform 1.10+)
   - **Rejected:** Would require significant module refactoring and loses audit trail of variable values in state

## Decision

Implement a **hybrid architecture**:

**Local Development: Terragrunt**
- Developers continue using Terragrunt for all operations
- `terragrunt plan`, `terragrunt apply` work without modification
- Full Terragrunt feature set (DRY config, multiple includes, code generation)

**CI/CD: Pure Terraform with Dynamic Configuration**
1. Extract variables from Terragrunt HCL files (`common.hcl`, `account.hcl`) using grep/awk
2. Generate `backend.tf` dynamically (mimicking Terragrunt's backend generation)
3. Generate `terraform.tfvars` from extracted values
4. Run native `terraform init`, `terraform plan`, `terraform apply`
5. Use the same S3 state files as local Terragrunt

**Implementation Details:**

The GitHub Actions workflow:
```yaml
# Extract values from Terragrunt HCL files
- Extract variables from live/common.hcl
- Get AWS Account ID from AWS STS
- Generate terraform.tfvars with extracted values

# Mimic Terragrunt backend generation
- Generate backend.tf with S3 configuration
- terraform init -reconfigure

# Standard Terraform workflow
- terraform plan -out=tfplan
- terraform apply tfplan
```

**Key Principle:** Single source of truth remains in Terragrunt HCL files. CI/CD extracts from these files rather than duplicating configuration.

## Consequences

**Positive:**

- ✅ **Local workflow unchanged:** Developers use familiar Terragrunt commands
- ✅ **Reliable CI/CD:** Pure Terraform bypasses all wrapper compatibility issues
- ✅ **Single source of truth:** All configuration lives in Terragrunt HCL files
- ✅ **Identical state files:** Both local and CI/CD use the same S3 state
- ✅ **Environment isolation:** Branch detection ensures correct environment deployment
- ✅ **No duplicate configuration:** CI/CD extracts values dynamically from HCL

**Negative:**

- ⚠️ **Increased complexity:** Workflow must replicate Terragrunt behavior (backend generation, variable extraction)
- ⚠️ **Two code paths:** Local Terragrunt and CI/CD Terraform must be kept in sync
- ⚠️ **Maintenance overhead:** Changes to variables require updates to extraction logic
- ⚠️ **Parsing fragility:** grep/awk parsing of HCL is brittle compared to native HCL evaluation
- ⚠️ **Testing burden:** Must verify both local and CI/CD paths work correctly

**Mitigation:**

- Workflow variable extraction is simple and well-documented
- HCL file structure is stable (common.hcl, account.hcl rarely change)
- CI/CD tests validate that generated configuration matches expected values
- Alternative parsing (using `terragrunt output` or `hcl2json`) considered for future improvement

**Why This Trade-off is Acceptable:**

The alternative (debugging and maintaining workarounds for Terragrunt/GitHub Actions wrapper issues) proved more costly than maintaining the hybrid approach. Developer productivity locally takes priority, and the CI/CD complexity is isolated to a single workflow file.

## Related

- **Supersedes:** Previous attempts to use Terragrunt with `terraform_wrapper: false`
- **Complements:** [ADR-0002](0002-s3-native-locking-vs-dynamodb.md) - Both local and CI/CD use the same S3 backend
