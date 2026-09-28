# Lab 01 - Theory and Interview Q&A

This file captures the theory, troubleshooting logic, and interview-style questions learned while building the AWS WAF lab.

## Core Mental Model

~~~text
Client
  ↓
CloudFront
  ↓
AWS WAF
  ↓
Allowed request
  ↓
Private S3 origin
~~~

WAF is attached to CloudFront. It is not a separate application hop that CloudFront calls manually.

For this lab, AWS WAF is global/CloudFront-scoped and the WAF resources are managed through the AWS provider in us-east-1.

## WAF vs Shield

**AWS WAF**
- Layer-7 HTTP/HTTPS protection
- URI, headers, query parameters, cookies, body and other request components
- managed rules
- custom rules
- rate-based rules
- bot/application filtering use cases

**AWS Shield**
- DDoS protection
- primarily focused on volumetric/network and transport-layer attacks
- Shield Standard is automatically available for many AWS edge services

A rate-based WAF rule can help with Layer-7 request floods, but WAF should not be described as the primary AWS DDoS service.

## Managed Rule Groups

A managed rule group is a collection of rules maintained by AWS.

Example:

~~~text
AWSManagedRulesCommonRuleSet
~~~

This group contains many child rules.

During the lab, the relevant child rule was:

~~~text
CrossSiteScripting_QUERYARGUMENTS
~~~

The child rule inspected query arguments and detected an XSS-like payload.

Important managed categories to know:
- AWSManagedRulesCommonRuleSet
- AWSManagedRulesKnownBadInputsRuleSet
- AWSManagedRulesSQLiRuleSet
- AWSManagedRulesAmazonIpReputationList
- AWSManagedRulesAnonymousIpList
- application/OS-specific managed groups
- Bot Control and fraud-related managed protections

Do not enable every managed group blindly. Select rules based on application exposure, test them, observe false positives, tune, then enforce.

## What Does WAF Actually Inspect?

Depending on the rule, WAF can inspect:
- URI path
- query string / query arguments
- headers
- cookies
- request body
- HTTP method
- IP characteristics
- managed labels
- other request metadata

Example:

~~~text
/search?q=terraform
~~~

Here:

~~~text
q
~~~

is the query-argument name.

In the XSS test, WAF decoded/normalized the request and identified XSS-like patterns in the query argument.

WAF does not execute JavaScript and does not "know the hacker." It evaluates request content using configured detection logic and signatures.

## BLOCK vs ALLOW vs COUNT

### BLOCK

~~~text
Rule matches
   ↓
BLOCK
   ↓
Request terminates
   ↓
Origin is not reached
~~~

### ALLOW

~~~text
Rule matches
   ↓
ALLOW
   ↓
Request terminates as allowed
~~~

ALLOW is also a terminating action.

### COUNT

~~~text
Rule matches
   ↓
COUNT
   ↓
Match is logged/metric recorded
   ↓
Evaluation continues
~~~

COUNT is particularly useful when introducing a new rule into production because it allows observation before enforcement.

## Why COUNT Mode Matters

A safe deployment lifecycle can be:

~~~text
New security rule
   ↓
COUNT
   ↓
Observe production traffic
   ↓
Analyze false positives
   ↓
Tune
   ↓
BLOCK
~~~

This reduces the chance of breaking legitimate application traffic.

## False Positive Tuning

The lab intentionally created a developer documentation use case:

~~~text
/docs.html?q=<script>example</script>
~~~

The request contains an XSS-looking value but is treated as legitimate for this simulated endpoint.

The wrong fix would be:

~~~text
Disable AWSManagedRulesCommonRuleSet
~~~

or:

~~~text
Disable XSS protection everywhere
~~~

The better approach demonstrated in the lab:

1. Override only the specific child rule to COUNT.
2. Preserve the managed-rule label.
3. Evaluate that label in a custom rule.
4. Allow only the explicitly approved context.
5. Continue blocking the same pattern everywhere else.

Final behavior:

~~~text
/docs.html + XSS-looking argument → allowed
/ + same XSS-looking argument     → blocked
/admin                            → blocked
~~~

## Managed Labels

Managed rules can apply labels when they match.

Example from this lab:

~~~text
awswaf:managed:aws:core-rule-set:CrossSiteScripting_QueryArguments
~~~

A later custom rule can match this label.

This enables a useful pattern:

~~~text
AWS managed detection
      ↓
Label
      ↓
