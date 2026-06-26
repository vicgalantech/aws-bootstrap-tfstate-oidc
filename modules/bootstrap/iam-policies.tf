# ================================================
# Terraform Deployment IAM Policies
#
# Split into multiple policies to avoid AWS 6,144 character limit.
#
# Security model:
#   1. OIDC trust policy — only GitHub Actions from allowed repos/branches can assume this role.
#   2. ARN-based scope   — all resource-level permissions are scoped to environment-specific
#                          ARN patterns. resources = ["*"] is used ONLY where AWS does not
#                          support resource-level permissions (list operations, kms:CreateKey).
#   3. KMS condition     — kms:CreateKey requires aws:RequestTag/Project = "bootstrap".
#                          KMS management actions require aws:ResourceTag/Project = "bootstrap".
#
# Policies:
#   - Core: S3, KMS, SSM, STS (state management and core infrastructure)
#   - IAM: IAM roles, policies, OIDC, CloudTrail
# ================================================

# ══════════════════════════════════════════════════════════════════════════════
# POLICY 1: Core Infrastructure (S3, KMS, SSM, STS)
# ══════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "terraform_core" {

  # ── S3: List the state bucket ───────────────────────────────────────────────
  statement {
    sid     = "S3StateBucketList"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:aws:s3:::tfstate-${var.company_name}-${var.environment}-*",
    ]
  }

  # ── S3: Read bucket metadata (plan refresh, import, state reads) ────────────
  statement {
    sid    = "S3BucketMetadataRead"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketPolicy",
      "s3:GetBucketTagging",
      "s3:GetLifecycleConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketLogging",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketCors",
      "s3:GetBucketWebsite",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetReplicationConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:ListBucketVersions",
      "s3:PutBucketLogging",
      "s3:PutBucketOwnershipControls",
    ]
    resources = [
      "arn:aws:s3:::tfstate-${var.company_name}-${var.environment}-*",
      "arn:aws:s3:::cloudtrail-${var.company_name}-${var.environment}-*",
    ]
  }

  # ── S3: ListAllMyBuckets — no resource-level support, must be * ─────────────
  statement {
    sid       = "S3ListAllBuckets"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  # ── S3: State object read/write ─────────────────────────────────────────────
  statement {
    sid    = "S3StateObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion",
    ]
    resources = [
      "arn:aws:s3:::tfstate-${var.company_name}-${var.environment}-*/*",
    ]
  }

  # ── S3: Create and manage buckets ───────────────────────────────────────────
  statement {
    sid    = "S3BucketManage"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketObjectLockConfiguration",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketLogging",
      "s3:PutBucketAcl",
    ]
    resources = [
      "arn:aws:s3:::tfstate-${var.company_name}-${var.environment}-*",
      "arn:aws:s3:::cloudtrail-${var.company_name}-${var.environment}-*",
    ]
  }

  # ── KMS: CreateKey — enforce Project tag ────────────────────────────────────
  statement {
    sid       = "KMSCreateKey"
    effect    = "Allow"
    actions   = ["kms:CreateKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["bootstrap"]
    }
  }

  # ── KMS: Alias management ───────────────────────────────────────────────────
  statement {
    sid    = "KMSAliasWrite"
    effect = "Allow"
    actions = [
      "kms:CreateAlias",
      "kms:DeleteAlias",
    ]
    resources = [
      "arn:aws:kms:*:${local.account_id}:alias/${var.company_name}-*",
    ]
  }

  statement {
    sid       = "KMSAliasTargetKey"
    effect    = "Allow"
    actions   = ["kms:CreateAlias"]
    resources = ["arn:aws:kms:*:${local.account_id}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["bootstrap"]
    }
  }

  statement {
    sid       = "KMSListAliases"
    effect    = "Allow"
    actions   = ["kms:ListAliases"]
    resources = ["*"]
  }

  # ── KMS: Manage tagged keys ─────────────────────────────────────────────────
  statement {
    sid    = "KMSManageTaggedKeys"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateKeyDescription",
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "kms:Encrypt",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["bootstrap"]
    }
  }

  # ── STS & SSM ───────────────────────────────────────────────────────────────
  statement {
    sid       = "STSGetCallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid    = "SSMParameterAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ssm:*:${local.account_id}:parameter/${var.environment}/bootstrap/*",
    ]
  }

  statement {
    sid       = "SSMDescribeParameters"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# POLICY 2: IAM & CloudTrail
# ══════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "terraform_iam" {

  # ── IAM: List operations ────────────────────────────────────────────────────
  statement {
    sid    = "IAMListOperations"
    effect = "Allow"
    actions = [
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  # ── IAM: OIDC provider ──────────────────────────────────────────────────────
  statement {
    sid    = "IAMOIDCProviderManagement"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  # ── IAM: Bootstrap role management ──────────────────────────────────────────
  statement {
    sid    = "IAMRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/github-actions-terraform-${var.environment}",
    ]
  }

  # ── IAM: Policy management ──────────────────────────────────────────────────
  statement {
    sid    = "IAMPolicyManagement"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:policy/TerraformDeployment-*-${var.environment}",
    ]
  }

  # ── IAM: PassRole for bootstrap ─────────────────────────────────────────────
  statement {
    sid       = "IAMPassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/github-actions-terraform-${var.environment}"]
  }

  # ── CloudTrail ──────────────────────────────────────────────────────────────
  statement {
    sid    = "CloudTrailListOperations"
    effect = "Allow"
    actions = [
      "cloudtrail:DescribeTrails",
      "cloudtrail:ListTrails",
      "cloudtrail:LookupEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudTrailManagement"
    effect = "Allow"
    actions = [
      "cloudtrail:CreateTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:GetTrail",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:PutInsightSelectors",
      "cloudtrail:GetInsightSelectors",
      "cloudtrail:AddTags",
      "cloudtrail:RemoveTags",
      "cloudtrail:ListTags",
    ]
    resources = [
      "arn:aws:cloudtrail:*:${local.account_id}:trail/centralized-audit-trail-${var.environment}",
    ]
  }
}

# ================================================
# IAM Policy Resources
# ================================================

resource "aws_iam_policy" "terraform_core" {
  name        = "TerraformDeployment-Core-${var.environment}"
  description = "Core infrastructure policy (S3, KMS, SSM) for ${var.environment}"
  policy      = data.aws_iam_policy_document.terraform_core.json

  tags = merge(var.tags, {
    Name = "TerraformDeployment-Core-${var.environment}"
  })
}

resource "aws_iam_policy" "terraform_iam" {
  name        = "TerraformDeployment-IAM-${var.environment}"
  description = "IAM and CloudTrail policy for ${var.environment}"
  policy      = data.aws_iam_policy_document.terraform_iam.json

  tags = merge(var.tags, {
    Name = "TerraformDeployment-IAM-${var.environment}"
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# POLICY 3: VPC & Networking
# ══════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "terraform_vpc" {

  # ── VPC: Core VPC management ─────────────────────────────────────────────────
  statement {
    sid    = "VPCManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  # ── VPC: Subnets ─────────────────────────────────────────────────────────────
  statement {
    sid    = "SubnetManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:DescribeSubnets",
      "ec2:ModifySubnetAttribute",
    ]
    resources = ["*"]
  }

  # ── VPC: Internet Gateway ────────────────────────────────────────────────────
  statement {
    sid    = "InternetGatewayManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:DescribeInternetGateways",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
    ]
    resources = ["*"]
  }

  # ── VPC: NAT Gateway ─────────────────────────────────────────────────────────
  statement {
    sid    = "NATGatewayManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:DescribeNatGateways",
    ]
    resources = ["*"]
  }

  # ── VPC: Elastic IPs ─────────────────────────────────────────────────────────
  statement {
    sid    = "ElasticIPManagement"
    effect = "Allow"
    actions = [
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:DescribeAddresses",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
    ]
    resources = ["*"]
  }

  # ── VPC: Route Tables ────────────────────────────────────────────────────────
  statement {
    sid    = "RouteTableManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:DescribeRouteTables",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
    ]
    resources = ["*"]
  }

  # ── VPC: Security Groups ─────────────────────────────────────────────────────
  statement {
    sid    = "SecurityGroupManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
    ]
    resources = ["*"]
  }

  # ── VPC: VPC Endpoints ───────────────────────────────────────────────────────
  statement {
    sid    = "VPCEndpointManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcEndpointServices",
      "ec2:ModifyVpcEndpoint",
      "ec2:DescribePrefixLists",
    ]
    resources = ["*"]
  }

  # ── VPC: Flow Logs ───────────────────────────────────────────────────────────
  statement {
    sid    = "FlowLogsManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateFlowLogs",
      "ec2:DeleteFlowLogs",
      "ec2:DescribeFlowLogs",
    ]
    resources = ["*"]
  }

  # ── VPC: Network ACLs ────────────────────────────────────────────────────────
  statement {
    sid    = "NetworkACLManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkAcl",
      "ec2:DeleteNetworkAcl",
      "ec2:DescribeNetworkAcls",
      "ec2:CreateNetworkAclEntry",
      "ec2:DeleteNetworkAclEntry",
      "ec2:ReplaceNetworkAclEntry",
      "ec2:ReplaceNetworkAclAssociation",
    ]
    resources = ["*"]
  }

  # ── VPC: Availability Zones ──────────────────────────────────────────────────
  statement {
    sid    = "AvailabilityZonesDescribe"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }

  # ── RDS: Subnet Groups ───────────────────────────────────────────────────────
  statement {
    sid    = "RDSSubnetGroupManagement"
    effect = "Allow"
    actions = [
      "rds:CreateDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:DescribeDBSubnetGroups",
      "rds:ModifyDBSubnetGroup",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
      "rds:ListTagsForResource",
    ]
    resources = [
      "arn:aws:rds:*:${local.account_id}:subgrp:*-${var.environment}-*",
      "arn:aws:rds:*:${local.account_id}:subgrp:*-${var.environment}",
    ]
  }

  # ── RDS: Describe operations ─────────────────────────────────────────────────
  statement {
    sid    = "RDSDescribeOperations"
    effect = "Allow"
    actions = [
      "rds:DescribeDBSubnetGroups",
    ]
    resources = ["*"]
  }

  # ── IAM: VPC Flow Logs role ──────────────────────────────────────────────────
  statement {
    sid    = "IAMFlowLogsRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/*-${var.environment}-flow-logs-role",
    ]
  }

  # ── IAM: PassRole for VPC Flow Logs ──────────────────────────────────────────
  statement {
    sid     = "IAMPassRoleToFlowLogs"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/*-${var.environment}-flow-logs-role",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["vpc-flow-logs.amazonaws.com"]
    }
  }

  # ── CloudWatch Logs: VPC Flow Logs ───────────────────────────────────────────
  statement {
    sid    = "CloudWatchLogsVPCFlowLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:DescribeLogGroups",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
      "logs:ListTagsLogGroup",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:logs:*:${local.account_id}:log-group:/aws/vpc/*",
      "arn:aws:logs:*:${local.account_id}:log-group:/aws/vpc/*:*",
    ]
  }
}

resource "aws_iam_policy" "terraform_vpc" {
  name        = "TerraformDeployment-VPC-${var.environment}"
  description = "VPC and Networking policy for ${var.environment}"
  policy      = data.aws_iam_policy_document.terraform_vpc.json

  tags = merge(var.tags, {
    Name = "TerraformDeployment-VPC-${var.environment}"
  })
}
