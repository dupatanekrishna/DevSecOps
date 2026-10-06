# Lab 04 - End-to-End CI/CD Security Gates

## Objective

Build one practical DevSecOps pipeline that combines software-quality checks, secret detection, static analysis, dependency scanning, IaC policy, container scanning, and DAST.

The lab intentionally contains insecure code and old dependencies so the scanners have something real to detect.

> **Important:** the vulnerable code and dependencies in this folder are training examples. Do not reuse them in production.

---

## Final Pipeline

~~~text
Developer / Pull Request
        ↓
Unit tests + coverage
        ↓
Gitleaks
Secret scanning
        ↓
Semgrep
SAST
        ↓
SonarQube
Static analysis + Quality Gate
        ↓
Trivy filesystem scan
SCA / vulnerable dependencies
        ↓
Checkov
Built-in IaC security baseline
        ↓
OPA / Conftest
Custom organization policy
        ↓
Docker build
        ↓
Trivy image scan
OS + application package CVEs
        ↓
Deploy test application
        ↓
OWASP ZAP
DAST
        ↓
PASS → eligible for promotion
FAIL → pipeline blocked
~~~

The GitHub Actions workflow implements the GitHub-hosted portions of this flow. Local SonarQube is documented separately because a GitHub-hosted runner cannot reach a SonarQube server bound to a developer laptop's `localhost`.

---

## Repository Layout

~~~text
04-cicd-security-gates/
├── app/
│   ├── app.py
│   └── requirements.txt
├── tests/
│   └── test_app.py
├── .dockerignore
├── .gitleaks.toml
├── Dockerfile
├── docker-compose-sonarqube.yml
├── requirements-dev.txt
├── sonar-project.properties
└── README.md

.github/workflows/
└── devsecops-security.yml
~~~

Generated files are intentionally not committed:

~~~text
.venv/
coverage.xml
.coverage
.pytest_cache/
__pycache__/
zap-report.html
zap-full-report.html
tfplan
tfplan.json
Terraform state
~~~

---

# Gate 1 - Unit Tests and Coverage

## Why unit tests belong before security scanning

Unit tests answer:

> Does the code behave as expected?

Security tools answer different questions:

~~~text
Unit tests
→ functional correctness

Coverage
→ how much application code the tests executed

SAST
→ insecure source-code patterns

SCA
→ vulnerable third-party dependencies

Container scan
→ vulnerabilities in final image packages

DAST
→ runtime behavior visible over HTTP
~~~

The lab uses:

~~~text
pytest
pytest-cov
~~~

Run:

~~~bash
python3.12 -m venv .venv
source .venv/bin/activate

pip install -r app/requirements.txt
pip install -r requirements-dev.txt

pytest -v

pytest \
  --cov=app \
  --cov-report=term-missing \
  --cov-fail-under=70
~~~

Observed hands-on result:

~~~text
2 tests passed
Coverage ≈ 78%
Required threshold = 70%
Exit code = 0
~~~

So:

~~~text
tests pass + coverage >= threshold
        ↓
exit 0
        ↓
pipeline continues
~~~

If tests fail or coverage drops below the configured threshold, pytest returns a non-zero exit code.

---

## What does coverage mean?

Coverage measures which lines of application code were executed while tests ran.

Example generated XML:

~~~xml
<coverage
  lines-valid="20"
  lines-covered="16"
  line-rate="0.8">
~~~

Meaning:

~~~text
20 coverable lines
16 executed by tests

16 / 20 = 80%
~~~

Individual lines look like:

~~~xml
<line number="18" hits="1"/>
<line number="28" hits="0"/>
~~~

~~~text
hits=1
→ executed

hits=0
→ not executed
~~~

The flow is:

~~~text
pytest
   ↓
pytest-cov / coverage.py
   ↓
coverage.xml
   ↓
SonarQube imports it
   ↓
Coverage displayed in dashboard
~~~

