# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the `terraform-aws-github-oidc` project.
ADRs document key design choices so that future engineers understand **why** the system works the way it does,
not just **how**.

Format: [MADR (Markdown Architectural Decision Records)](https://adr.github.io/madr/)

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-arn-based-isolation-vs-abac.md) | ARN-based environment isolation instead of ABAC resource tags | Accepted |
| [0002](0002-s3-native-locking-vs-dynamodb.md) | S3 native state locking instead of DynamoDB | Accepted |
| [0003](0003-organisation-wide-oidc-role.md) | Organisation-wide OIDC role with broad IAM permissions | Accepted (risk acknowledged) |
| [0004](0004-hybrid-terragrunt-terraform-cicd.md) | Hybrid Terragrunt/Terraform CI/CD architecture | Accepted |

## How to Add an ADR

1. Copy the template below into a new file `docs/adr/NNNN-short-title.md`
2. Fill in all sections
3. Add a row to the index above
4. Open a PR — ADRs are reviewed like code changes

```markdown
# ADR-NNNN: Title

## Status
Proposed | Accepted | Deprecated | Superseded by [ADR-XXXX]

## Context
What is the issue or situation that led to this decision?

## Decision
What did we decide to do?

## Consequences
What are the positive and negative consequences of this decision?
```
