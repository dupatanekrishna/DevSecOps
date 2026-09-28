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

For interviews, the important concept is broader than the specific product:

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

## Interview Q&A

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
