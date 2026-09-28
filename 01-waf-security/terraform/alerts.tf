resource "aws_sns_topic" "waf_alerts" {
  provider = aws.use1

  name = "${var.project_name}-waf-alerts"

  tags = {
    Project = var.project_name
    Lab     = "01-waf-security"
  }
}

resource "aws_sns_topic_subscription" "email" {
  provider = aws.use1

  topic_arn = aws_sns_topic.waf_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "xss_blocks" {
  provider = aws.use1

  alarm_name        = "${var.project_name}-xss-blocks"
  alarm_description = "Alert when BlockXSSExceptDocs blocks requests"

  namespace   = "AWS/WAFV2"
  metric_name = "BlockedRequests"

  statistic          = "Sum"
  period             = 60
  evaluation_periods = 1

  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    WebACL = "${var.project_name}-web-acl"
    Rule   = "BlockXSSExceptDocs"
  }

  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.waf_alerts.arn]
  ok_actions    = [aws_sns_topic.waf_alerts.arn]

  tags = {
    Project = var.project_name
    Lab     = "01-waf-security"
  }
}