Custom organization/application policy
      ↓
Context-aware enforcement
~~~

The managed detection logic is reused without globally accepting its default blocking behavior.

## Rule Priority

Lower priority numbers are evaluated first.

Lab order:

~~~text
10  AWSManagedRulesCommonRuleSet
15  BlockXSSExceptDocs
20  BlockAdminPath
30  RateLimitPerIP
~~~

Priority 15 must come after priority 10 because the managed rule needs to apply its XSS label before the custom label-match rule can consume it.

## Rate-Based Rules

Lab configuration:

~~~text
limit = 100
evaluation window = 60 seconds
aggregation key = source IP
~~~

The query parameter used during testing:

~~~text
?rate-test=158
~~~

was only test data. It was not the request count.

The aggregation was based on source IP.

Rate-based rules should not be explained as precise atomic request counters. AWS continuously evaluates traffic and can have a short enforcement delay.

## CloudFront OAC and Private S3

S3 public access is blocked.

CloudFront uses Origin Access Control and SigV4 to retrieve S3 objects.

~~~text
Internet ─X─> S3

Internet
   ↓
CloudFront
   ↓ signed origin request
Private S3
~~~

The S3 bucket policy grants s3:GetObject to:

~~~text
cloudfront.amazonaws.com
~~~

and restricts the request using the CloudFront distribution SourceArn.

## 403 Does Not Automatically Mean WAF

One of the most useful troubleshooting findings in this lab:

~~~text
HTTP 403
~~~

does not prove WAF blocked the request.

A request to a missing/private S3 path produced an S3 AccessDenied response.

Evidence:
- WAF log: action = ALLOW
- WAF terminatingRuleId = Default_Action
- HTTP header indicated AmazonS3 / CloudFront origin error

Troubleshooting principle:

~~~text
Do not diagnose from status code alone.
Correlate response + WAF logs + CloudFront/origin evidence.
~~~

Typical investigation:
1. Check WAF log for action and terminatingRuleId.
2. Check HTTP response headers/body.
3. Check CloudFront access data if enabled.
4. Check origin behavior/logs.
5. Trace the request layer by layer.

## 403 vs 503 vs 504

These are useful starting hypotheses, not absolute rules.

**403**
- WAF block
- authorization/authentication issue
- private-origin access problem
- application denial

**503**
- backend/service unavailable
- unhealthy targets
- application/service discovery problem

**504**
- upstream timeout
- long-running backend
- load balancer/gateway timeout
- dependency timeout

Always validate with logs and metrics rather than assuming from the status code.

## WAF Metrics vs Logs

**Metrics answer:**
- how many?
- is the count rising?
- did a threshold cross?

Examples:
- AllowedRequests
- BlockedRequests
- CountedRequests

**Logs answer:**
- which request?
- which IP?
- which URI?
- which rule matched?
- what request component matched?
- which managed child rule was involved?

Simple interview statement:

~~~text
Metrics tell me how much.
Logs tell me why.
~~~

## CloudWatch Logs Insights

Logs Insights is used to query and aggregate WAF JSON logs.

Useful operators:
- fields
- filter
- sort
- limit
- stats

See [queries.md](./queries.md) for the exact queries used in this lab.

## CloudWatch Alarm and SNS

Alert path:

~~~text
XSS request
   ↓
BlockXSSExceptDocs
   ↓
BlockedRequests metric
   ↓
CloudWatch alarm
   ↓
SNS topic
   ↓
Email subscription
~~~

The email subscription requires manual recipient confirmation.

Terraform can request the subscription, but the recipient must confirm ownership by clicking the AWS confirmation link.

Before confirmation:

~~~text
SubscriptionArn = PendingConfirmation
~~~

After confirmation, AWS returns a real subscription ARN.

## Terraform Lessons From This Lab

Recommended workflow:

~~~bash
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
~~~

Why save a plan?

~~~text
terraform plan -out=tfplan
        ↓
review exact proposal
        ↓
terraform apply tfplan
        ↓
apply exact reviewed plan
~~~

Running plain:

~~~bash
terraform apply
~~~

is fine for a lab, but Terraform calculates a new plan during apply.

Generated files such as state and saved plans must not be committed.

## Terraform Provider Alias Lesson

The lab used:
- default AWS provider for regional resources
- aliased us-east-1 provider for CloudFront-scoped WAF resources

Example:

~~~hcl
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}
~~~

Then:

~~~hcl
provider = aws.use1
~~~

