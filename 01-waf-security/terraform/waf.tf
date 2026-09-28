resource "aws_wafv2_web_acl" "main" {
  provider = aws.use1

  name  = "${var.project_name}-web-acl"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          name = "CrossSiteScripting_QUERYARGUMENTS"

          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "BlockXSSExceptDocs"
    priority = 15

    action {
      block {}
    }

    statement {
      and_statement {
        statement {
          label_match_statement {
            scope = "LABEL"
            key   = "awswaf:managed:aws:core-rule-set:CrossSiteScripting_QueryArguments"
          }
        }

        statement {
          not_statement {
            statement {
              byte_match_statement {
                search_string         = "/docs.html"
                positional_constraint = "EXACTLY"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockXSSExceptDocs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "BlockAdminPath"
    priority = 20

    action {
      block {}
    }

    statement {
      byte_match_statement {
        search_string         = "/admin"
        positional_constraint = "STARTS_WITH"

        field_to_match {
          uri_path {}
        }

        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockAdminPath"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 30

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = 100
        aggregate_key_type    = "IP"
        evaluation_window_sec = 60
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Project = var.project_name
    Lab     = "01-waf-security"
  }
}

resource "aws_cloudwatch_log_group" "waf" {
  provider = aws.use1

  name              = "aws-waf-logs-${var.project_name}"
  retention_in_days = 7

  tags = {
    Project = var.project_name
    Lab     = "01-waf-security"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  provider = aws.use1

  resource_arn = aws_wafv2_web_acl.main.arn

  log_destination_configs = [
    aws_cloudwatch_log_group.waf.arn
  ]
}
