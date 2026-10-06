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

### 03 - Terraform IaC Security Scanning with Checkov
Hands-on Terraform security scanning lab using Checkov to detect public SSH exposure, S3 security gaps, remediation, scoped exceptions, scanner-version troubleshooting, and CI/CD gate behavior.

Covered:
- Checkov built-in IaC policies
- Public SSH detection and remediation
- S3 Public Access Block
- S3 versioning exception handling
- PASS / FAIL / SKIP semantics
- Resource-level suppression vs global skip
- Soft-fail concepts
- Source and Terraform plan scanning
- Checkov vs OPA
- Scanner lifecycle/version troubleshooting

See: [03-terraform-iac-security](./03-terraform-iac-security/README.md)

### 04 - End-to-End CI/CD Security Gates
Hands-on pipeline lab combining unit tests, coverage, secret scanning, SAST, SonarQube, SCA, IaC security, custom Policy as Code, container scanning, DAST, and GitHub Actions enforcement.

Covered:
- pytest + coverage gates
- Python/runtime dependency compatibility troubleshooting
- Gitleaks secret scanning and why commented secrets still count
- Semgrep SAST and blocking exit-code behavior
- SonarQube centralized projects, coverage, Quality Gates and environment separation
- Trivy SCA and vulnerability severity vs remediation priority
- Docker image hardening, image-size basics, non-root execution and EXPOSE vs port mapping
- Checkov + OPA/Conftest in CI
- GitOps / ArgoCD / Terraform Controller shift-left model
- OWASP ZAP baseline/full DAST and DAST discovery limitations
- GitHub Actions end-to-end security pipeline

See: [04-cicd-security-gates](./04-cicd-security-gates/README.md)

## Planned Labs

- 05 - Kubernetes security: RBAC, NetworkPolicy, Pod Security and ingress
- 06 - IAM, IRSA, Secrets Manager and KMS
- 07 - Security observability and incident workflows

## What You Should Be Able to Explain After Completing These Labs

You should be able to:

- Explain how security controls move from design to enforcement through IaC and CI/CD.
- Distinguish preventive controls, detective controls, and operational validation.
- Explain how AWS WAF rules, managed protections, labels, metrics, logs, and alerting work together.
- Explain why narrowly scoped exceptions are safer than disabling broad protections.
- Describe how OPA/Conftest and Checkov enforce different kinds of infrastructure policy.
- Explain how SAST, SCA, secret scanning, IaC scanning, container scanning, DAST, and quality gates fit into a delivery pipeline.
- Reason about blocking versus advisory security gates and when each is appropriate.
- Troubleshoot scanner failures, false positives, dependency issues, and CI/CD enforcement behavior.
- Explain how GitOps and policy checks can shift security earlier in the delivery lifecycle.

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
