# Runbook: Infrastructure Drift in Production

**Severity:** P2 — Production infrastructure diverged from Terraform state  
**Owner:** Platform / DevOps team  
**Last reviewed:** March 2026

---

## Symptom

One or more of the following:

- GitHub Actions drift-detection job (runs every Monday 06:00 UTC) created a GitHub Issue titled `⚠️ Infrastructure Drift Detected - prod`
- Manual `make plan ENV=prod` shows unexpected changes
- A resource was modified, deleted, or created manually in the AWS Console

---

## Triage

### Step 1 — Identify what drifted

```bash
export AWS_PROFILE=bootstrap-prod
terragrunt plan \
  --terragrunt-working-dir live/prod/bootstrap \
  -detailed-exitcode \
  -no-color 2>&1 | tee /tmp/drift-plan.txt
```

Review `/tmp/drift-plan.txt`. Terraform uses `~` for in-place updates, `-` for deletions, `+` for additions.

### Step 2 — Classify the drift

| Type | Risk | Action |
|---|---|---|
| Tag changes only | Low | Auto-reconcile via apply |
| IAM policy document changed | **High** | Review manually before applying |
| S3 bucket policy changed | **High** | Review manually — check for privilege escalation |
| KMS key policy changed | **Critical** | Freeze CI/CD — see [KMS key policy drift](#kms-key-policy-drift) |
| Resource deleted (e.g. S3 bucket, IAM role) | **Critical** | Do NOT apply — see [Critical resource deleted](#critical-resource-deleted) |
| CloudTrail disabled or trail deleted | **Critical** | Notify security team immediately |

---

## Reconciliation Paths

### Path A: Safe to reconcile automatically (tag drift, non-security changes)

```bash
export AWS_PROFILE=bootstrap-prod

# Review the plan one more time
terragrunt plan --terragrunt-working-dir live/prod/bootstrap

# Apply only after confirming the changes are expected
terragrunt apply --terragrunt-working-dir live/prod/bootstrap
```

### Path B: IAM / KMS / S3 policy drift — manual review required

1. Download the current live policy from AWS:
   ```bash
   # IAM role trust policy
   aws iam get-role \
     --role-name github-actions-terraform-prod \
     --query 'Role.AssumeRolePolicyDocument' | jq .

   # IAM managed policy
   POLICY_ARN=$(aws iam list-policies --query \
     "Policies[?PolicyName=='TerraformDeploymentPolicy-prod'].Arn" \
     --output text)
   VERSION=$(aws iam get-policy --policy-arn "${POLICY_ARN}" \
     --query 'Policy.DefaultVersionId' --output text)
   aws iam get-policy-version \
     --policy-arn "${POLICY_ARN}" \
     --version-id "${VERSION}" \
     --query 'PolicyVersion.Document' | jq .
   ```

2. Compare against the Terraform-rendered policy:
   ```bash
   terragrunt plan --terragrunt-working-dir live/prod/bootstrap \
     -no-color 2>&1 | grep -A 50 "aws_iam"
   ```

3. If the live policy is **more permissive** than Terraform's version — treat as a security incident. Notify the security team before reconciling.

4. Reconcile after review:
   ```bash
   terragrunt apply --terragrunt-working-dir live/prod/bootstrap
   ```

### KMS key policy drift

1. **Stop all CI/CD operations immediately** — if the KMS key policy was tampered with, credentials may be compromised.
2. Retrieve the current key policy:
   ```bash
   KMS_KEY_ID=$(terragrunt output -json \
     --terragrunt-working-dir live/prod/bootstrap \
     | jq -r '.terraform_state_kms_alias.value')
   aws kms get-key-policy --key-id "${KMS_KEY_ID}" --policy-name default | jq .
   ```
3. Compare against `modules/bootstrap/s3-state.tf` (state bucket key) or `modules/bootstrap/cloudtrail.tf` (CloudTrail key).
4. Rotate the IAM role credentials used by CI/CD (`github-actions-terraform-prod`).
5. Reconcile via Terraform using admin (break-glass) credentials.

### Critical resource deleted

**Never run `terraform apply` when a critical resource is missing.** Terraform will attempt to re-create it, which may cause data loss or leave dependent resources in an inconsistent state.

1. Identify what was deleted from the plan output.
2. If the deletion is accidental:
   - For an **S3 bucket**: follow the [state bucket recovery runbook](./state-bucket-recovery.md).
   - For an **IAM role**: re-create manually, import into state, then apply.
   - For a **KMS key** (deleted, not scheduled): a deleted KMS key is unrecoverable. You must re-create the key, re-encrypt all S3 objects, and re-configure all references.
3. If the deletion is intentional (someone decommissioned a resource):
   - Remove the resource from Terraform source and open a PR.
   - Apply the new state via CI/CD, not manually.

---

## Post-Reconciliation Checklist

- [ ] `terragrunt plan` shows **zero changes** for `live/prod/bootstrap`
- [ ] CloudTrail is enabled and logging: `aws cloudtrail get-trail-status --name centralized-audit-trail-prod`
- [ ] The GitHub Issue opened by drift-detection is closed with a comment describing root cause
- [ ] A retrospective action item is created to prevent recurrence (e.g., SCP to deny manual console changes)

---

## Preventing Future Drift

- Enable AWS Config rules to detect out-of-band IAM and S3 policy changes.
- Add an SCP (Service Control Policy) at the AWS Organization level to deny `DeleteBucket`, `DeleteTrail`, and `DeleteKey` in prod accounts except via the CI/CD role.
- Increase drift-detection frequency from weekly to daily for `prod`.
