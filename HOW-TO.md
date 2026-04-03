# How-To Guide: Multi-Org DevOps Blueprint

This guide walks you through the most common tasks when working with this repository — from first setup to daily development, deployments, and troubleshooting.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Initial Setup (Fork & Configure)](#2-initial-setup)
3. [Day-to-Day Development](#3-day-to-day-development)
4. [Deploying Changes](#4-deploying-changes)
5. [Creating a Release](#5-creating-a-release)
6. [Adding a New Org / Region](#6-adding-a-new-org--region)
7. [Adding a New Shared Package](#7-adding-a-new-shared-package)
8. [Adding Org-Specific Logic](#8-adding-org-specific-logic)
9. [Running Tests Locally](#9-running-tests-locally)
10. [Debugging Pipeline Failures](#10-debugging-pipeline-failures)
11. [Managing Secrets & Environments](#11-managing-secrets--environments)
12. [Common Patterns & Recipes](#12-common-patterns--recipes)

---

## 1. Prerequisites

Install these tools before you begin:

```bash
# Salesforce CLI (sf)
npm install -g @salesforce/cli

# Verify installation
sf version

# GitHub CLI (optional but recommended)
brew install gh
gh auth login
```

You also need:
- A Salesforce Dev Hub org (for scratch orgs) or 3 sandbox orgs
- A GitHub account with access to this repository
- Node.js 18+ (for Salesforce CLI)

---

## 2. Initial Setup

### 2.1 Fork and Clone

```bash
# Fork via GitHub CLI
gh repo fork rammc/TDX-2026-Salesforce-DevOps-Multi-Org --clone
cd TDX-2026-Salesforce-DevOps-Multi-Org
```

### 2.2 Authenticate with Your Dev Hub

```bash
sf org login web --set-default-dev-hub --alias devhub
```

### 2.3 Create Scratch Orgs

```bash
# One scratch org per region
sf org create scratch --definition-file config/project-scratch-def.json --alias eu-scratch --duration-days 14
sf org create scratch --definition-file config/project-scratch-def.json --alias us-scratch --duration-days 14
sf org create scratch --definition-file config/project-scratch-def.json --alias apac-scratch --duration-days 14
```

> **Note:** If you don't have a Dev Hub, use existing sandboxes and authenticate with:
> ```bash
> sf org login web --alias eu-sandbox --instance-url https://test.salesforce.com
> ```

### 2.4 Deploy to Your Scratch Orgs

Deploy shared packages first (respecting dependency order), then org-specific metadata:

```bash
# EU org — shared + org-specific
sf project deploy start --source-dir packages/core        --target-org eu-scratch
sf project deploy start --source-dir packages/integration --target-org eu-scratch
sf project deploy start --source-dir packages/logic       --target-org eu-scratch
sf project deploy start --source-dir orgs/eu/logic        --target-org eu-scratch
sf project deploy start --source-dir orgs/eu/ui           --target-org eu-scratch

# US org — shared + org-specific
sf project deploy start --source-dir packages/core        --target-org us-scratch
sf project deploy start --source-dir packages/integration --target-org us-scratch
sf project deploy start --source-dir packages/logic       --target-org us-scratch
sf project deploy start --source-dir orgs/us/logic        --target-org us-scratch
sf project deploy start --source-dir orgs/us/ui           --target-org us-scratch

# APAC org — shared + org-specific
sf project deploy start --source-dir packages/core        --target-org apac-scratch
sf project deploy start --source-dir packages/integration --target-org apac-scratch
sf project deploy start --source-dir packages/logic       --target-org apac-scratch
sf project deploy start --source-dir orgs/apac/logic      --target-org apac-scratch
sf project deploy start --source-dir orgs/apac/ui         --target-org apac-scratch
```

### 2.5 Verify with Smoke Tests

```bash
./scripts/smoke-test.sh eu-scratch
./scripts/smoke-test.sh us-scratch
./scripts/smoke-test.sh apac-scratch
```

### 2.6 Configure GitHub Secrets

Generate auth URLs and store them as GitHub Environment secrets:

```bash
# Generate auth URL for each org
sf org display --target-org eu-scratch --verbose | grep "Sfdx Auth Url"

# Store in GitHub (repeat per org)
gh secret set SF_AUTH_URL --env production-eu < auth_url_eu.txt
gh secret set SF_AUTH_URL --env production-us < auth_url_us.txt
gh secret set SF_AUTH_URL --env production-apac < auth_url_apac.txt

# Sandbox environments for PR validation
gh secret set SF_AUTH_URL --env eu-sandbox < auth_url_eu.txt
gh secret set SF_AUTH_URL --env us-sandbox < auth_url_us.txt
gh secret set SF_AUTH_URL --env apac-sandbox < auth_url_apac.txt
```

### 2.7 Configure GitHub Environments

In your GitHub repository settings, create these environments:

| Environment | Purpose | Required Reviewers |
|-------------|---------|-------------------|
| `eu-sandbox` | PR validation against EU | None |
| `us-sandbox` | PR validation against US | None |
| `apac-sandbox` | PR validation against APAC | None |
| `production-eu` | Production deployments to EU | EU compliance team |
| `production-us` | Production deployments to US | US SOX auditor |
| `production-apac` | Production deployments to APAC | APAC admin |

### 2.8 Optional: Slack Notifications

```bash
# Store Slack webhook as a repository-level secret
gh secret set SLACK_WEBHOOK_URL
# Paste your Slack incoming webhook URL when prompted
```

---

## 3. Day-to-Day Development

### 3.1 Create a Feature Branch

```bash
git checkout main
git pull origin main
git checkout -b feature/my-change
```

### 3.2 Make Your Changes

Edit files in the appropriate directory:

| What you're changing | Where to edit |
|---------------------|---------------|
| Shared data model (fields, objects) | `packages/core/` |
| Shared integrations (APIs, CMDT) | `packages/integration/` |
| Shared business logic | `packages/logic/` |
| EU-only logic or UI | `orgs/eu/` |
| US-only logic or UI | `orgs/us/` |
| APAC-only logic or UI | `orgs/apac/` |
| CI/CD pipelines | `.github/workflows/` |

### 3.3 Test Locally Before Pushing

```bash
# Deploy your changed package to the relevant scratch org
sf project deploy start --source-dir packages/logic --target-org eu-scratch

# Run tests
sf apex run test --target-org eu-scratch --class-names AccountScoringServiceTest --result-format human
```

### 3.4 Push and Open a Pull Request

```bash
git add -A
git commit -m "feat: add scoring multiplier for enterprise accounts"
git push -u origin feature/my-change

# Open PR using the template
gh pr create --fill
```

The CI pipeline automatically:
1. Detects which packages/orgs your changes affect
2. Validates metadata against the affected sandbox orgs
3. Runs Apex tests
4. Posts a summary comment on your PR

### 3.5 Merge to Main

Once all checks pass and reviewers approve, merge via GitHub. This triggers:
- **`deploy-shared.yml`** if you changed files under `packages/`
- **`deploy-org-deltas.yml`** if you changed files under `orgs/`

---

## 4. Deploying Changes

### How the Pipelines Decide What to Deploy

The `scripts/detect-changes.sh` script compares your changes against the base branch and outputs:

```json
{
  "shared_changed": true,
  "affected_packages": ["core", "logic"],
  "affected_orgs": ["eu"]
}
```

You can run it locally to preview what the pipeline would do:

```bash
./scripts/detect-changes.sh origin/main
```

### Shared Package Deployment Order

Shared packages always deploy in this order (defined in `config/deployment-order.json`):

```
core  →  integration  →  logic
```

Each package deploys to **all three orgs** before the next package starts. This ensures every org has the dependency before the dependent package arrives.

### Org-Specific Deployments

Org-specific changes deploy **only to the affected org**. If you change a file in `orgs/eu/`, only the EU org gets a deployment. Multiple orgs deploy in parallel.

### Manual Deployment

If you need to deploy manually (e.g., hotfix):

```bash
# Deploy a single package to a single org
sf project deploy start \
  --source-dir packages/core \
  --target-org eu-prod \
  --wait 60

# Dry-run first to validate
sf project deploy start \
  --source-dir packages/core \
  --target-org eu-prod \
  --dry-run
```

---

## 5. Creating a Release

Releases are triggered by pushing a version tag:

```bash
# Tag the current commit
git tag v1.2.0
git push origin v1.2.0
```

This triggers `orchestrate-release.yml`, which:

1. Detects all changes since the previous tag
2. Deploys shared packages sequentially (core → integration → logic), each rolling through EU → US → APAC
3. Deploys org-specific deltas in parallel
4. Runs smoke tests per org
5. Posts a release notification to Slack with a deployment matrix

**Approval gates:** Each production environment requires manual approval before the deployment proceeds. Reviewers are notified via GitHub.

### Viewing the Release Matrix

After the workflow completes, the release notification shows:

```
Release: v1.2.0

Package        | EU       | US       | APAC
-------------- | -------- | -------- | --------
core           | deployed | deployed | deployed
integration    | skipped  | skipped  | skipped
logic          | deployed | deployed | deployed

Org Deltas:  EU: deployed | US: skipped | APAC: skipped
Smoke Tests: EU: passed   | US: passed  | APAC: passed
```

---

## 6. Adding a New Org / Region

Example: Adding a **LATAM** org.

### Step 1: Create the Directory Structure

```bash
mkdir -p orgs/latam/logic/main/default/classes
mkdir -p orgs/latam/ui/main/default/flexipages
```

### Step 2: Update `sfdx-project.json`

Add the new package directories:

```json
{
  "path": "orgs/latam/logic",
  "package": "modbp-latam-logic",
  "versionName": "LATAM Region Logic v1",
  "versionNumber": "1.0.0.NEXT",
  "dependencies": [
    { "package": "modbp-logic", "versionNumber": "1.0.0.LATEST" }
  ]
},
{
  "path": "orgs/latam/ui",
  "default": false
}
```

### Step 3: Update `config/org-registry.json`

Add the LATAM org entry with alias, auth secret, governance rules, and package list.

### Step 4: Update `config/deployment-order.json`

Add `orgs/latam/logic` and `orgs/latam/ui` to the dependency graph.

### Step 5: Update GitHub Actions

In all workflow files, add `latam` to the org matrix arrays. Update `scripts/detect-changes.sh` to include the new region.

### Step 6: Update CODEOWNERS

```
orgs/latam/    @latam-team
```

### Step 7: Create GitHub Environments

- `latam-sandbox` (no reviewers)
- `production-latam` (with required reviewers)

### Step 8: Store Secrets

```bash
gh secret set SF_AUTH_URL --env production-latam
gh secret set SF_AUTH_URL --env latam-sandbox
```

---

## 7. Adding a New Shared Package

Example: Adding a **notifications** package.

### Step 1: Create the Directory

```bash
mkdir -p packages/notifications/main/default/classes
```

### Step 2: Update `sfdx-project.json`

```json
{
  "path": "packages/notifications",
  "package": "modbp-notifications",
  "versionName": "Notification Services v1",
  "versionNumber": "1.0.0.NEXT",
  "dependencies": [
    { "package": "modbp-core", "versionNumber": "1.0.0.LATEST" }
  ]
}
```

### Step 3: Update `config/deployment-order.json`

Insert `notifications` in the correct position in the `deploy_order` array, after its dependencies.

### Step 4: Update `deploy-shared.yml`

Add a new deploy job for the notifications package, chained after its dependency (core) and before any packages that depend on it.

### Step 5: Add CODEOWNERS Entry

```
packages/notifications/    @notifications-team
```

---

## 8. Adding Org-Specific Logic

Example: Adding a new compliance handler for the EU org.

### Step 1: Create the Apex Class

```bash
# Create the class files
touch orgs/eu/logic/main/default/classes/EPrivacyHandler.cls
touch orgs/eu/logic/main/default/classes/EPrivacyHandler.cls-meta.xml
touch orgs/eu/logic/main/default/classes/EPrivacyHandlerTest.cls
touch orgs/eu/logic/main/default/classes/EPrivacyHandlerTest.cls-meta.xml
```

### Step 2: Write the Meta XML

Every Apex class needs a `-meta.xml` file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>62.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

### Step 3: Reference Cross-Package Fields with Namespace

When referencing fields from `packages/core` in org-specific code, use the namespace prefix:

```apex
// Correct — cross-package reference
String classification = acc.modbp__Data_Classification__c;

// Wrong — only works within the same package
String classification = acc.Data_Classification__c;
```

### Step 4: Write Tests

Ensure >85% code coverage. Use meaningful assertions:

```apex
@IsTest
static void shouldBlockRestrictedExport() {
    Account acc = new Account(
        Name = 'Test Corp',
        modbp__Data_Classification__c = 'Restricted'
    );

    Boolean canExport = EPrivacyHandler.canExport(acc);

    System.assertEquals(false, canExport,
        'Restricted accounts must not be exportable under ePrivacy regulation');
}
```

---

## 9. Running Tests Locally

### Run All Tests in a Package

```bash
# Run all test classes for core
sf apex run test \
  --target-org eu-scratch \
  --class-names GlobalIdServiceTest \
  --result-format human \
  --code-coverage
```

### Run All Tests for an Org

```bash
# Use the smoke test script
./scripts/smoke-test.sh eu-scratch
```

### Run a Specific Test Method

```bash
sf apex run test \
  --target-org eu-scratch \
  --tests GlobalIdServiceTest.shouldGenerateValidFormat \
  --result-format human
```

### Check Code Coverage

```bash
sf apex run test \
  --target-org eu-scratch \
  --class-names GlobalIdServiceTest,IntegrationRouterTest,AccountScoringServiceTest \
  --code-coverage \
  --result-format json | jq '.result.coverage.coverage[]'
```

---

## 10. Debugging Pipeline Failures

### "Validation failed" in validate-pr.yml

The metadata doesn't compile in the target org. Common causes:
1. **Missing dependency** — you added code that references a field/class from another package that isn't deployed yet
2. **Namespace mismatch** — forgot the `modbp__` prefix in org-specific code
3. **API version mismatch** — meta XML uses a different API version than the org supports

Fix: deploy the dependency package first, or check field API names.

### "Authentication failed" in deploy workflows

The `SF_AUTH_URL` secret is expired or invalid.

```bash
# Regenerate the auth URL
sf org display --target-org your-org --verbose | grep "Sfdx Auth Url"

# Update the secret
gh secret set SF_AUTH_URL --env production-eu
```

### "Test failure" in smoke tests

```bash
# Reproduce locally
sf apex run test --target-org eu-scratch --class-names GDPRComplianceHandlerTest --result-format human

# Check test output for assertion messages
sf apex run test --target-org eu-scratch --class-names GDPRComplianceHandlerTest --result-format json | jq '.result.tests[] | select(.Outcome != "Pass")'
```

### Pipeline runs but deploys nothing

The change detection script didn't find relevant changes. Debug locally:

```bash
./scripts/detect-changes.sh origin/main
```

Check that your changed files are under `packages/` or `orgs/` — changes outside these directories don't trigger deployments.

---

## 11. Managing Secrets & Environments

### Required Secrets per Environment

| Secret | Scope | Description |
|--------|-------|-------------|
| `SF_AUTH_URL` | Per environment | SFDX auth URL for the target Salesforce org |
| `SLACK_WEBHOOK_URL` | Repository | Slack incoming webhook for deployment notifications |

### Rotating Auth URLs

Auth URLs expire when:
- A sandbox is refreshed
- A scratch org expires
- A user's password is changed

To rotate:

```bash
# 1. Re-authenticate
sf org login web --alias eu-prod

# 2. Get new auth URL
sf org display --target-org eu-prod --verbose 2>&1 | grep "Sfdx Auth Url"

# 3. Update GitHub secret
gh secret set SF_AUTH_URL --env production-eu
```

### Listing Current Environments

```bash
gh api repos/{owner}/{repo}/environments | jq '.environments[].name'
```

---

## 12. Common Patterns & Recipes

### Deploy Only One Package to One Org

```bash
sf project deploy start --source-dir packages/integration --target-org us-scratch --dry-run
# Remove --dry-run when ready
sf project deploy start --source-dir packages/integration --target-org us-scratch
```

### Retrieve Metadata from an Org

```bash
# Pull all metadata for a package
sf project retrieve start --source-dir packages/core --target-org eu-scratch
```

### Compare Org Against Repo

```bash
sf project deploy start --source-dir packages/core --target-org eu-scratch --dry-run
# If the dry-run succeeds with no errors, the org matches the repo
```

### Roll Back a Deployment

There is no built-in rollback in Salesforce metadata deployments. Instead:

```bash
# 1. Revert the commit
git revert HEAD

# 2. Push to main — the pipeline re-deploys the previous state
git push origin main
```

### Run the Change Detection Script Locally

```bash
# See what the pipeline would detect
./scripts/detect-changes.sh origin/main

# Compare against a specific commit
./scripts/detect-changes.sh abc123
```

### Open a Quick PR for a Hotfix

```bash
git checkout -b hotfix/fix-scoring-null-check
# ... make your fix ...
git add packages/logic/main/default/classes/AccountScoringService.cls
git commit -m "fix: handle null AnnualRevenue in scoring service"
git push -u origin hotfix/fix-scoring-null-check
gh pr create --title "fix: handle null AnnualRevenue in scoring service" --body "Prevents NPE when Account.AnnualRevenue is null"
```

---

## Quick Reference Card

| Task | Command |
|------|---------|
| Deploy package | `sf project deploy start -d packages/core -o eu-scratch` |
| Validate only | `sf project deploy start -d packages/core -o eu-scratch --dry-run` |
| Run tests | `sf apex run test -o eu-scratch -n MyTestClass --result-format human` |
| Smoke test | `./scripts/smoke-test.sh eu-scratch` |
| Detect changes | `./scripts/detect-changes.sh origin/main` |
| Create release | `git tag v1.0.0 && git push origin v1.0.0` |
| Rotate secret | `gh secret set SF_AUTH_URL --env production-eu` |
| Open PR | `gh pr create --fill` |

---

*For architecture decisions and rationale, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DECISION-LOG.md](docs/DECISION-LOG.md).*

*For full environment setup instructions, see [docs/SETUP-GUIDE.md](docs/SETUP-GUIDE.md).*