is used on relevant resources.

## terraform init Variants

**terraform init**
- initialize providers/modules/backend

**terraform init -upgrade**
- allow newer provider/module versions within configured constraints

**terraform init -reconfigure**
- disregard existing backend configuration metadata and reconfigure the backend

Changing only a provider alias normally does not require `-reconfigure`.

## Security Lifecycle Learned

~~~text
Detect
  ↓
Observe
  ↓
Understand
  ↓
Tune
  ↓
Validate
  ↓
Enforce
  ↓
Alert
~~~

This is more realistic than simply enabling a security product and assuming the job is finished.

---

# Interview Q&A

## Q1. How would you deploy and manage AWS WAF?

I would manage the Web ACL, managed rule groups, custom rules, rate-based rules, logging, metrics and alarms through Infrastructure as Code. I would introduce high-risk rules in COUNT mode first, analyze logs and false positives, tune narrowly, then move to enforcement. Changes should be reviewed through version control and CI/CD.

## Q2. How do you troubleshoot a WAF false positive?

I identify the exact request, terminating rule or non-terminating matching rule, managed child rule, matched field and labels in WAF logs. I reproduce the legitimate request, put the problematic rule into COUNT if needed, then create the smallest possible exception. I avoid disabling the entire managed rule group.

## Q3. What did you do for the XSS false positive in this lab?

The AWS managed query-argument XSS child rule was overridden to COUNT. AWS still applied its managed XSS label. A custom rule then used that label to block the request everywhere except the explicitly approved /docs.html endpoint.

## Q4. Why not exclude /docs.html from the whole Common Rule Set?

That would create a much larger security gap. The requirement only involved one child XSS behavior, so the exception should remain limited to that detection and context.

## Q5. What is terminatingRuleId?

It identifies the rule that made the final terminating decision for the request.

For example:

~~~text
BlockXSSExceptDocs
BlockAdminPath
RateLimitPerIP
AWSManagedRulesCommonRuleSet
Default_Action
~~~

## Q6. What happens when a rule uses COUNT?

The match is recorded and metrics/log information is generated, but evaluation continues to later rules.

## Q7. Why is rule priority important?

Rules execute by priority. In the tuning example, the AWS managed rule must run first and apply a label. The custom rule then runs afterward and evaluates that label.

## Q8. How would you safely introduce a new managed rule group?

I would:
1. enable it in COUNT mode,
2. observe real traffic,
3. query matches,
4. identify false positives,
5. create narrow exclusions/overrides,
6. test,
7. switch appropriate rules to enforcement,
8. monitor metrics and alerts.

## Q9. How do you distinguish a WAF 403 from an origin 403?

I correlate the request with WAF logs. If WAF shows ALLOW/Default_Action but the HTTP response is 403, I investigate CloudFront and the origin. If WAF shows BLOCK and the appropriate terminating rule, WAF is responsible for the denial.

## Q10. What is the difference between CloudWatch logs and metrics?

Metrics are numerical time-series data used for monitoring and alerting. Logs contain request-level details used for investigation and root-cause analysis.

## Q11. How would you detect repeated attacks?

Use WAF metrics and Logs Insights to aggregate blocked requests by:
- rule
- IP
- URI
- country
- time window

Then use CloudWatch alarms/SNS or forward logs into a SIEM for broader correlation.

## Q12. How does the SNS alert work?

A WAF rule increments the BlockedRequests metric. A CloudWatch alarm evaluates that metric. When the threshold is crossed, the alarm publishes to an SNS topic. Confirmed subscribers receive the notification.

## Q13. Why did the SNS email initially not arrive?

The Terraform resource existed, but AWS showed the email subscription as PendingConfirmation. Email subscriptions require the recipient to confirm the AWS subscription message before delivery begins.

## Q14. What is the purpose of CloudFront OAC?

OAC lets CloudFront securely access a private S3 origin using signed requests. The S3 bucket does not need to be publicly readable.

## Q15. What is the value of managing WAF with Terraform?

It provides repeatability, reviewable changes, version history, consistent environments, rollback through code history, and the ability to integrate security configuration changes into CI/CD.

## Q16. Does terraform validate prove the infrastructure is secure?

No. It validates Terraform configuration syntax/schema relationships. Security policy requires additional controls such as Checkov, OPA/Conftest, Sentinel or other organization-specific policy gates.

That distinction leads directly into Lab 02: Policy as Code with OPA and Conftest.
