# Lab 01 - Screenshot Evidence Checklist

Screenshots are useful portfolio evidence, but they must be sanitized before publishing.

Do not expose:
- AWS account ID
- personal email
- public client IP
- credentials/tokens
- internal/private company names
- production URLs
- request IDs if they are considered sensitive in your environment

## Recommended Screenshots

### 01 - Terraform Plan

Capture a plan showing the WAF/CloudFront/S3 resources and a successful review before apply.

Suggested filename:

~~~text
01-terraform-plan.png
~~~

### 02 - WAF Web ACL Rules

Capture the AWS WAF console showing the rule order:

~~~text
AWSManagedRulesCommonRuleSet
BlockXSSExceptDocs
BlockAdminPath
RateLimitPerIP
~~~

Suggested filename:

~~~text
02-waf-rule-priority.png
~~~

### 03 - Normal Request Allowed

Terminal or WAF sampled request showing:

~~~text
/
→ 200
~~~

Suggested filename:

~~~text
03-normal-request-allowed.png
~~~

### 04 - Admin Path Blocked

Evidence:

~~~text
/admin
→ 403
terminatingRuleId = BlockAdminPath
~~~

Suggested filename:

~~~text
04-admin-path-blocked.png
~~~

### 05 - Managed XSS Detection

CloudWatch log showing:
- AWSManagedRulesCommonRuleSet
- CrossSiteScripting_QUERYARGUMENTS
- XSS match
- query argument field
- managed label

Suggested filename:

~~~text
05-managed-xss-detection.png
~~~

### 06 - COUNT Mode

Capture the case where the managed XSS child rule detects the request but effective request action is ALLOW because the rule is in COUNT mode.

Useful evidence:
- nonTerminatingMatchingRules
- action = COUNT
- final action = ALLOW
- Default_Action

Suggested filename:

~~~text
06-count-mode-allow.png
~~~

### 07 - False Positive Tuning Comparison

Best screenshot for the portfolio.

Show two CloudWatch Logs Insights rows:

~~~text
/docs.html + XSS-like query
→ ALLOW

/ + same XSS-like query
→ BLOCK
→ BlockXSSExceptDocs
~~~

Both should show the same managed XSS label.

Suggested filename:

~~~text
07-xss-tuning-comparison.png
~~~

### 08 - Rate Limit Block

Capture a WAF log entry with:

~~~text
terminatingRuleId   = RateLimitPerIP
terminatingRuleType = RATE_BASED
limitKey            = IP
maxRateAllowed      = 100
evaluationWindowSec = 60
~~~

Redact the real IP.

Suggested filename:

~~~text
08-rate-limit-block.png
~~~

### 09 - Origin 403 vs WAF ALLOW

Useful troubleshooting evidence:

~~~text
HTTP response = 403 / S3 AccessDenied
WAF action    = ALLOW
terminatingRuleId = Default_Action
~~~

This demonstrates that a 403 is not automatically a WAF block.

Suggested filename:

~~~text
09-origin-403-not-waf.png
~~~

### 10 - CloudWatch Alarm in ALARM State

Capture:

~~~text
devsecops-waf-lab-xss-blocks
State = ALARM
Threshold crossed
~~~

Suggested filename:

~~~text
10-cloudwatch-alarm.png
~~~

### 11 - SNS Subscription

Capture confirmed SNS subscription status.

Do not expose the real email address in a public repository.

Suggested filename:

~~~text
11-sns-confirmed.png
~~~

## Suggested Repository Structure

~~~text
01-waf-security/
├── README.md
├── theory-and-qa.md
├── queries.md
├── screenshots/
│   ├── README.md
│   ├── 01-terraform-plan.png
│   ├── 02-waf-rule-priority.png
│   ├── ...
│   └── 11-sns-confirmed.png
└── terraform/
~~~

## README Embedding Example

After sanitized screenshots are added, embed them like this:

~~~markdown
### False-Positive Tuning Evidence

![XSS tuning comparison](./screenshots/07-xss-tuning-comparison.png)
~~~

The screenshots directory currently contains this checklist only. Add the actual sanitized screenshots from the completed lab when available.
