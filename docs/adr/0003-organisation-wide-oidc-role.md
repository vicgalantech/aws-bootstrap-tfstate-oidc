# ADR-0003: Organisation-Wide OIDC Role With Broad IAM Permissions

## Status

Accepted (risk acknowledged)

## Context

The `github-actions-terraform-{env}` IAM role created by this bootstrap has broad IAM permissions:

```hcl
# IAMManagement statement
actions   = ["iam:*"]
resources = ["*"]

# CloudTrailManagement statement
actions   = ["cloudtrail:*"]
resources = ["*"]
```

The standard security recommendation is to scope `resources` to specific ARNs managed by this
bootstrap (e.g., `arn:aws:iam::*:role/github-actions-terraform-*`). This follows the principle
of least privilege.

**Why broad permissions are intentional here:**

This bootstrap project is not only responsible for creating the OIDC provider and the bootstrap
role itself — it is the **foundation role** for the entire organisation's CI/CD automation. The
same role (or roles derived from it) will be used to provision:

- Lambda functions and their execution roles
- ECS/Fargate clusters, task definitions, and associated IAM roles
- Bedrock model access policies
- RDS instances and their parameter groups
- API Gateway configurations
- Future projects added to the organisation

If `resources` is scoped to bootstrap-only ARNs, every new project that needs IAM management
would require a new bootstrap deployment to extend the role. This defeats the purpose of having
a shared CI/CD foundation.

## Decision

Accept the broad `resources = ["*"]` for IAM and CloudTrail management statements, with the
following mitigations:

1. **OIDC trust policy** — The role can only be assumed via GitHub Actions OIDC from a specific
   GitHub organisation. No human or service account can assume this role directly.
2. **Branch restrictions** — The OIDC subject claim is scoped to specific branches
   (`main`, `develop`, `release/*`, `feature/*`). Arbitrary forks cannot assume the role.
3. **Separate role per environment** — `github-actions-terraform-dev` cannot affect `prod`
   resources, even though both have `resources = ["*"]`, because S3/KMS/CloudTrail ARNs are
   restricted by environment name in other statements.
4. **Session tagging** — Every assume-role call tags the session with `github-actor`, enabling
   CloudTrail attribution of every API call to a specific engineer.

## Consequences

**Positive:**
- Single bootstrap deployment enables the entire organisation's CI/CD automation.
- New projects can be provisioned without updating the bootstrap role policy.
- Reduces operational overhead — no need to maintain separate IAM roles for each project type.

**Negative / Risks:**
- A compromised GitHub Actions workflow in the allowed repository could create or modify any IAM
  resource in the account. This is a high-impact risk.
- The role technically allows privilege escalation (creating an admin role and attaching
  `AdministratorAccess`).

**When to revisit this decision:**
- If the organisation adopts a multi-account strategy (separate AWS accounts for each project
  or business unit), each account's bootstrap role should be scoped to that account's resources.
- If the security team requires a penetration test or SOC 2 audit, this statement will likely
  be flagged. At that point, consider splitting the role into `BootstrapRole` (scoped to
  bootstrap resources) and `ProjectProvisioningRole` (separate trust policy, broader scope).
- If a workflow compromise occurs in any repository with access to this role, immediately revoke
  the role's trust policy and rotate credentials. See the
  [Security Incident Response runbook](../runbooks/state-bucket-recovery.md).