High coverage does **not** prove the tests are good. Weak assertions can still execute many lines.

### Engineering Explanation

> Code coverage measures how much of the codebase is exercised by automated tests. I can enforce a minimum threshold in CI, but I do not treat coverage percentage alone as proof of test quality.

---

# Troubleshooting - Python 3.14 vs Old Werkzeug

The first test run used Python 3.14 with intentionally old Flask/Werkzeug dependencies and failed during pytest collection.

Observed error:

~~~text
AttributeError: module 'ast' has no attribute 'Str'
~~~

This was not an application-test failure. It was runtime/dependency incompatibility.

The lab was moved to Python 3.12, where the old Werkzeug package still runs but emits deprecation warnings.

Lesson:

~~~text
source code
   ↓
runtime compatibility
   ↓
dependency compatibility
   ↓
test collection
   ↓
unit tests
~~~

A CI pipeline can fail before tests execute if the runtime and dependency set are incompatible.

---

# Gate 2 - Secret Scanning with Gitleaks

A controlled lab-specific rule is defined in `.gitleaks.toml`.

Example intentionally bad source:

~~~python
LAB_SECRET = "devsecops-demo-secret"
~~~

Gitleaks detected it:

~~~text
leaks found: 1
exit code: 1
~~~

The remediation was:

~~~python
import os

LAB_SECRET = os.environ.get("LAB_SECRET")
~~~

After removing the hard-coded value:

~~~text
no leaks found
exit code: 0
~~~

## Important doubt explored: is commenting out a secret enough?

No.

This was still detected:

~~~python
# LAB_SECRET = "devsecops-demo-secret"
~~~

A secret scanner scans repository text; it does not care that Python treats the line as a comment.

~~~text
commenting out a secret
≠ removing the secret
~~~

If a real credential was ever committed, rotate/revoke it and clean the repository history as required by the organization's incident process.

---

# Gate 3 - SAST with Semgrep

Run:

~~~bash
semgrep scan \
  --config auto \
  app/
~~~

Observed hands-on result:

~~~text
8 findings
8 marked blocking
~~~

Important findings included:

~~~text
user-controlled eval()
→ code injection / arbitrary code execution risk

subprocess + user-controlled input
→ command injection

shell=True
→ unsafe shell invocation

debug=True
→ production information exposure risk

host=0.0.0.0
→ scanner warning that requires workload context
~~~

## Scanner finding vs pipeline gate

The default scan returned:

~~~text
findings: 8
exit code: 0
~~~

That demonstrates:

~~~text
scanner found a vulnerability
≠ pipeline automatically blocked
~~~

To enforce the gate:

~~~bash
semgrep scan \
  --config auto \
  --error \
  app/

echo $?
~~~

Observed:

~~~text
exit code: 1
~~~

Now it behaves as a CI gate.

## Important doubt: should every Semgrep finding be blindly fixed?

No.

For example, `host="0.0.0.0"` is often necessary inside Docker/Kubernetes so the application can receive traffic through the container network.

The process should be:

~~~text
finding
   ↓
understand context
   ↓
real vulnerability?
false positive?
required architecture?
approved exception?
~~~

---

# Gate 4 - SonarQube

## Why SonarQube if Semgrep already works?

Semgrep is very CLI-first and excellent for fast shift-left SAST and custom rules.

SonarQube is a centralized analysis platform that combines:

~~~text
code quality
security findings
security hotspots
bugs
maintainability
coverage
duplication
quality gates
history/trends
~~~

They overlap, but they solve different operational problems.

~~~text
Semgrep
→ lightweight / CLI-first
→ fast PR scanning
→ custom security rules

SonarQube
→ centralized platform
→ dashboards
→ quality profiles
→ quality gates
→ governance across many projects
~~~

---

## Scaling SonarQube to multiple projects

A separate SonarQube server is not normally created for each application.

