# Lab 02 - Policy as Code with OPA and Conftest

## Objective

Use **Open Policy Agent (OPA)** and **Conftest** to stop an insecure Terraform change **before deployment**.

The experiment intentionally creates a Terraform plan containing:

~~~text
SSH / TCP 22
source = 0.0.0.0/0
~~~

Terraform accepts the configuration syntactically, but the organization security policy rejects it.

The key lesson is:

> Terraform answers whether infrastructure can be planned. Policy as Code answers whether the organization should allow that infrastructure.

---

## Architecture / Control Flow

~~~text
Developer changes Terraform
          |
          v
     terraform fmt
          |
          v
    terraform validate
          |
          v
     terraform plan
          |
          v
terraform show -json
          |
          v
      tfplan.json
          |
          v
   OPA / Conftest
      /       \
     /         \
  PASS         FAIL
   |             |
   v             X
Eligible       Stop
for next       pipeline
stage
~~~

There is **no terraform apply** in this lab. The purpose is to demonstrate pre-deployment enforcement.

---

## Tools

### OPA

**Open Policy Agent (OPA)** is an open-source, general-purpose policy engine.

OPA evaluates structured input against policy rules and returns decisions.

OPA can be used with:
- Terraform
- Kubernetes
- APIs
- microservices
- CI/CD
- admission control
- authorization systems
- configuration validation

### Rego

**Rego** is OPA's policy language.

In this lab, the policy is written in:

~~~text
policy/terraform.rego
~~~

### Conftest

**Conftest** is an open-source CLI that uses OPA/Rego to test configuration files.

It is convenient for CI/CD because policy violations cause a non-zero exit code.

Mental model:

~~~text
OPA
= policy engine

Rego
= policy language

Conftest
= CLI for testing configuration with OPA/Rego
~~~

---

## Repository Layout

~~~text
02-policy-as-code/
├── README.md
├── policy/
│   └── terraform.rego
└── terraform/
    ├── main.tf
    └── main-secure.tf.example
~~~

Generated files such as these are intentionally not committed:

~~~text
.terraform/
tfplan
tfplan.json
*.tfstate
~~~

---

## Step 1 - Deliberately Insecure Terraform

The lab contains:

