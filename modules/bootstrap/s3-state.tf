# ================================================
# S3 Bucket for Terraform State Storage
# ================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.tfstate_bucket_name

  tags = merge(var.tags, {
    Name                = local.tfstate_bucket_name
    resource-type       = "state-backend"
    test_github_actions = "test passed"
  })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ================================================
# KMS Key Policy for Terraform State Encryption
# ================================================
# Explicit policy to satisfy CKV2_AWS_64 - avoids default "*" principal.

data "aws_iam_policy_document" "terraform_state_kms_policy" {
  # Allow root account full access (required for key administration)
  statement {
    sid    = "AllowRootAccountFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow GitHub Actions role to use the key for state encryption/decryption
  statement {
    sid    = "AllowGitHubActionsRoleUsage"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.github_actions.arn]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }

  # Allow S3 service to use the key for server-side encryption
  statement {
    sid    = "AllowS3ServiceUsage"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3:::${local.tfstate_bucket_name}"]
    }
  }
}

# KMS CMK — key rotation enabled, 30-day deletion window.
# Project tag is required by the KMS IAM policy condition (aws:ResourceTag/Project).
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state bucket encryption - ${var.environment}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.terraform_state_kms_policy.json

  tags = merge(var.tags, {
    Name          = "terraform-state-kms-${var.environment}"
    resource-type = "kms-key"
    Project       = "bootstrap"
  })
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/tfstate-${var.company_name}-${var.environment}"
  target_key_id = aws_kms_key.terraform_state.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ================================================
# S3 Bucket Policy — deny non-TLS and TLS < 1.2
# ================================================

data "aws_iam_policy_document" "terraform_state_bucket_policy" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "EnforceTLS12OrHigher"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket     = aws_s3_bucket.terraform_state.id
  policy     = data.aws_iam_policy_document.terraform_state_bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

# ================================================
# Lifecycle Configuration
# ================================================

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ================================================
# Dedicated Access Log Bucket
#
# S3 server access logging to the same bucket causes log-entry recursion
# (AWS writes access log entries for the access-log writes themselves).
# This bucket is the sole target for state-bucket access logs.
# ================================================

resource "aws_s3_bucket" "access_logs" {
  bucket = local.access_logs_bucket_name

  tags = merge(var.tags, {
    Name          = local.access_logs_bucket_name
    resource-type = "access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Grant the S3 logging service write access using a bucket policy (modern,
# ACL-free approach). Scoped to the specific source bucket to prevent
# other buckets from writing logs here.
data "aws_iam_policy_document" "access_logs_bucket_policy" {
  statement {
    sid    = "AllowS3LogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.terraform_state.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket     = aws_s3_bucket.access_logs.id
  policy     = data.aws_iam_policy_document.access_logs_bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

resource "aws_s3_bucket_logging" "terraform_state" {
  bucket        = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "terraform-state/"
}
