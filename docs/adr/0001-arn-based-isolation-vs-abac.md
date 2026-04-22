# ADR-0001: ARN-Based Environment Isolation Instead of ABAC Resource Tags

## Status

Accepted

## Context

We needed a mechanism to prevent the GitHub Actions role for `dev` from accidentally modifying
resources in `qa` or `prod`.

The initial implementation used **Attribute-Based Access Control (ABAC)**:

- The S3 state bucket was tagged with `environment = "dev"`.
- The IAM policy used `s3:ResourceTag/environment` conditions to allow access only to buckets
  whose `environment` tag matched `aws:PrincipalTag/environment` (the session tag passed by the
  GitHub Actions OIDC workflow).
- The idea: the same IAM role can exist in all environments, and the tags on both the principal
  and the resource control what each instance can touch.

**Why ABAC failed in CI/CD:**

1. The S3 state bucket must exist before Terraform can read state. On a clean deployment, the
   bucket does not exist and has no tags.
2. When `aws s3api head-bucket` is called before the bucket exists, AWS evaluates the
   `s3:ResourceTag` condition against a non-existent resource and returns a 403 (not 404).
3. This caused Terraform to believe the bucket had been "deleted outside Terraform" on every
   CI/CD run, triggering a drift false-positive.
4. The `terraform import` workaround that was added to compensate was itself destructive if
   the import failed mid-execution (state left in a partially removed state).

## Decision

Replace ABAC resource-tag conditions with **ARN-based environment isolation**:

- The environment name is embedded directly in the resource name:
  `{company}-tfstate-{environment}-{account_id}`
- IAM policies restrict access using ARN patterns that include the environment name:
  `arn:aws:s3:::{company}-*-{environment}-*`
- A separate IAM role is deployed per environment
  (`github-actions-terraform-dev`, `github-actions-terraform-prod`).
- Each role's OIDC trust policy restricts which GitHub branches can assume it.

The `aws:PrincipalTag/environment` session tag is still set by the workflow for audit trail
purposes (visible in CloudTrail), but it is no longer used in IAM `Condition` blocks to gate
resource access.

## Consequences

**Positive:**
- No 403/404 ambiguity during S3 operations — bucket existence is checked by Terraform, not
  by `head-bucket` + tag evaluation.
- Removes the need for the unconditional `terraform state rm` + `terraform import` reconcile
  step, which was a latent data-loss risk.
- Simpler IAM policies — ARN patterns are easy to read and audit.
- Consistent behaviour between local `terraform plan` and CI/CD runs.

**Negative:**
- ARN-based isolation is less flexible than ABAC: if you rename an environment or add a new one,
  you must update both the bucket naming convention and the IAM ARN patterns.
- You cannot use a single IAM role across environments — one role per environment is required.
  (This is actually desirable for blast-radius reduction, but increases the number of resources
  to manage.)
- If someone creates an out-of-convention bucket name (e.g., `my-bucket-dev`), it falls outside
  the IAM policy's ARN pattern and Terraform cannot manage it with this role.