~~~hcl
resource "aws_security_group" "bad_ssh" {
  name        = "opa-policy-lab"
  description = "OPA Policy as Code lab"

  ingress {
    description = "Deliberately insecure SSH rule"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
}
~~~

This configuration exposes SSH to every IPv4 address.

It is intentionally insecure and should **not** be applied.

---

## Step 2 - Terraform Validation and Plan

From the Terraform directory:

~~~bash
cd terraform

terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
~~~

Terraform can successfully create a plan because the configuration is valid Terraform and valid AWS configuration.

Now convert the binary plan to JSON:

~~~bash
terraform show -json tfplan > tfplan.json
~~~

Why JSON?

~~~text
Terraform HCL
    ↓
terraform plan
    ↓
binary tfplan
    ↓
terraform show -json
    ↓
structured JSON
    ↓
OPA can inspect it
~~~

---

## Step 3 - OPA Policy

The Rego policy:

~~~rego
package main

deny contains msg if {
    some resource in input.resource_changes

    resource.type == "aws_security_group"

    some ingress in resource.change.after.ingress

    ingress.from_port == 22
    ingress.to_port == 22

    "0.0.0.0/0" in ingress.cidr_blocks

    msg := sprintf(
        "Security violation: %s exposes SSH port 22 to 0.0.0.0/0",
        [resource.address]
    )
}
~~~

Read it like English:

~~~text
For every Terraform resource change
          ↓
Is it an aws_security_group?
          ↓
Inspect its ingress rules
          ↓
Does it expose port 22?
          ↓
Does cidr_blocks contain 0.0.0.0/0?
          ↓
YES
          ↓
DENY
~~~

---

## Step 4 - Evaluate Directly with OPA

From the lab root:

~~~bash
opa eval \
  --data policy/terraform.rego \
  --input terraform/tfplan.json \
  'data.main.deny'
~~~

Observed during the hands-on lab:

~~~text
Security violation: aws_security_group.bad_ssh exposes SSH port 22 to 0.0.0.0/0
~~~

This proves OPA inspected the **planned infrastructure**, not merely the HCL source.

---

## Step 5 - Turn the Policy into a CI/CD Gate with Conftest

Run:

~~~bash
conftest test terraform/tfplan.json \
  --policy policy/
~~~

Observed result:

~~~text
FAIL - terraform/tfplan.json - main - Security violation:
aws_security_group.bad_ssh exposes SSH port 22 to 0.0.0.0/0

1 test, 0 passed, 0 warnings, 1 failure, 0 exceptions
~~~

Check the shell exit code:

~~~bash
echo $?
~~~

Observed:

~~~text
1
~~~

That exit code is the important CI/CD behavior.

~~~text
Conftest finds violation
          ↓
exit code = 1
          ↓
CI/CD job fails
          ↓
deployment does not continue
~~~

This is what turns a policy from documentation into an enforceable security control.

---

## Step 6 - PASS Scenario

A secure comparison is included as:

~~~text
terraform/main-secure.tf.example
~~~

The relevant change is:

~~~hcl
cidr_blocks = [
  "10.0.0.0/8"
]
~~~

For a real environment, use the actual approved corporate/VPN or administrative CIDR rather than treating all of `10.0.0.0/8` as universally trusted.

To test the PASS case, change the insecure CIDR in `main.tf`, regenerate the plan and JSON, then rerun Conftest:

~~~bash
cd terraform

terraform fmt
terraform validate
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json

cd ..

conftest test terraform/tfplan.json \
  --policy policy/

echo $?
~~~

The expected security result is:

~~~text
PASS
exit code = 0
~~~

The original FAIL result was verified hands-on. The PASS case should be verified after changing the local test configuration.

---

## Why terraform validate Is Not a Security Control

~~~text
terraform validate
        ↓
Is the Terraform configuration structurally valid?
~~~

It does **not** mean:

~~~text
Is this infrastructure compliant with company security policy?
~~~

That second question is where Policy as Code belongs.

Example:

~~~text
Security group:
TCP 22 from 0.0.0.0/0
~~~

Terraform:

~~~text
Valid configuration ✅
~~~

Organization policy:

~~~text
Not allowed ❌
~~~

---

## OPA vs Conftest

### OPA

Use OPA when you need the policy engine itself or want to integrate policy decisions into another application/platform.

Example:

~~~bash
opa eval ...
~~~

It evaluates Rego and returns policy decisions.

### Conftest

Use Conftest when you want a simple developer/CI interface for validating configuration.

Example:

~~~bash
conftest test tfplan.json --policy policy/
~~~

Its non-zero exit code integrates naturally with CI/CD systems.

---

## Policy as Code vs IaC Security Scanner

OPA and an IaC scanner solve related but different problems.

### Checkov-style security scanning

Typical question:

~~~text
Does this infrastructure violate known cloud/IaC security best practices?
~~~

Examples:
- public SSH
- unencrypted storage
- public S3
- missing logging
- insecure Kubernetes configuration

### OPA Policy as Code

Typical question:

~~~text
Does this change violate OUR organization's rules?
~~~

Examples:
- only approved AWS regions
- mandatory CostCenter tag
- only approved EC2 families
- production resources must use specific encryption
- no public administrative ports
- approved network ranges only
- mandatory backup settings

These tools complement each other.

~~~text
Terraform
   ↓
IaC scanner
   ↓
OPA / organization policy
   ↓
security gate
   ↓
deployment
~~~

---

## Other Policy Tools to Know

### OPA Gatekeeper

Kubernetes-focused admission-control project built around OPA.

Typical flow:

~~~text
kubectl / deployment
        ↓
Kubernetes API
        ↓
Admission
        ↓
Gatekeeper policy
        ↓
allow / deny
~~~

### Kyverno

A Kubernetes-native policy engine. Policies are YAML-oriented and can validate, mutate, generate and verify Kubernetes resources.

### HashiCorp Sentinel

HashiCorp's Policy as Code system, commonly used with HCP Terraform / Terraform Enterprise.

Conceptually:

~~~text
Terraform plan
     ↓
Sentinel policy
     ↓
pass / fail
~~~

The important engineering concept is broader than the specific product:

> Security policy should be version-controlled, reviewable, testable and automatically enforced before deployment.

---

## Example CI/CD Stage

A generic CI/CD security stage could look like:

~~~bash
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
conftest test tfplan.json --policy ../policy/
~~~

If Conftest returns exit code 1, the job fails and later deployment stages should not run.

Conceptually:

~~~text
Git push
   ↓
terraform fmt
   ↓
terraform validate
   ↓
terraform plan
   ↓
plan → JSON
   ↓
Conftest / OPA
   ↓
PASS ─────────────→ deployment stage
FAIL ─────────────→ pipeline stopped
~~~

---

## Troubleshooting Notes

### Conftest says PASS unexpectedly

Verify that you regenerated the Terraform plan after modifying the HCL:

~~~bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
~~~

Testing an old `tfplan.json` means you are evaluating stale infrastructure.

### OPA returns an empty deny result

Check:
- resource type in `resource_changes`
- shape of `resource.change.after`
- exact ingress representation in Terraform plan JSON
- port numbers
- CIDR value
- Rego package and query path

Useful inspection:

~~~bash
jq '.resource_changes' terraform/tfplan.json
~~~

### Conftest exits with 1

In this lab, that is intentional when the security policy detects the insecure rule.

~~~text
exit 0 = policy passed
exit 1 = policy failure
~~~

### Do I need terraform apply?

No.

The entire objective is to catch the violation **before apply**.

---

## Knowledge Check

### What is Policy as Code?

Policy as Code means expressing security/governance requirements as machine-readable policy that can be version-controlled, tested and automatically enforced.

### Why use OPA with Terraform?

Terraform defines the desired infrastructure. OPA can inspect the Terraform plan and decide whether that proposed infrastructure complies with organizational policy before deployment.

### Why inspect the Terraform plan instead of only HCL?

The plan represents Terraform's resolved proposal, including values and resource changes. It gives the policy engine a structured view of what Terraform intends to create/change/delete.

### What role does Conftest play?

Conftest provides a convenient CLI around OPA/Rego for configuration testing and returns CI-friendly exit codes.

### What happened in this lab?

Terraform accepted an AWS security group exposing TCP 22 to `0.0.0.0/0`. OPA detected the violation. Conftest returned a failure and exit code 1, demonstrating how a pipeline could block the change before deployment.

### What happens when policy fails in CI/CD?

The policy-check job returns a non-zero status. The pipeline should stop and prevent the apply/deployment stage from executing.

### Is OPA only for Terraform?

No. OPA is general purpose. It can be used with Kubernetes, APIs, authorization, CI/CD and other systems that can provide structured input.

### OPA or Checkov?

They are complementary. Checkov is useful for broad built-in IaC security checks. OPA is especially useful for custom organizational policies and governance requirements.

### OPA or Sentinel?

Both implement Policy as Code. OPA/Rego is general-purpose and open source. Sentinel is HashiCorp's policy framework used in its ecosystem.

### What is the production workflow you would use?

~~~text
Pull request
   ↓
format + validate
   ↓
security scanning
   ↓
terraform plan
   ↓
OPA/Conftest organizational policies
   ↓
review/approval
   ↓
apply from approved plan
~~~

---

## Security Note

This lab intentionally contains an insecure Terraform example for testing.

Do not run:

~~~bash
terraform apply
~~~

against the insecure example.

Generated plan/state artifacts should remain local and must not be committed.

---

## AWS SCP vs OPA / Conftest

AWS Organizations **Service Control Policies (SCPs)** can also block deployments, but they operate at a different layer from OPA/Conftest.

### Control flow

~~~text
Developer writes Terraform
        ↓
OPA / Conftest in CI
        ↓
Shift-left policy check
        ↓
terraform apply
        ↓
AWS IAM permissions
        ↓
AWS Organizations SCP
        ↓
AWS API accepts or denies the action
~~~

### Key difference

**OPA / Conftest**

~~~text
Pre-deployment
CI/CD
Developer feedback
Shift-left
Custom organization policy
~~~

**AWS SCP**

~~~text
AWS Organizations / account guardrail
Enforced when the AWS API action is attempted
Defines the maximum permissions available to accounts/OUs
Can deny an action even if IAM allows it
~~~

SCPs do not grant permissions by themselves. They limit what permissions can be effective.

Example:

~~~text
Policy:
Production EC2 must run only in approved regions

OPA / Conftest:
Terraform plan checked in CI
→ FAIL before apply

SCP:
terraform apply reaches AWS
→ AWS API denies the action
~~~

The strongest design is layered:

~~~text
Shift-left
OPA / Conftest / Checkov / Sentinel
        ↓
Cloud / account guardrails
SCP / IAM / Control Tower / Config
        ↓
Admission / runtime controls
Gatekeeper / Kyverno / WAF / monitoring
~~~

### Is SCP shift-left?

Not usually in the strict sense.

OPA/Conftest in CI is a clear **shift-left** control because the problem is detected before deployment reaches the cloud API.

SCP is a **preventive cloud governance guardrail**. It still prevents a bad deployment, but it does so later, at AWS API enforcement time.

### Example layered protection

~~~text
Rule:
Do not allow SSH from 0.0.0.0/0

Layer 1:
OPA / Conftest
→ catches it in pull request / pipeline

Layer 2:
IAM / SCP
→ prevents disallowed AWS API operations or configurations at account level

Layer 3:
Cloud monitoring / Config / Security Hub
→ detects drift or policy violations after deployment
~~~

---

## CNCF, OPA and Policy Standards

OPA is an open-source **CNCF Graduated** project.

Important distinction:

~~~text
CNCF / OPA provides:
- policy engine
- ecosystem
- reusable tooling

Your organization provides:
- actual governance rules
- approved regions
- required tags
- allowed CIDRs
- encryption requirements
- instance-type restrictions
- production policies
~~~

So there is **not one universal CNCF policy file** that every company uses.

The policy engine is standardized/reusable, but the rules are normally organization-specific.

### Mental model

~~~text
OPA
= policy engine

Rego
= policy language

Conftest
= CLI for testing configuration with OPA/Rego

Gatekeeper
= Kubernetes admission control using OPA concepts

Kyverno
= Kubernetes-native policy engine

SCP
= AWS Organizations account-level guardrail
~~~

### Engineering Explanation

A concise explanation:

> We use shift-left controls such as OPA/Conftest in CI to reject non-compliant Terraform before apply, and we also use AWS Organizations SCPs as account-level guardrails so prohibited actions are denied at the AWS API layer. OPA is a CNCF Graduated open-source policy engine, while the actual governance rules are usually defined by the organization.

---

## Shift-Left Security with GitOps, Terraform Controller and ArgoCD

Shift-left security still applies when deployment is performed by a controller instead of directly by CI.

The important separation is:

~~~text
CI / Pull Request
→ decide whether the change is allowed to enter Git

GitOps Controller
→ reconcile the approved Git state into the target platform
~~~

### Terraform Controller Flow

~~~text
Developer changes Terraform
        ↓
Pull Request
        ↓
terraform fmt / validate
        ↓
Checkov
        ↓
OPA / Conftest
        ↓
review / approval
        ↓
Merge
        ↓
Git desired state
        ↓
Terraform Controller
        ↓
plan / apply through controller
        ↓
AWS API
        ↓
IAM / SCP guardrails
~~~

The Terraform Controller does not replace shift-left checks. It replaces the direct deployment step and continuously reconciles approved desired state.

### ArgoCD Flow

~~~text
Developer changes Kubernetes YAML / Helm
        ↓
Pull Request
        ↓
lint / tests
        ↓
Trivy config scan
        ↓
OPA / Conftest
        ↓
review / approval
        ↓
Merge
        ↓
Git desired state
        ↓
ArgoCD
        ↓
Kubernetes API
        ↓
Gatekeeper / Kyverno / Pod Security
        ↓
allow / deny
~~~

### Multiple Enforcement Layers

A strong GitOps design uses more than one control point:

~~~text
Gate 1 - Shift left
PR / CI
→ tests, SAST, secrets, Checkov, OPA

Gate 2 - Git governance
→ code review, approvals, branch protection

Gate 3 - Deployment-time enforcement
→ Kubernetes admission policy
→ AWS IAM / SCP / cloud controls

Gate 4 - Runtime detection
→ WAF, monitoring, SIEM, alerts
~~~

This creates defense in depth.

### Key Distinction

~~~text
CI/CD security gate
→ Should this change enter Git?

ArgoCD / Terraform Controller
→ Make actual state match approved Git state.

Gatekeeper / Kyverno / SCP
→ Is this deployment allowed at the platform control plane?
~~~

### Engineering Explanation

> In a GitOps model, I keep security gates before merge. CI runs tests, IaC scanning, secret scanning and OPA/Conftest on the pull request. Only compliant changes are merged into the desired-state repository. ArgoCD or Terraform Controller then reconciles that approved state. I also keep deployment-time enforcement using Kubernetes admission policies such as Gatekeeper or Kyverno, and AWS guardrails such as IAM and SCP. GitOps does not remove shift-left; it adds a controlled reconciliation layer.
