# DevSecOps Hands-On Security Lab

A practical, continuously updated DevSecOps repository focused on security controls that can be implemented, tested, observed, tuned, and automated.

The goal is not just to list tools. Each lab is designed to show the full engineering lifecycle:

~~~text
Design
  ↓
Infrastructure as Code
  ↓
Deploy
  ↓
Test
  ↓
Observe
  ↓
Break / simulate
  ↓
Investigate
  ↓
Tune
  ↓
Alert
  ↓
Document
~~~

## Labs

### 01 - AWS WAF Security, Tuning and Alerting
Hands-on AWS WAF lab using Terraform, CloudFront, private S3, CloudWatch Logs Insights, rate limiting, AWS Managed Rules, false-positive tuning, CloudWatch alarms and SNS.

Covered:
- AWS WAF Web ACL as code
- AWS Managed Rules Common Rule Set
- Custom URI blocking
- Rate-based rules
- WAF logging to CloudWatch
- Logs Insights investigation
- COUNT vs BLOCK behavior
- Managed-rule child-rule investigation
- False-positive tuning with labels
- Narrow exception handling
- CloudWatch metrics and alarms
- SNS email notifications
- Private S3 origin with CloudFront OAC

See: [01-waf-security](./01-waf-security/README.md)

### 02 - Policy as Code with OPA / Conftest
Hands-on Policy as Code lab that inspects Terraform plan JSON with Rego, proves an insecure SSH rule is denied, and demonstrates how Conftest returns a CI/CD-friendly non-zero exit code.

Covered:
- OPA and Rego basics
- Terraform plan JSON
- Custom organizational policy
- Public SSH detection
- Conftest security gate
- FAIL / exit-code behavior
- PASS workflow
- CI/CD integration concepts
- OPA vs Checkov vs Sentinel
- Gatekeeper and Kyverno overview

See: [02-policy-as-code](./02-policy-as-code/README.md)

## Planned Labs

- 03 - Terraform IaC security scanning
- 04 - CI/CD security gates: SAST, SCA, secrets and container scanning
- 05 - Kubernetes security: RBAC, NetworkPolicy, Pod Security and ingress
- 06 - IAM, IRSA, Secrets Manager and KMS
- 07 - Security observability and incident workflows

## Security Note

This repository contains lab examples only. Do not commit:
- AWS account IDs
- credentials or access keys
- Terraform state
- private keys
- real email addresses
- internal URLs
- production configuration
- client/company confidential information

All examples should be sanitized before being made public.
