# Lab 01 — Engineering Reasoning & Knowledge Check

This document captures the theory, troubleshooting logic, operational decisions, and scenario-based knowledge checks derived from the AWS WAF hands-on lab.

The purpose is to connect the implementation to engineering reasoning: understand why each control exists, how to validate it, how to investigate unexpected behavior, and how to tune security without creating unnecessary gaps.

## Core mental model

```text
Client
  ↓
CloudFront
  ↓
AWS WAF
  ↓
Allowed request
  ↓
Private S3 origin
```

AWS WAF is associated with CloudFront and evaluates viewer requests according to the configured Web ACL and rules.

For CloudFront-scoped WAF resources, the AWS provider operates through `us-east-1`.

## WAF vs Shield

**AWS WAF** focuses on Layer-7 HTTP/HTTPS request inspection and policy enforcement. It can evaluate URI paths, query parameters, headers, cookies, request bodies, HTTP methods, IP characteristics, labels, and other request metadata.

**AWS Shield** is AWS's DDoS protection service, focused primarily on volumetric/network and transport-layer attacks.

A WAF rate-based rule can help with Layer-7 request floods, but WAF should not be described as the primary AWS DDoS service.

## Managed rule groups

Managed rule groups are collections of security rules maintained by AWS.

Examples include:

- `AWSManagedRulesCommonRuleSet`
- `AWSManagedRulesKnownBadInputsRuleSet`
- `AWSManagedRulesSQLiRuleSet`
- `AWSManagedRulesAmazonIpReputationList`
- `AWSManagedRulesAnonymousIpList`

The lab observed the child rule:

```text
CrossSiteScripting_QUERYARGUMENTS
```

The rule detected an XSS-like query-argument payload.

Do not enable every managed rule group blindly. Select controls based on application exposure, test them, observe false positives, tune them, then enforce them.

## BLOCK, ALLOW, and COUNT

### BLOCK

```text
Rule matches
→ BLOCK
→ request terminates
→ origin is not reached
```

### ALLOW

```text
Rule matches
→ ALLOW
→ request terminates as allowed
```

ALLOW is a terminating action.

### COUNT

```text
Rule matches
→ COUNT
→ match is recorded
→ evaluation continues
```

COUNT is useful when introducing or tuning a rule because it allows observation before enforcement.

A safe rollout model is:

```text
New rule
→ COUNT
→ observe traffic
→ analyze false positives
→ tune narrowly
→ BLOCK
```

## False-positive tuning

The lab intentionally used a documentation endpoint containing code-like input:

```text
/docs.html?q=<script>example</script>
```

Rather than disabling an entire managed rule group, the lab demonstrated a narrower pattern:

1. Override only the relevant child rule to COUNT.
2. Preserve the managed-rule label.
3. Evaluate that label in a custom rule.
4. Allow only the explicitly approved context.
5. Block the same pattern elsewhere.

Result:

```text
/docs.html + XSS-looking argument → allowed
/ + same XSS-looking argument     → blocked
/admin                            → blocked
```

Key principle:

> Narrow the exception; do not remove the protection globally.

## Managed labels and rule priority

Managed rules can apply labels such as:

```text
awswaf:managed:aws:core-rule-set:CrossSiteScripting_QueryArguments
```

A later custom rule can consume that label and apply application-specific policy.

Example evaluation order:

```text
10  AWSManagedRulesCommonRuleSet
15  BlockXSSExceptDocs
20  BlockAdminPath
30  RateLimitPerIP
```

The managed rule must run before a custom label-match rule that depends on its label.

## Rate-based rules

The lab used source IP as the aggregation key with a configured request limit and evaluation window.

Rate-based rules should not be treated as exact atomic counters. AWS evaluates traffic continuously and enforcement can have a short delay.

## CloudFront OAC and private S3

The S3 origin is private. CloudFront uses Origin Access Control with signed origin requests.

```text
Internet ─X─> S3

Internet
   ↓
CloudFront
   ↓ signed request
Private S3
```

The bucket policy grants the CloudFront service access and restricts it to the expected distribution.

## A 403 does not automatically mean WAF

One of the most important findings in the lab was that an HTTP status code alone is not enough to identify the failing layer.

A request to a missing/private S3 path returned 403 even though WAF logged:

```text
action = ALLOW
terminatingRuleId = Default_Action
```

That evidence pointed to the origin rather than WAF.

Troubleshooting model:

```text
HTTP response
+ WAF logs
+ CloudFront/origin evidence
→ identify the layer that generated the response
```

Useful starting hypotheses:

- **403:** WAF block, authorization issue, origin access issue, or application denial.
- **503:** unavailable backend, unhealthy target, application/service-discovery issue.
- **504:** slow upstream, gateway timeout, dependency timeout.

Always validate with logs and metrics.

## WAF metrics vs logs

Metrics answer questions such as:

- How many requests were allowed or blocked?
- Is the rate increasing?
- Did a threshold cross?

Logs answer questions such as:

- Which request matched?
- Which IP and URI were involved?
- Which rule or child rule matched?
- Which request component triggered the detection?

Mental model:

```text
Metrics → how much?
Logs    → why / which request?
```

## CloudWatch Logs Insights

Useful operators include:

- `fields`
- `filter`
- `sort`
- `limit`
- `stats`

See [`queries.md`](./queries.md) for the exact queries used in the lab.

## CloudWatch alarms and SNS