~~~text
                    Central SonarQube
                           │
            ┌──────────────┼──────────────┐
            │              │              │
       backend-api    frontend-ui    device-service
            ↑              ↑              ↑
      sonar-scanner   sonar-scanner   sonar-scanner
            ↑              ↑              ↑
        CI pipeline     CI pipeline     CI pipeline
~~~

Each repository has its own unique project key:

~~~properties
sonar.projectKey=payment-service
~~~

or:

~~~properties
sonar.projectKey=device-service
~~~

but scanners upload to the same central SonarQube service.

This allows platform/security teams to centrally manage quality profiles, gates, security findings, coverage and trends.

---

## Environment separation - DEV / STAGE / PROD

A common question during the lab was whether SonarQube projects should be created separately for DEV, STAGE and PROD.

Usually, no.

SonarQube primarily analyzes **source code**, so a normal model is:

~~~text
one application/repository
        ↓
one SonarQube project
        ↓
Quality Gate
        ↓
build one artifact
        ↓
DEV
        ↓
STAGE
        ↓
PROD
~~~

Environment separation normally belongs to deployment/configuration tooling:

~~~text
Terraform
ArgoCD
Helm
OPA
Checkov
Kubernetes admission policy
cloud guardrails
~~~

If DEV/STAGE/PROD are genuinely different codebases or repositories, separate projects can make sense.

---

## Local SonarQube Setup

The lab uses SonarQube Community + PostgreSQL:

~~~bash
docker-compose \
  -f docker-compose-sonarqube.yml \
  up -d
~~~

Access:

~~~text
http://localhost:9000
~~~

Project used in the lab:

~~~text
Display name: devsecops-security-lab
Project key:  devsecops-security-lab
Main branch:  main
~~~

Do not commit the Sonar token.

Use an environment variable:

~~~bash
export SONAR_TOKEN="..."
~~~

If a token is accidentally exposed, revoke it and generate a new one.

---

## Coverage Integration with SonarQube

Generate XML:

~~~bash
pytest \
  --cov=app \
  --cov-report=xml:coverage.xml
~~~

Sonar config:

~~~properties
sonar.python.coverage.reportPaths=coverage.xml
~~~

Observed dashboard result:

~~~text
Coverage: 80%
Security: 3 open issues
Reliability: A
Maintainability: A
Duplications: 0%
~~~

The coverage XML is machine-readable evidence of which source lines executed during tests.

---

## Quality Gate Lesson

The project initially showed security issues while the Quality Gate still passed.

That teaches:

~~~text
issues detected
≠ Quality Gate automatically fails
~~~

The Quality Gate contains the organization's acceptance policy.

For CI enforcement:

~~~bash
sonar-scanner \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.qualitygate.wait=true
~~~

Observed:

~~~text
QUALITY GATE STATUS: PASSED
EXECUTION SUCCESS
exit code 0
~~~

The important architecture is:

~~~text
sonar-scanner
      ↓
analysis uploaded
      ↓
SonarQube evaluates Quality Gate
      ↓
PASS / FAIL
      ↓
CI continues / blocks
~~~

---

## Why local SonarQube is optional in GitHub Actions

A GitHub-hosted runner cannot directly reach:

~~~text
http://localhost:9000
~~~

running on a developer laptop.

For a real centralized SonarQube server:

~~~text
GitHub runner
     ↓
network-reachable SonarQube URL
~~~

For a laptop-only SonarQube instance, use a self-hosted runner on the same reachable network or keep the Sonar experiment local.

The workflow therefore documents SonarQube as an optional self-hosted job.

---

# Gate 5 - SCA with Trivy

Filesystem scan:

~~~bash
trivy fs \
  --scanners vuln \
  app/
~~~

Observed on the intentionally old dependency set:

~~~text
15 vulnerabilities
LOW: 2
MEDIUM: 10
HIGH: 3
CRITICAL: 0
~~~

Examples included older Flask and Werkzeug versions.

To make it blocking:

~~~bash
trivy fs \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  app/
~~~

