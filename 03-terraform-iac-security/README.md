# Lab 03 - Terraform IaC Security Scanning with Checkov

## Objective

Use **Checkov** to scan Terraform before deployment, detect insecure cloud configuration, remediate real findings, and handle justified exceptions without globally disabling security controls.

This lab follows Lab 02 intentionally:

~~~text
Lab 02
Terraform → OPA/Rego → custom organizational policy

Lab 03
Terraform → Checkov → built-in security checks
~~~

The goal is to understand why both belong in a mature DevSecOps pipeline.

---

## What Was Verified Hands-On

### Security Group experiment

Initial configuration:

~~~hcl
cidr_blocks = [
  "0.0.0.0/0"
]
~~~

Checkov detected:

~~~text
CKV_AWS_24
Ensure no security groups allow ingress from 0.0.0.0/0 to port 22
~~~

Observed result:

~~~text
Passed checks: 6
Failed checks: 1
Exit code: 1
~~~

After remediation:

~~~hcl
cidr_blocks = [
  "10.0.0.0/8"
]
~~~

Observed result:

~~~text
Passed checks: 7
Failed checks: 0
Exit code: 0
~~~

This demonstrated:

~~~text
terraform validate = configuration is structurally valid
Checkov            = configuration is checked against security policies
~~~

A valid Terraform configuration is not automatically a secure Terraform configuration.

---

## S3 Experiment

A minimal S3 bucket was added to test multiple built-in policies.

Initial targeted scan checked:

~~~text
CKV_AWS_19  → encryption at rest
CKV_AWS_21  → versioning
CKV2_AWS_6  → Public Access Block
~~~

The initial result was:

~~~text
Encryption          PASS
Public Access Block FAIL
Versioning          FAIL
Exit code            1
~~~

The public-access finding was treated as a genuine security control and remediated.

Versioning was intentionally not enabled for the ephemeral DEV/lab use case, so a narrow resource-level exception was documented:

~~~hcl
#checkov:skip=CKV_AWS_21: Versioning intentionally disabled for ephemeral DEV/lab data
~~~

After remediation and the documented exception:

~~~text
CKV_AWS_19  PASS
CKV2_AWS_6  PASS
CKV_AWS_21  SKIPPED
Exit code   0
~~~

---

## Final Terraform Layout

~~~text
03-terraform-iac-security/
├── README.md
└── terraform/
    ├── main.tf
    └── s3.tf
~~~

No Terraform apply is required for this lab.

Generated Terraform files such as state, plan binaries and plan JSON are excluded from Git.

---

## Install Checkov

On macOS, an isolated installation is preferred when the system/Homebrew Python is externally managed.

Example using pipx:

~~~bash
brew install pipx
pipx ensurepath

export PIPX_HOME="$HOME/.local/pipx"
export PIPX_BIN_DIR="$HOME/.local/bin"

pipx install checkov
hash -r

which checkov
checkov --version
~~~

The hands-on lab ultimately used:

~~~text
Checkov 3.3.20
~~~

### Troubleshooting lesson

An older Homebrew installation was on Checkov 3.3.10. The desired Terraform S3 policy mappings were not appearing as expected in the policy listing.

After using Checkov 3.3.20, the Terraform policy catalog showed entries for:

~~~text
CKV_AWS_19
aws_s3_bucket
Terraform

CKV_AWS_21
aws_s3_bucket
Terraform

CKV2_AWS_6
aws_s3_bucket
Terraform
~~~

This produced an important operational lesson:

> A green scanner result does not prove every desired security policy was evaluated. Verify scanner version, policy availability and the checks that actually ran.

---

## Scan Terraform Source

Validate first:

~~~bash
terraform fmt
terraform validate
~~~

Scan one file:

~~~bash
checkov -f main.tf
~~~

Scan an entire Terraform directory:

~~~bash
checkov -d . --framework terraform
~~~

Check the process status:

~~~bash
echo $?
~~~

Typical CI meaning:

~~~text
0 → configured checks did not produce blocking failures
1 → one or more blocking policy checks failed
~~~

---

## Scan Selected Policies

To focus on specific controls:

~~~bash
checkov -f s3.tf \
  --check CKV_AWS_19,CKV_AWS_21,CKV2_AWS_6
~~~

This is useful for experiments and troubleshooting.

For a production pipeline, broad scanning is usually combined with a documented organizational baseline.

---

## Terraform Plan Scanning

Checkov can also inspect Terraform plan JSON.

~~~bash
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json

checkov -f tfplan.json
~~~

Mental model:

~~~text
Terraform source scan
        ↓
fast shift-left feedback

Terraform plan JSON
        ↓
resolved proposed infrastructure
        ↓
additional policy evaluation
~~~

A mature pipeline can use both.

---

## PASS, FAIL and SKIP

### PASS

The resource satisfies the policy.

~~~text
CKV2_AWS_6
Public Access Block
PASS
~~~

### FAIL

The resource violates a policy that should block the pipeline.

Example:

~~~text
CKV_AWS_24
SSH open to 0.0.0.0/0
FAIL
~~~

### SKIP

The finding is intentionally exempted for that specific resource with a documented reason.

Example:

~~~hcl
#checkov:skip=CKV_AWS_21: Versioning intentionally disabled for ephemeral DEV/lab data
~~~

The important distinction:

~~~text
FAIL
→ remediate real risk

SKIP
→ accepted exception with justification
→ narrow scope
→ reviewable in code
~~~

Do not turn a genuine security issue into a suppression merely to make the pipeline green.

---

## Resource-Level Suppression vs Global Skip

### Resource-level suppression

Preferred when one resource has an approved exception:

~~~hcl
#checkov:skip=CKV_AWS_21: Approved DEV/lab exception
~~~

