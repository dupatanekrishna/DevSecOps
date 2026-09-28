resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "site" {
  bucket = "${var.project_name}-${random_id.suffix.hex}"

  tags = {
    Project = var.project_name
    Lab     = "01-waf-security"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  content_type = "text/html"

  content = <<EOF_HTML
<!DOCTYPE html>
<html>
<head>
  <title>DevSecOps WAF Lab</title>
</head>
<body>
  <h1>DevSecOps Security Lab</h1>
  <p>Request passed through CloudFront and AWS WAF successfully.</p>
</body>
</html>
EOF_HTML
}

resource "aws_s3_object" "docs" {
  bucket       = aws_s3_bucket.site.id
  key          = "docs.html"
  content_type = "text/html"

  content = <<EOF_HTML
<!DOCTYPE html>
<html>
<head>
  <title>Developer Documentation</title>
</head>
<body>
  <h1>Developer Documentation</h1>
  <p>This page simulates a legitimate application that accepts code snippets.</p>
</body>
</html>
EOF_HTML
}