---

## Important doubt: severity vs remediation priority

Scanner severity and business priority are related but not identical.

Evaluate:

~~~text
scanner severity
      ↓
exploitability
      ↓
reachability
      ↓
internet exposure
      ↓
asset criticality
      ↓
data sensitivity
      ↓
privilege gained
      ↓
known exploitation
      ↓
patch availability
      ↓
business remediation priority
~~~

Example:

~~~text
HIGH CVE
+ internet-facing
+ reachable vulnerable function
+ customer sessions/data
+ patch available
→ very high remediation priority
~~~

But:

~~~text
HIGH CVE
+ unused code path
+ isolated ephemeral lab
+ no sensitive data
→ lower practical priority
~~~

A useful baseline policy is:

~~~text
CRITICAL
→ block

HIGH
→ normally block; exception requires review

MEDIUM
→ remediate based on context/SLA

LOW
→ backlog / baseline policy
~~~

Do not blindly reduce security gates just to make the pipeline green.

---

# Gate 6 - Docker Image Scanning

## Application dependency scan vs image scan

~~~text
Trivy fs
→ source repository
→ language/package dependencies

Trivy image
→ final container artifact
→ OS packages + installed application dependencies
~~~

The image scan found operating-system CVEs in packages such as:

~~~text
ncurses
perl-base
util-linux
~~~

Some findings had no immediate patched version.

The right process is:

~~~text
CVE found
   ↓
patched base/package available?
   ├─ YES → upgrade/rebuild
   │
   └─ NO
       ↓
evaluate reachability/exposure/privilege
       ↓
risk exception / compensating control / monitor
~~~

---

## How to reduce Docker image size

The lab discussion covered:

~~~text
use slim/minimal base images
copy only required files
use .dockerignore
pip --no-cache-dir
remove package-manager caches
avoid unnecessary tools
multi-stage build when compilers/build tools are needed
run a minimal runtime stage
~~~

The lab Dockerfile uses:

~~~dockerfile
FROM python:3.12-slim
~~~

and:

~~~dockerfile
RUN pip install --no-cache-dir -r requirements.txt
~~~

plus `.dockerignore`.

It also runs the application as a non-root user as a defense-in-depth baseline.

---

## Important doubt: EXPOSE vs docker run -p

`EXPOSE 8080` does not publish a host port. It documents the intended container port.

If the application listens inside the container on 8080:

~~~bash
docker run -p 9090:8080 image
~~~

means:

~~~text
localhost:9090
       ↓
container:8080
       ↓
Flask application
~~~

General syntax:

~~~text
-p HOST_PORT:CONTAINER_PORT
~~~

So the host port may be completely different from the container's listening port.

The right-hand side must match the port the application actually listens on.

---

# Gate 7 - Checkov + OPA / Conftest in CI

This gate reuses Labs 02 and 03 rather than repeating their full experiments.

~~~text
Terraform
   ↓
Checkov
built-in IaC baseline
   ↓
OPA / Conftest
custom organization policy
   ↓
PASS / FAIL
~~~

## Checkov

Example selected baseline:

~~~text
CKV_AWS_24
→ no public SSH

CKV_AWS_19
→ S3 encryption at rest

CKV_AWS_21
→ versioning policy / documented exception

CKV2_AWS_6
→ S3 Public Access Block
~~~

Checkov answers:

> Does this violate known IaC security controls?

OPA answers:

> Does this violate our organization's policy?

---

## OPA / Conftest

The policy checks Terraform plan JSON.

~~~text
Terraform
   ↓
terraform plan
   ↓
terraform show -json
   ↓
tfplan.json
   ↓
Conftest
   ↓
Rego
   ↓
PASS / DENY
~~~

Hands-on secure case:

~~~text
1 test
1 passed
0 failures
exit code 0
~~~

The insecure test from Lab 02 demonstrates the opposite result for SSH exposed to `0.0.0.0/0`.

