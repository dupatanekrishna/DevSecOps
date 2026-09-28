resource "aws_s3_bucket" "lab_data" {
  # Resource-scoped, documented exception.
  # For a real environment, this exception should follow the organization's
  # approval process and use-case requirements.
  #checkov:skip=CKV_AWS_21: Versioning intentionally disabled for ephemeral DEV/lab data

  bucket = "devsecops-checkov-security-lab-example"

  tags = {
    Environment = "dev"
    Purpose     = "Checkov security testing"
  }
}

resource "aws_s3_bucket_public_access_block" "lab_data" {
  bucket = aws_s3_bucket.lab_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
