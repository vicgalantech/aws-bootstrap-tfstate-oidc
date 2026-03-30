# Runbook: Terraform State Bucket Recovery

**Severity:** P1 — Infrastructure operations are blocked until resolved  
**Owner:** Platform / DevOps team  
**Last reviewed:** March 2026

---

## Symptom

One or more of the following:

- `terraform init` fails with: `NoSuchBucket: The specified bucket does not exist`
- GitHub Actions plan/apply jobs fail at the `Terraform Init` step
- `aws s3 ls s3://<company>-tfstate-<env>-<account_id>` returns `NoSuchBucket`

---

## Root Causes

| Cause | Likelihood | Recovery path |
|---|---|---|
| Bucket accidentally deleted via AWS Console or CLI | Medium | [Scenario A](#scenario-a-bucket-deleted-state-file-lost) or [B](#scenario-b-bucket-deleted-state-file-backed-up) |
| Bucket exists but versioning disabled and state overwritten | Low | [Scenario C](#scenario-c-state-file-corrupted) |
| S3 lock file stuck (`.tflock`) blocking all operations | High | [Scenario D](#scenario-d-stuck-lock-file) |
| Wrong bucket name in backend config | Low | [Scenario E](#scenario-e-backend-misconfiguration) |

---

## Pre-flight Checks

Run these before taking any action:

```bash
# 1. Confirm which environment is affected
ENV="dev"   # or qa / prod
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="tfstate-<company_name>-${ENV}-${ACCOUNT_ID}"

# 2. Check if bucket exists
aws s3api head-bucket --bucket "${BUCKET}" 2>&1

# 3. Check if state file exists
aws s3 ls "s3://${BUCKET}/bootstrap/terraform.tfstate"

# 4. Check for a stuck lock file
aws s3 ls "s3://${BUCKET}/bootstrap/terraform.tfstate.tflock"
```

---

## Scenario A: Bucket Deleted, State File Lost

The bucket and state file are gone. No versioned backup exists.

**Impact:** All Terraform-managed resources are orphaned — they exist in AWS but Terraform has
no record of them. Running `terraform apply` will attempt to create duplicates.

### Recovery Steps

1. **Do not run `terraform apply` yet.** It will create duplicate resources.

2. Re-create the bucket manually (it must have versioning and encryption enabled):
   ```bash
   aws s3api create-bucket \
     --bucket "${BUCKET}" \
     --region eu-west-1 \
     --create-bucket-configuration LocationConstraint=eu-west-1

   aws s3api put-bucket-versioning \
     --bucket "${BUCKET}" \
     --versioning-configuration Status=Enabled

   aws s3api put-bucket-encryption \
     --bucket "${BUCKET}" \
     --server-side-encryption-configuration '{
       "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]
     }'

   aws s3api put-public-access-block \
     --bucket "${BUCKET}" \
     --public-access-block-configuration \
       "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
   ```

3. Import all existing resources into a new state file. Run locally with admin credentials:
   ```bash
   cd bootstrap/
   terraform init -backend-config=backend-config.hcl

   # Import the state bucket itself (must be first)
   terraform import aws_s3_bucket.terraform_state "${BUCKET}"

   # Import all other resources one by one:
   terraform import aws_iam_openid_connect_provider.github_actions \
     "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

   terraform import aws_iam_role.github_actions \
     "github-actions-terraform-${ENV}"

   # Continue importing remaining resources shown in `terraform plan`
   ```

4. Run `terraform plan` — it should show zero changes if all imports are correct.

5. Commit nothing. Push a tag to trigger a clean CI/CD plan run to verify.

---

## Scenario B: Bucket Deleted, State File Backed Up

S3 versioning was enabled before deletion. AWS keeps a 30-day recovery window via the Delete Marker.

### Recovery Steps

1. List the deleted bucket's versions:
   ```bash
   aws s3api list-object-versions \
     --bucket "${BUCKET}" \
     --prefix "bootstrap/terraform.tfstate" \
     --query "DeleteMarkers[*].{Key:Key,VersionId:VersionId,Date:LastModified}"
   ```

2. Restore the state file by deleting the Delete Marker:
   ```bash
   DELETE_MARKER_VERSION_ID="<version_id_from_above>"
   aws s3api delete-object \
     --bucket "${BUCKET}" \
     --key "bootstrap/terraform.tfstate" \
     --version-id "${DELETE_MARKER_VERSION_ID}"
   ```

3. Verify the state is restored:
   ```bash
   aws s3 cp "s3://${BUCKET}/bootstrap/terraform.tfstate" /tmp/recovered-state.json
   cat /tmp/recovered-state.json | jq '.resources | length'
   ```

4. Run `terraform plan` — should show zero changes.

---

## Scenario C: State File Corrupted

The state file exists but is malformed (e.g., truncated mid-write).

### Recovery Steps

1. List available versions of the state file:
   ```bash
   aws s3api list-object-versions \
     --bucket "${BUCKET}" \
     --prefix "bootstrap/terraform.tfstate" \
     --query "Versions[*].{VersionId:VersionId,Date:LastModified,Size:Size}" \
     --output table
   ```

2. Restore the most recent valid version:
   ```bash
   GOOD_VERSION_ID="<version_id_from_above>"
   aws s3api copy-object \
     --bucket "${BUCKET}" \
     --copy-source "${BUCKET}/bootstrap/terraform.tfstate?versionId=${GOOD_VERSION_ID}" \
     --key "bootstrap/terraform.tfstate"
   ```

3. Verify:
   ```bash
   aws s3 cp "s3://${BUCKET}/bootstrap/terraform.tfstate" /tmp/state.json
   jq '.version' /tmp/state.json   # should print 4
   ```

---

## Scenario D: Stuck Lock File

A previous Terraform run was killed mid-execution, leaving a `.tflock` file that blocks all
subsequent runs.

**Symptom:** `terraform plan` hangs or immediately errors with:
```
Error: Error locking state: state file .tflock already exists
```

### Recovery Steps

1. Confirm the lock is stale (check the timestamp — if older than 30 minutes, it is safe to remove):
   ```bash
   aws s3 ls "s3://${BUCKET}/bootstrap/terraform.tfstate.tflock"
   ```

2. Download and inspect the lock file to identify who held the lock:
   ```bash
   aws s3 cp "s3://${BUCKET}/bootstrap/terraform.tfstate.tflock" /tmp/lock.json
   cat /tmp/lock.json
   ```

3. Confirm the lock holder's process is dead (check GitHub Actions run status).

4. Remove the lock file:
   ```bash
   aws s3 rm "s3://${BUCKET}/bootstrap/terraform.tfstate.tflock"
   ```

5. Re-run the Terraform operation.

---

## Scenario E: Backend Misconfiguration

The bucket exists and state is intact, but the backend config points to the wrong bucket.

**Common cause:** `vars.COMPANY_NAME` GitHub variable changed, or `ACCOUNT_ID` resolved
incorrectly in CI/CD.

### Recovery Steps

1. Find the correct bucket:
   ```bash
   aws s3 ls | grep tfstate
   ```

2. Update the `COMPANY_NAME` GitHub Actions variable at:
   `Settings → Secrets and variables → Actions → Variables`

3. Re-run the workflow.

---

## Post-Recovery Checklist

- [ ] `terraform plan` shows **zero changes** in CI/CD
- [ ] S3 bucket versioning is enabled: `aws s3api get-bucket-versioning --bucket "${BUCKET}"`
- [ ] S3 bucket encryption is enabled: `aws s3api get-bucket-encryption --bucket "${BUCKET}"`
- [ ] The incident is documented in your team's incident log
- [ ] A retrospective action item is created to prevent recurrence (e.g., enable S3 Object Lock,
      add bucket deletion protection via SCP)
