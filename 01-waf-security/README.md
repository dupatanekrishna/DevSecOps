> **Study material:** [Theory & Interview Q&A](./theory-and-qa.md) · [CloudWatch Logs Insights Queries](./queries.md)

# Lab 01 - AWS WAF Security, Tuning and Alerting

## Objective

Build and operate an AWS WAF-protected CloudFront application entirely through Terraform, then test the controls from a local machine and investigate the results with CloudWatch.

This lab demonstrates the full WAF lifecycle:

~~~text
Deploy
  ↓
Detect
  ↓
Observe
  ↓
Investigate
  ↓
COUNT
  ↓
Tune false positives
  ↓
Enforce
  ↓
Alert
~~~

## Architecture

~~~text
                           Internet / Mac
                                |
                               curl
                                |
                                v
                           CloudFront
                                |
                                v
                             AWS WAF
                 +--------------+--------------+
                 |              |              |
                 v              v              v
          AWS Managed CRS   Custom Rules   Rate-Based Rule
                 |              |              |
                 +--------------+--------------+
                                |
                       allowed requests
                                |
                                v
                         Private S3 Origin
                         via CloudFront OAC

AWS WAF
   |
   +--> CloudWatch Logs
   |       |
   |       +--> Logs Insights
   |
   +--> CloudWatch Metrics
           |
           +--> Alarm
                  |
                  v
                 SNS
                  |
                  v
                Email
~~~

## Terraform Layout

~~~text
01-waf-security/
├── README.md
├── queries.md
└── terraform/
    ├── providers.tf
    ├── variables.tf
    ├── main.tf
    ├── waf.tf
    ├── cloudfront.tf
    ├── alerts.tf
    ├── outputs.tf
    └── terraform.tfvars.example
~~~

## Controls Implemented

### 1. AWS Managed Common Rule Set

Terraform attaches:

~~~hcl
managed_rule_group_statement {
  name        = "AWSManagedRulesCommonRuleSet"
  vendor_name = "AWS"
}
~~~

The managed group contains many AWS-maintained child rules. During testing, an XSS-like query argument matched:

~~~text
CrossSiteScripting_QUERYARGUMENTS
~~~

Example request:

~~~text
/?q=<script>alert(1)</script>
~~~

Observed WAF fields included:

~~~text
terminatingRuleId = AWSManagedRulesCommonRuleSet
conditionType     = XSS
location          = ALL_QUERY_ARGS
matchedFieldName  = q
matchedData       = "<", "script"
~~~

### 2. Custom URI Blocking

A custom rule blocks requests whose URI starts with:

~~~text
/admin
~~~

Examples:

~~~text
/admin
/admin/users
/admin/settings
~~~

### 3. Rate Limiting

A rate-based rule groups requests by source IP:

~~~text
limit                 = 100
aggregate_key_type    = IP
evaluation_window_sec = 60
~~~

Important: AWS WAF rate-based rules are not exact counters. Enforcement can begin after the evaluation system determines an aggregation instance has exceeded the configured rate.

Observed fields:

~~~text
terminatingRuleId   = RateLimitPerIP
terminatingRuleType = RATE_BASED
limitKey            = IP
maxRateAllowed      = 100
evaluationWindowSec = 60
~~~

## COUNT Mode

BLOCK behavior:

~~~text
XSS detected
   ↓
managed child rule BLOCK
   ↓
request terminated
   ↓
403
~~~

COUNT behavior:

~~~text
XSS detected
   ↓
COUNT
   ↓
match recorded
   ↓
evaluation continues
   ↓
Default_Action
   ↓
ALLOW
~~~

COUNT is useful for safely observing a new security rule before production enforcement.

## False-Positive Tuning

A simulated documentation endpoint accepts code-like search content:

~~~text
/docs.html?q=<script>example</script>
~~~

For this lab, that request represents legitimate application traffic.

Instead of disabling the entire AWS managed Common Rule Set, only the specific child rule is overridden to COUNT:

~~~text
CrossSiteScripting_QUERYARGUMENTS
~~~

AWS still applies the managed WAF label:

~~~text
awswaf:managed:aws:core-rule-set:CrossSiteScripting_QueryArguments
~~~

A custom rule then reads that label and blocks XSS everywhere except the approved documentation path.

