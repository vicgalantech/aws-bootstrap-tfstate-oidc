# ADR-0005: SSM Parameter Store for Cross-Project Infrastructure Exports

## Status

Accepted

## Context

For scalable AWS architectures, managing dependencies between projects is critical. The bootstrap module creates foundational infrastructure (S3 state bucket, KMS keys, IAM roles) that downstream projects need to consume.

**The Problem:** How do we share infrastructure outputs between independent Terraform projects?

In CloudFormation, this is solved with `Outputs` and `Export/Import`. In the Terraform ecosystem, there are three main approaches:

### Option 1: AWS SSM Parameter Store

Publish values to AWS SSM Parameter Store. Other projects query the parameter by path.

```hcl
# Project A (creates the bucket)
resource "aws_ssm_parameter" "bucket_name" {
  name  = "/infra/storage/bucket-id"
  type  = "String"
  value = aws_s3_bucket.main.id
}

# Project B (consumes the bucket)
data "aws_ssm_parameter" "bucket" {
  name = "/infra/storage/bucket-id"
}
# Usage: data.aws_ssm_parameter.bucket.value
```

### Option 2: Terraform Remote State

Native Terraform approach where one state reads outputs from another state stored in S3.

```hcl
# Project B
data "terraform_remote_state" "bootstrap" {
  backend = "s3"
  config = {
    bucket = "tfstate-bucket"
    key    = "env/bootstrap/terraform.tfstate"
    region = "eu-west-1"
  }
}
# Usage: data.terraform_remote_state.bootstrap.outputs.bucket_id
```

### Option 3: Terragrunt Dependency

Terragrunt passes outputs between modules automatically during execution.

```hcl
# In terragrunt.hcl
dependency "bootstrap" {
  config_path = "../bootstrap"
}

inputs = {
  bucket_id = dependency.bootstrap.outputs.bucket_id
}
```

### Comparison Matrix

| Criteria | SSM Parameter Store | Remote State | Terragrunt Dependency |
|----------|--------------------|--------------|-----------------------|
| **Decoupling** | 🟢 Maximum | 🟡 Medium | 🔴 Minimum (Coupled) |
| **Security (IAM)** | Excellent (by path) | Complex (S3/KMS) | High |
| **AWS Console Visibility** | ✅ Yes | ❌ No | ❌ No |
| **Cross-Account Support** | ✅ Native | ⚠️ Complex | ⚠️ Complex |
| **Tooling Independence** | ✅ Any tool can read | ❌ Terraform only | ❌ Terragrunt only |
| **Audit Trail** | ✅ CloudTrail | ❌ None | ❌ None |

## Decision

Use **AWS SSM Parameter Store** for exporting infrastructure values.

**Rationale:**

1. **Maximum Decoupling:** Project B doesn't need to know anything about Project A's state file location, backend configuration, or Terraform version. It only needs to know the parameter path.

2. **AWS-Native Visibility:** Parameters are visible in the AWS Console, making debugging and auditing straightforward. Operations teams can inspect values without Terraform access.

3. **IAM-Based Security:** Access control is managed through standard IAM policies scoped to parameter paths (e.g., `arn:aws:ssm:*:*:parameter/dev/bootstrap/*`).

4. **CloudFormation Parity:** This approach mirrors CloudFormation's `Export/Import` pattern, making it familiar to teams with CloudFormation experience.

5. **Tool Agnostic:** Any tool (Terraform, Pulumi, CDK, scripts, Lambda functions) can read SSM parameters. Not locked into Terraform ecosystem.

6. **Cross-Account Ready:** SSM parameters can be shared across accounts using resource-based policies or AWS RAM, enabling future multi-account architectures.

**Why Not Remote State?**

- Requires Project B to have read access to Project A's S3 state bucket and KMS key
- Tightly couples projects to Terraform's state format
- No visibility outside Terraform tooling
- State file contains sensitive information beyond what's needed

**Why Not Terragrunt Dependency?**

- Only works within the same Terragrunt execution context
- Requires all dependent modules to be in the same repository or accessible path
- Doesn't work for truly independent projects deployed separately

## Implementation

### Exported Parameters

| Parameter Path | Value | Description |
|----------------|-------|-------------|
| `/{env}/bootstrap/tfstate-bucket-name` | S3 bucket ID | State bucket name |
| `/{env}/bootstrap/tfstate-bucket-arn` | S3 bucket ARN | For IAM policies |
| `/{env}/bootstrap/tfstate-kms-key-arn` | KMS key ARN | For encryption |
| `/{env}/bootstrap/tfstate-kms-key-alias` | KMS alias | Human-readable reference |
| `/{env}/bootstrap/github-actions-role-arn` | IAM role ARN | For OIDC authentication |
| `/{env}/bootstrap/aws-region` | Region | Deployment region |

### IAM Permissions

GitHub Actions role includes:
- `ssm:PutParameter`, `ssm:DeleteParameter` - Create/update parameters
- `ssm:GetParameter`, `ssm:GetParameters`, `ssm:GetParametersByPath` - Read parameters
- `ssm:AddTagsToResource`, `ssm:RemoveTagsFromResource` - Manage tags

All scoped to: `arn:aws:ssm:*:ACCOUNT_ID:parameter/{env}/bootstrap/*`

## Consequences

**Positive:**

- ✅ **Loose coupling:** Downstream projects only depend on parameter paths, not state files
- ✅ **AWS-native:** Visible in console, auditable via CloudTrail
- ✅ **Secure:** IAM policies control access by path
- ✅ **Flexible:** Any tool can consume the parameters
- ✅ **Self-documenting:** Parameter names describe their purpose

**Negative:**

- ⚠️ **Additional resources:** Creates SSM parameters that must be managed
- ⚠️ **Eventual consistency:** Parameter updates are not atomic with infrastructure changes
- ⚠️ **Cost:** SSM Parameter Store has API call costs (minimal for standard parameters)

**Mitigation:**

- Parameters are created in the same `terraform apply` as the resources they reference
- Standard (non-advanced) parameters are free to store, only API calls are charged
- Parameter paths follow a consistent naming convention for discoverability

## Related

- **Complements:** [ADR-0004](0004-hybrid-terragrunt-terraform-cicd.md) - CI/CD can read parameters for configuration
- **Enables:** Future multi-project architectures sharing bootstrap infrastructure
