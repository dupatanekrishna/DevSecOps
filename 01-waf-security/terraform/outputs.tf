output "cloudfront_domain_name" {
  description = "CloudFront hostname for testing"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "s3_bucket_name" {
  description = "Private S3 origin bucket"
  value       = aws_s3_bucket.site.bucket
}

output "waf_web_acl_name" {
  description = "AWS WAF Web ACL name"
  value       = aws_wafv2_web_acl.main.name
}

output "waf_log_group" {
  description = "CloudWatch Log Group used by AWS WAF"
  value       = aws_cloudwatch_log_group.waf.name
}

output "sns_topic_arn" {
  description = "SNS topic used by WAF alarms"
  value       = aws_sns_topic.waf_alerts.arn
}