Result:

~~~text
/docs.html + XSS-like query  → ALLOW
/ + same XSS-like query      → BLOCK
/admin                       → BLOCK
~~~

Key principle:

> Narrow the exception; do not remove the protection globally.

## Rule Evaluation Order

~~~text
Priority 10
AWSManagedRulesCommonRuleSet
  |
  +-- CrossSiteScripting_QUERYARGUMENTS → COUNT + label

Priority 15
BlockXSSExceptDocs
  |
  +-- XSS label AND URI != /docs.html → BLOCK

Priority 20
BlockAdminPath
  |
  +-- URI starts with /admin → BLOCK

Priority 30
RateLimitPerIP
  |
  +-- source-IP rate threshold exceeded → BLOCK

Default Action
  |
  +-- ALLOW
~~~

## CloudFront and WAF Association

~~~hcl
web_acl_id = aws_wafv2_web_acl.main.arn
~~~

Viewer requests are evaluated by AWS WAF before allowed requests are forwarded to the origin.

## Private S3 Origin

The bucket is not public. CloudFront uses OAC with SigV4.

~~~text
Internet
   X
Private S3

CloudFront
   |
   | signed request
   v
Private S3
~~~

The bucket policy permits only the CloudFront service and restricts access to the specific CloudFront distribution ARN.

## WAF Logging

Full WAF request logs are sent to:

~~~text
aws-waf-logs-devsecops-waf-lab
~~~

The log group uses seven-day retention.

Important troubleshooting lesson:

> An HTTP 403 does not automatically mean WAF blocked the request.

A request to a nonexistent private S3 path returned an S3 AccessDenied response while the WAF log showed:

~~~text
action = ALLOW
terminatingRuleId = Default_Action
~~~

That proves the origin, not WAF, generated the 403.

## CloudWatch Alarm and SNS

The lab creates an alarm for the tuned XSS rule:

~~~text
Namespace = AWS/WAFV2
Metric    = BlockedRequests
WebACL    = devsecops-waf-lab-web-acl
Rule      = BlockXSSExceptDocs
Statistic = Sum
Threshold = >= 1
Period    = 60 seconds
~~~

Flow:

~~~text
WAF block
   ↓
BlockedRequests metric
   ↓
CloudWatch Alarm
   ↓
SNS
   ↓
Email
~~~

SNS email subscriptions require the recipient to confirm the AWS subscription email before notifications are delivered.

## Deploy

~~~bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
~~~

## Test

~~~bash
CF=$(terraform output -raw cloudfront_domain_name)

curl -i "https://$CF/"
curl -i "https://$CF/admin"
curl -i "https://$CF/?q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"
curl -i "https://$CF/docs.html?q=%3Cscript%3Eexample%3C%2Fscript%3E"
~~~

Rate test against your own lab:

~~~bash
seq 1 200 | xargs -I{} -P20 \
  curl -s -o /dev/null -w "%{http_code}\n" \
  "https://$CF/?rate-test={}"
~~~

## Verify Alarm

~~~bash
aws cloudwatch describe-alarms \
  --alarm-names devsecops-waf-lab-xss-blocks \
  --region us-east-1 \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table
~~~

## Cleanup

~~~bash
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
~~~

## Interview Revision

- WAF protects Layer-7 HTTP traffic; AWS Shield is the primary AWS DDoS protection service.
- AWS Managed Rule Groups contain many child rules maintained by AWS.
- COUNT records a match but allows evaluation to continue.
- BLOCK terminates the request.
- ALLOW is also terminating and should not be confused with COUNT.
- Use logs to identify the rule group, exact child rule, request field and matched data.
- Do not disable a complete managed rule group for one false positive.
- Prefer narrow exceptions based on endpoint, parameter, label or other application context.
- WAF metrics answer "how much"; WAF logs answer "why".
- CloudWatch Logs Insights is useful for investigation and traffic-pattern analysis.
- CloudWatch alarms and SNS convert detections into actionable notifications.
- Keep infrastructure and security policy changes version-controlled through Terraform.

## Security / Compliance

Before publishing:
- never commit terraform.tfstate
- never commit terraform.tfvars
- never commit AWS account IDs or real infrastructure identifiers
- never commit real client IP addresses
- never commit access keys, credentials or private keys