---

## Troubleshooting: nested Lab 02 directories

A path issue was discovered while integrating OPA into Lab 04.

The accidental structure contained:

~~~text
02-policy-as-code/terraform/02-policy-as-code/...
~~~

The files were moved back to:

~~~text
02-policy-as-code/
├── policy/
│   └── terraform.rego
└── terraform/
    └── main.tf
~~~

Two useful lessons:

1. `terraform validate` can succeed in an empty directory because there is nothing invalid to validate.
2. An exit code of 1 from Conftest is not automatically a policy denial. Check the message: a missing policy directory is a tooling/configuration error, not a security-policy violation.

---

# GitOps / Terraform Controller / ArgoCD Question

A question explored during this lab was:

> If Terraform Controller or ArgoCD performs deployment, where does shift-left security go?

It still belongs before merge.

~~~text
Developer
   ↓
Pull Request
   ↓
tests / secrets / SAST / SCA
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
ArgoCD / Terraform Controller
   ↓
actual platform
~~~

The controller replaces/directs the deployment/reconciliation step; it does not replace CI security gates.

Then add deployment-time controls:

~~~text
Kubernetes
→ Gatekeeper / Kyverno / Pod Security

AWS
→ IAM / SCP / service controls
~~~

And runtime controls:

~~~text
WAF
monitoring
SIEM
alerts
~~~

Mental model:

~~~text
CI gate
→ Should this change enter Git?

ArgoCD / Terraform Controller
→ Make actual state match approved Git state.

Gatekeeper / Kyverno / SCP
→ Is this deployment allowed by the platform?
~~~

The deeper GitOps discussion is also documented in Lab 02.

---

# Gate 8 - DAST with OWASP ZAP

DAST requires a running application.

~~~text
application container
       ↓
HTTP endpoint
       ↓
OWASP ZAP
       ↓
external runtime scan
~~~

Baseline scan:

~~~bash
docker run --rm \
  --network devsecops-lab \
  -v "$(pwd):/zap/wrk/:rw" \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
  -t http://devsecops-app:8080 \
  -r zap-report.html
~~~

Observed baseline:

~~~text
FAIL: 0
WARN: 6
PASS: 61
~~~

Warnings included:

~~~text
missing X-Content-Type-Options
server version disclosure
missing CSP
cacheable content
missing Permissions-Policy
missing Cross-Origin-Resource-Policy
~~~

Full/active scan:

~~~bash
docker run --rm \
  --network devsecops-lab \
  -v "$(pwd):/zap/wrk/:rw" \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-full-scan.py \
  -t http://devsecops-app:8080 \
  -r zap-full-report.html
~~~

Observed:

~~~text
PASS: 136
WARN: 5
FAIL: 0
exit code: 2
~~~

ZAP uses distinct exit behavior for warnings vs failures, so pipeline policy should explicitly decide whether warnings block.

---

## Important DAST limitation discovered

The application contains deliberately insecure endpoints using `eval()` and `subprocess(..., shell=True)`.

Semgrep sees them directly because it reads source code.

ZAP may not exploit them if those routes and parameters are not discovered by spidering/crawling.

The scan discovered only a small set of URLs.

Therefore:

~~~text
DAST PASS for a particular attack rule
≠ proof that vulnerability cannot exist
~~~

DAST coverage depends on:

~~~text
route discovery
authentication
API definitions
crawl coverage
request parameters
test data
application state
~~~

This is why SAST and DAST complement each other.

---

# Gate 9 - GitHub Actions

Workflow:

~~~text
.github/workflows/devsecops-security.yml
~~~

The pipeline is triggered on pull requests and pushes to `main`.

Major jobs:

~~~text
unit-tests
gitleaks
semgrep
trivy-sca
iac-security
container-security
dast
optional SonarQube self-hosted job
~~~

## Expected first-run behavior

The application intentionally still contains:

~~~python
eval(expression)
~~~

and:

