# Diese Datei enthaelt S3 + IAM fuer Avatar-Storage.
# Nur pruefen/anzeigen:
# tofu plan -var-file=dev.tfvars
# tofu state list

data "aws_caller_identity" "current" {}

locals {
  avatar_bucket_name = "${var.s3_bucket_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "avatars" {
  bucket        = local.avatar_bucket_name
  force_destroy = true

  tags = {
    Name        = local.avatar_bucket_name
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_public_access_block" "avatars" {
  bucket = aws_s3_bucket.avatars.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "avatars" {
  bucket = aws_s3_bucket.avatars.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "grocery-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_s3_policy_doc" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.avatars.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.avatars.arn}/${var.s3_avatar_prefix}/*"
    ]
  }
}

resource "aws_iam_policy" "ec2_s3_policy" {
  name   = "grocery-ec2-s3-policy"
  policy = data.aws_iam_policy_document.ec2_s3_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "grocery-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
