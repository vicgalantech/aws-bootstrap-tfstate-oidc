# Runbook: GitHub Actions OIDC Trust Failure

**Severity:** P1 — All CI/CD deployments are blocked  
**Owner:** Platform / DevOps team  
**Last reviewed:** March 2026

---

## Symptom

GitHub Actions job fails at the `Configure AWS credentials` step with one of:

```
Error: Could not assume role with OIDC:
  Not authorized to perform sts:AssumeRoleWithWebIdentity

Error: No OpenIDConnect provider found in your account for
  https://token.actions.githubusercontent.com

Error: The security token included in the request is expired
```

---

## Triage Decision Tree

```
OIDC auth fails in CI
        │
        ├─ Error: "No OpenIDConnect provider found"
        │         └─> Go to: Scenario A — OIDC provider deleted
        │
        ├─ Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"
        │         ├─ Sub-claim mismatch (wrong repo/branch)
        │         │         └─> Go to: Scenario B — Sub-claim mismatch
        │         └─ Role ARN wrong or role deleted
        │                   └─> Go to: Scenario C — IAM role misconfigured
        │
        ├─ Error: "security token expired"
        │         └─> Go to: Scenario D — Clock skew / token expiry
        │
        └─ Error: "aud claim does not match"
                  └─> Go to: Scenario E — Audience claim misconfigured
```

---

## Diagnostic Commands

Run these first to understand the current state:

```bash
ENV="dev"   # or qa / prod
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Confirm the OIDC provider exists
aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[*].Arn" --output table

# 2. Get the OIDC provider details
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_ARN}"

# 3. Check the IAM role trust policy
aws iam get-role \
  --role-name "github-actions-terraform-${ENV}" \
  --query 'Role.AssumeRolePolicyDocument' | jq .

# 4. Check the role ARN stored as a GitHub Actions variable
# (compare against the actual role ARN above)
echo "Expected GitHub variable: AWS_ROLE_ARN_$(echo ${ENV} | tr '[:lower:]' '[:upper:]')"
```

---

## Scenario A: OIDC Provider Deleted

**Symptom:** `aws iam list-open-id-connect-providers` does not return the GitHub endpoint.

### Recovery

```bash
# Re-import the OIDC provider into Terraform state and re-apply via Terraform.
# Do NOT re-create manually — Terraform must own this resource.

# Option 1 (preferred): run locally with admin credentials
export AWS_PROFILE=bootstrap-${ENV}
cd live/${ENV}/bootstrap

# Init if needed
terragrunt init

# Re-create via Terraform
terragrunt apply -target=aws_iam_openid_connect_provider.github_actions
```

If the OIDC provider was never in state (bootstrap ran without it), create it manually then import:

```bash
# Re-create manually
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list \
    6938fd4d98bab03faadb97b34396831e3780aea1 \
    1c58a3a8518e8759bf075b76b750d4f2df264fcd

# Import into Terraform state
terragrunt import \
  --terragrunt-working-dir live/${ENV}/bootstrap \
  aws_iam_openid_connect_provider.github_actions \
  "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

# Verify plan shows zero changes
terragrunt plan --terragrunt-working-dir live/${ENV}/bootstrap
```

---

## Scenario B: Sub-Claim Mismatch

**Symptom:** Auth fails with "Not authorized" and the GitHub Actions log shows the token subject claim:

```
sub: repo:myorg/myrepo:ref:refs/heads/feature/my-feature
```

but the trust policy only allows `repo:myorg/myrepo:ref:refs/heads/main`.

### Diagnosis

Check what sub-claim GitHub is presenting:

1. Add a debug step to the failing workflow temporarily:
   ```yaml
   - name: Debug OIDC token
     run: |
       echo "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
   ```

2. Compare the `sub` field from the token against the trust policy condition:
   ```bash
   aws iam get-role \
     --role-name "github-actions-terraform-${ENV}" \
     --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' | jq .
   ```

### Fix

**Option 1 — Allow the branch** (temporary, for emergency):

Update `allowed_branches` in `live/${ENV}/bootstrap/terragrunt.hcl` to include the new pattern and apply.

**Option 2 — Disable branch restriction** (permanent, less secure):

In `live/${ENV}/bootstrap/terragrunt.hcl`:
```hcl
enable_branch_restriction = false
```

