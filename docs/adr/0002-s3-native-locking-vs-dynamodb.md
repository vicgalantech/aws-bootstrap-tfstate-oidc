# ADR-0002: S3 Native State Locking Instead of DynamoDB

## Status

Accepted

## Context

Terraform state stored in S3 requires a locking mechanism to prevent concurrent `apply` runs from
corrupting the state file. Before Terraform 1.10, the only supported locking backend for S3 was
a DynamoDB table.

**The self-referential bootstrap problem with DynamoDB:**

This project bootstraps the very S3 bucket that will later store Terraform state. With DynamoDB
locking, you need to also bootstrap a DynamoDB table. This creates a circular dependency:

- You cannot use Terraform to create the DynamoDB table if the remote backend (which requires
  the DynamoDB table) is not yet configured.
- The workaround was to apply twice: once with a local backend to create both S3 and DynamoDB,
  then migrate the backend to S3+DynamoDB.
- Any mistake in this two-phase process leaves an inconsistent state.

Additionally, every environment requires its own DynamoDB table, adding cost and operational
overhead (table management, capacity planning, IAM permissions for `dynamodb:PutItem`,
`dynamodb:GetItem`, `dynamodb:DeleteItem`).

**What Terraform 1.10 introduced:**

[Terraform 1.10](https://www.hashicorp.com/blog/terraform-1-10-improves-handling-of-sensitive-outputs-in-state)
added native S3 state locking using S3 **conditional writes** (`If-None-Match: *` header on
`PutObject`). A `.tflock` file is written to S3 alongside the state file. No external service
is required.

## Decision

Use S3 native locking (`use_lockfile = true` in the backend configuration) instead of DynamoDB.

```hcl
# bootstrap/providers.tf
terraform {
  backend "s3" {
    use_lockfile = true   # S3 conditional writes — no DynamoDB needed
    encrypt      = true
  }
}
```

The minimum Terraform version is pinned to `>= 1.10.0` in `bootstrap/versions.tf` to enforce this.

## Consequences

**Positive:**
- Eliminates the DynamoDB table bootstrap problem — one phase deployment.
- Reduces AWS resource count per environment (no DynamoDB table to manage, monitor, or pay for).
- Simplifies IAM: the role no longer needs DynamoDB permissions.
- The `.tflock` file is visible in S3 alongside the state file, making lock status easy to inspect.

**Negative:**
- S3 native locking requires Terraform `>= 1.10.0`. Older versions of Terraform or OpenTofu
  that predate this feature will silently skip locking and risk state corruption.
  Enforcement via `required_version = ">= 1.10.0"` in `versions.tf` is mandatory.
- S3 native locking is eventually consistent in multi-region setups. For single-region deployments
  (this project targets `eu-west-1`) this is not a practical concern.
- If a Terraform process is killed mid-apply, the `.tflock` file may remain. Manual removal via
  `aws s3 rm s3://bucket/bootstrap/terraform.tfstate.tflock` is required to unblock subsequent runs.
  (Same issue exists with DynamoDB — the lock record must be manually deleted.)