Advantages:
- exception stays beside the resource
- reason is visible in code review
- does not weaken unrelated resources

### Global skip

Example:

~~~bash
checkov -d . --skip-check CKV_AWS_21
~~~

This disables that check for the entire scan scope.

That can unintentionally affect DEV, PROD, backup and customer-data buckets, so broad skipping should be used cautiously.

---

## Soft Fail

Sometimes an organization wants a finding to remain visible without blocking the pipeline immediately.

Conceptually:

~~~text
Hard fail
→ report + stop pipeline

Soft fail
→ report + continue pipeline

Skip
→ approved exception; check is suppressed for defined scope
~~~

Soft fail is useful during rollout or remediation windows, but it should not become a permanent workaround for serious findings.

---

## Full Directory Scan - Important Finding

After the targeted experiment passed/skipped as intended, a complete scan was also executed:

~~~bash
checkov -d . --framework terraform
~~~

The broader scan reported:

~~~text
Passed checks: 16
Failed checks: 6
Skipped checks: 1
Exit code: 1
~~~

This was deliberately documented rather than hidden.

Additional findings included:

~~~text
CKV2_AWS_5
Security group is not attached to another resource

CKV2_AWS_62
S3 event notifications not configured

CKV2_AWS_61
S3 lifecycle configuration not configured

CKV_AWS_18
S3 access logging not configured

CKV_AWS_145
S3 not encrypted with a customer-managed KMS key

CKV_AWS_144
S3 cross-region replication not configured
~~~

These findings teach an important point:

> A scanner policy catalog is broader than the requirements of any single workload.

For example, this lab intentionally does not deploy an EC2 instance, so the security group is unattached. Cross-region replication, customer-managed KMS, event notifications and access logging may be mandatory in some production baselines but not in every ephemeral lab or DEV workload.

The correct DevSecOps response is not to blindly fix or suppress everything.

Use:

~~~text
Finding
   ↓
Understand the workload and policy requirement
   ↓
Is this mandatory for this environment?
   |
   +-- YES → remediate
   |
   +-- NO → approved, narrow exception / baseline adjustment
   |
   +-- TEMPORARY → track and possibly soft-fail
~~~

---

## Checkov vs OPA

### Checkov

Best suited to broad built-in IaC security checks.

Typical question:

~~~text
Does this infrastructure violate a known cloud/IaC security best practice?
~~~

Examples:
- public SSH
- public S3
- missing encryption
- missing logging
- insecure security groups
- hard-coded credentials

### OPA / Rego

Best suited to custom organizational governance.

Typical question:

~~~text
Does this proposed infrastructure violate OUR rules?
~~~

Examples:
- PROD must have versioning
- DEV may omit versioning
- only approved AWS regions
- mandatory CostCenter tag
- only approved instance families
- corporate CIDRs only
- production encryption must use a specific key strategy

The tools complement each other:

~~~text
Terraform
   ↓
terraform validate
   ↓
Checkov
built-in security baseline
   ↓
OPA / Conftest
organization-specific policy
   ↓
approval
   ↓
terraform apply
~~~

---

## CI/CD Security Gate

A realistic pipeline sequence:

~~~text
Git push / Pull Request
        ↓
terraform fmt -check
        ↓
terraform validate
        ↓
Checkov source scan
        ↓
terraform plan
        ↓
Checkov plan scan
        ↓
OPA / Conftest
        ↓
manual/automated approval
        ↓
terraform apply approved plan
~~~

Any hard-fail security stage returns a non-zero exit code and prevents the deployment stage from running.

---

## Interview Q&A

### What is Checkov?

Checkov is an IaC security scanner that evaluates infrastructure definitions against a large catalog of security and compliance checks.

### Why use Checkov if Terraform already validates the code?

Terraform validation confirms the configuration is structurally valid. It does not determine whether the proposed infrastructure meets security best practices.

### What did Checkov detect in this lab?

It detected SSH open to the internet, missing S3 Public Access Block, missing versioning and several additional controls during a broad directory scan.

### How did you handle the SSH finding?

The CIDR was changed from `0.0.0.0/0` to a restricted private/trusted range. The policy then passed.

### How did you handle S3 Public Access Block?

It was treated as a genuine security control and remediated by adding `aws_s3_bucket_public_access_block` with all four protections enabled.

### Why was S3 versioning skipped?

The lab modeled an ephemeral DEV bucket where versioning was intentionally not required. A resource-level Checkov suppression was added with a documented justification.

### Would you do the same in production?

Only if the organization's production policy explicitly permits the exception and it follows the appropriate review/approval process. Otherwise the finding should be remediated.

### Why not globally disable the versioning policy?

Because a global skip could silently weaken production or other sensitive buckets. A narrow resource-level exception is safer and more auditable.

### What if the full scan reports additional failures?

Review each finding against the workload's security baseline. Some are mandatory controls; others may not apply to that workload. Do not make a pipeline green by blindly suppressing findings.

### Checkov or OPA?

Use both when appropriate. Checkov provides broad built-in security coverage; OPA expresses custom organizational rules.

### What did the scanner-version problem teach?

Security tooling itself requires lifecycle management. Scanner version and policy availability must be understood; a green result only has meaning if the expected checks actually ran.

---

## Key Takeaways

~~~text
terraform validate
≠ security validation

Checkov
= built-in IaC security scanning

OPA
= custom Policy as Code

PASS
= control satisfied

FAIL
= blocking policy violation

SKIP
= explicit accepted exception

Soft fail
= visible finding without blocking

Green scan
≠ all desired policies were necessarily evaluated
~~~

The objective is not simply to make the scanner green. The objective is to enforce the correct security baseline for the workload and environment.