~~~python
subprocess.check_output(
    command_input,
    shell=True,
)
~~~

Therefore the first GitHub Actions run is **expected to fail** at the SAST security gate.

That is part of the experiment.

~~~text
bad code
   ↓
PR / pipeline
   ↓
Semgrep
   ↓
blocking finding
   ↓
exit 1
   ↓
downstream deployment/security stages blocked
~~~

Then the next experiment is:

~~~text
FAIL
  ↓
remediate code
  ↓
commit / push
  ↓
pipeline reruns
  ↓
PASS
~~~

This demonstrates the complete shift-left lifecycle.

---

# How the Gates Differ

| Gate | Tool | Primary question |
|---|---|---|
| Unit tests | pytest | Does the code behave correctly? |
| Coverage | pytest-cov | How much code did the tests exercise? |
| Secret scanning | Gitleaks | Did credentials/secrets enter source? |
| SAST | Semgrep | Does source contain insecure patterns? |
| Code quality/security | SonarQube | Does code meet centralized quality/security policy? |
| SCA | Trivy FS | Are third-party dependencies vulnerable? |
| IaC | Checkov | Does infrastructure violate built-in cloud/IaC controls? |
| Policy as Code | OPA/Conftest | Does infrastructure violate organization-specific policy? |
| Container | Trivy Image | Does the built artifact contain OS/app CVEs? |
| DAST | OWASP ZAP | What security issues are observable in the running app? |

---

# Knowledge Check

## What is shift-left security?

Moving security feedback earlier into developer and pull-request workflows so defects are caught before deployment.

## Does adding a scanner automatically create a security gate?

No. The scanner must return an enforced non-zero status or the CI system must evaluate its results against a blocking policy.

## Why use both Semgrep and SonarQube?

Semgrep is fast and CLI/rule focused. SonarQube provides centralized governance, dashboards, history, code quality, coverage and Quality Gates.

## Why use SAST and DAST together?

SAST can inspect vulnerable code even when a runtime scanner cannot discover the route. DAST sees the deployed application's real HTTP behavior and configuration.

## Why use Trivy twice?

Filesystem/SCA scanning evaluates source dependencies. Image scanning evaluates the final container including OS packages and installed dependencies.

## How do you decide whether a CVE is high priority?

Combine scanner severity with exploitability, reachability, exposure, business/asset criticality, sensitive data, privilege impact, known exploitation, fix availability and compensating controls.

## What if a HIGH CVE has no fix?

Assess reachability and exposure, minimize privilege/attack surface, apply compensating controls, record an approved exception if policy permits, monitor for an upstream fix, and rebuild when one is released.

## Why run containers as non-root?

It reduces the privilege and impact available to an attacker if the application is compromised.

## Does EXPOSE publish a port?

No. `EXPOSE` is metadata/documentation. `docker run -p HOST:CONTAINER` performs the host-to-container mapping.

## What is the difference between Checkov and OPA?

Checkov gives broad built-in IaC security checks. OPA/Rego expresses custom organization-specific policy.

## If ArgoCD/Terraform Controller deploys, where are CI security gates?

Before merge. Approved Git becomes desired state, then controllers reconcile it. Admission controls/SCPs remain as another enforcement layer.

## Why did SonarQube pass while security issues existed?

Because Quality Gate behavior depends on configured conditions, often focused on New Code. Detection and enforcement are separate concepts.

## Can GitHub-hosted Actions reach SonarQube on my laptop?

Not directly through `localhost`. Use a centrally reachable SonarQube service or a self-hosted runner/network path that can reach the server.

---

# Key Lessons

~~~text
Testing != security scanning

Finding != enforcement

Severity != business priority

SAST != DAST

Source scan != image scan

Built-in policy != custom organization policy

GitOps != removal of shift-left controls

Green scanner output != proof every desired policy was evaluated
~~~

A mature DevSecOps pipeline layers these controls rather than treating any single scanner as complete security.