Apply via CI/CD after merging the change.

---

## Scenario C: IAM Role Misconfigured or Deleted

**Symptom:** Auth fails with "Not authorized" but the OIDC provider exists and the sub-claim matches.

```bash
# Verify the role exists
aws iam get-role --role-name "github-actions-terraform-${ENV}" 2>&1

# Verify the GitHub Actions variable matches the actual role ARN
aws iam get-role \
  --role-name "github-actions-terraform-${ENV}" \
  --query 'Role.Arn' --output text
```

### Fix: Role ARN variable mismatch

The role ARN stored as the GitHub Actions variable is wrong:

1. Get the correct ARN:
   ```bash
   aws iam get-role \
     --role-name "github-actions-terraform-${ENV}" \
     --query 'Role.Arn' --output text
   ```

2. Update the GitHub repository variable:
   - Go to `Settings → Secrets and variables → Actions → Variables`
   - Update `AWS_ROLE_ARN_DEV` / `AWS_ROLE_ARN_QA` / `AWS_ROLE_ARN_PROD`

### Fix: Role deleted

```bash
# Re-create via Terraform (same as Scenario A)
export AWS_PROFILE=bootstrap-${ENV}
terragrunt apply \
  --terragrunt-working-dir live/${ENV}/bootstrap \
  -target=aws_iam_role.github_actions \
  -target=aws_iam_role_policy_attachment.github_actions_terraform_deployment
```

---

## Scenario D: Clock Skew / Token Expiry

**Symptom:** `The security token included in the request is expired`

This is almost always a GitHub Actions infrastructure issue, not a configuration problem.

1. Check [GitHub Status](https://www.githubstatus.com/) for Actions incidents.
2. Re-run the failed workflow — OIDC tokens are short-lived (15 minutes) and expiry during a slow job startup can trigger this.
3. If the error persists, check whether the runner's system clock is skewed:
   ```yaml
   - name: Check runner time
     run: date -u
   ```
   AWS requires the request timestamp to be within 5 minutes of actual UTC time.

---

## Scenario E: Audience Claim Misconfigured

**Symptom:** `aud claim does not match`

The trust policy expects `sts.amazonaws.com` as the audience but the GitHub workflow is
requesting a different audience.

Check the workflow's `configure-aws-credentials` step — it must NOT override `audience`:
```yaml
- uses: aws-actions/configure-aws-credentials@<sha>
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN_DEV }}
    aws-region: eu-west-1
    # Do NOT add: audience: ...  (default is sts.amazonaws.com which is correct)
```

If the OIDC provider was created with a different client ID, update it:
```bash
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn "${OIDC_ARN}" \
  --thumbprint-list \
    6938fd4d98bab03faadb97b34396831e3780aea1 \
    1c58a3a8518e8759bf075b76b750d4f2df264fcd

# Client IDs can only be added/removed, not edited
aws iam add-client-id-to-open-id-connect-provider \
  --open-id-connect-provider-arn "${OIDC_ARN}" \
  --client-id sts.amazonaws.com
```

---

## OIDC Thumbprint Rotation

GitHub periodically rotates the certificate for `token.actions.githubusercontent.com`.
When this happens all OIDC authentications fail globally.

```bash
# Get the current valid thumbprints from GitHub
# (run this from any machine with openssl)
openssl s_client -servername token.actions.githubusercontent.com \
  -connect token.actions.githubusercontent.com:443 \
  -showcerts </dev/null 2>/dev/null \
  | openssl x509 -fingerprint -sha1 -noout \
  | tr -d ':' | awk -F= '{print tolower($2)}'

# Update the Terraform variable in modules/bootstrap/iam-oidc.tf
# and apply via CI/CD
```

The two thumbprints currently configured in `iam-oidc.tf` are:
- `6938fd4d98bab03faadb97b34396831e3780aea1`
- `1c58a3a8518e8759bf075b76b750d4f2df264fcd`

---

## Post-Recovery Checklist

- [ ] GitHub Actions job completes successfully end-to-end
- [ ] `terraform plan` shows **zero changes** (re-applied resources are in sync with state)
- [ ] OIDC provider thumbprints match the current GitHub certificate
- [ ] The incident is documented in your team's incident log
- [ ] The GitHub Actions variable `AWS_ROLE_ARN_<ENV>` is confirmed correct