Alert path:

```text
WAF block
→ BlockedRequests metric
→ CloudWatch alarm
→ SNS topic
→ confirmed subscriber
```

Email subscriptions remain `PendingConfirmation` until the recipient confirms ownership.

## Terraform engineering lessons

Recommended workflow:

```bash
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Saving a plan allows review of the exact proposal that will later be applied.

Generated Terraform state and plan files must not be committed.

### Provider alias

CloudFront-scoped WAF resources can use an aliased `us-east-1` provider:

```hcl
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}
```

### `terraform init` variants

- `terraform init` — initialize backend/providers/modules.
- `terraform init -upgrade` — allow newer compatible provider/module versions.
- `terraform init -reconfigure` — reconfigure backend metadata.

Changing only a provider alias does not normally require `-reconfigure`.

## Security lifecycle learned

```text
Detect
→ Observe
→ Understand
→ Tune
→ Validate
→ Enforce
→ Alert
```

Security engineering is not complete merely because a tool is enabled.

---

## What You Should Be Able to Explain After Completing This Lab

You should be able to:

- Explain where AWS WAF fits in a CloudFront architecture and what request data it can inspect.
- Distinguish AWS WAF from AWS Shield.
- Explain managed rule groups, child rules, and managed labels.
- Explain the behavioral difference between BLOCK, ALLOW, and COUNT.
- Describe why COUNT mode is useful during a controlled rollout.
- Troubleshoot and tune a WAF false positive without disabling broad protection.
- Explain why rule priority matters when a custom rule depends on a managed label.
- Explain how WAF rate-based rules aggregate traffic and why they are not exact request counters.
- Explain how CloudFront OAC protects a private S3 origin.
- Distinguish a WAF-generated 403 from an origin-generated 403 using evidence.
- Explain the difference between WAF metrics and WAF logs.
- Query WAF logs using CloudWatch Logs Insights.
- Explain how CloudWatch alarms and SNS turn detections into notifications.
- Explain why Terraform plan review and version-controlled security configuration improve operational safety.

---

# Knowledge Check

## 1. How would you deploy and manage AWS WAF safely?

Manage the Web ACL, managed rule groups, custom rules, rate-based rules, logging, metrics, and alarms through Infrastructure as Code. Introduce higher-risk changes in COUNT mode when appropriate, analyze real matches and false positives, tune narrowly, review changes through version control, then enforce and monitor.

## 2. How do you troubleshoot a WAF false positive?

Identify the exact request, managed or custom rule, matched field, child rule, labels, and terminating behavior in WAF logs. Reproduce the legitimate request, temporarily observe with COUNT where appropriate, and create the smallest possible exception instead of disabling broad protection.

## 3. What did the lab do for the XSS false positive?

The relevant managed XSS child rule was overridden to COUNT so its label was preserved. A custom rule used that label to block the pattern everywhere except the explicitly approved `/docs.html` context.

## 4. Why not exclude `/docs.html` from the entire Common Rule Set?

Because the requirement concerns one narrow behavior. Excluding the endpoint from the entire managed rule group would create a much larger security gap.

## 5. What is `terminatingRuleId`?

It identifies the rule or default action that made the final terminating decision for the request.

## 6. What happens when a rule uses COUNT?

The match is recorded and contributes to logs/metrics, but evaluation continues to later rules.

## 7. Why is rule priority important?

Rules are evaluated in priority order. A managed rule must run first if a later custom rule depends on the label that managed rule applies.

## 8. How would you safely introduce a new managed rule group?

Start in COUNT when risk warrants it, observe real traffic, investigate matches, identify false positives, add narrow exceptions, validate expected behavior, move appropriate rules to enforcement, then monitor metrics and alerts.

## 9. How do you distinguish a WAF 403 from an origin 403?

Correlate the response with WAF logs. If WAF shows ALLOW/Default_Action but the response is 403, investigate CloudFront and the origin. If WAF shows BLOCK and the expected terminating rule, WAF generated the denial.

## 10. What is the difference between CloudWatch logs and metrics?

Metrics are aggregated numerical time-series signals used for monitoring and alerting. Logs contain request-level detail used for investigation and root-cause analysis.

## 11. How would you detect repeated attack patterns?

Aggregate WAF logs and metrics by rule, source IP, URI, country, and time window. Use CloudWatch alarms/SNS for targeted notifications or forward security telemetry into a SIEM for broader correlation.

## 12. How does the SNS alert path work?

A WAF rule contributes to a metric such as `BlockedRequests`. A CloudWatch alarm evaluates the metric and publishes to SNS when the threshold is met. Confirmed subscribers receive the notification.

## 13. Why might an SNS email initially not arrive?

Email subscriptions require recipient confirmation. Until confirmed, the subscription remains `PendingConfirmation` and notifications are not delivered to that email endpoint.

## 14. What is the purpose of CloudFront OAC?

OAC lets CloudFront securely retrieve objects from a private S3 origin using signed requests, avoiding the need for a publicly readable bucket.

## 15. What is the value of managing WAF with Terraform?

It provides repeatability, peer-reviewable changes, version history, environment consistency, controlled rollout, and CI/CD integration for security policy.

## 16. Does `terraform validate` prove the infrastructure is secure?

No. It validates Terraform configuration structure and provider schema relationships. Security policy requires additional controls such as Checkov, OPA/Conftest, Sentinel, or organization-specific policy gates.
