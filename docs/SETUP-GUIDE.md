# Setup Guide

This guide walks you through setting up the multi-org DevOps blueprint from scratch — forking the repository, creating orgs, configuring CI/CD, and verifying your first deployment.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Fork the Repository](#2-fork-the-repository)
3. [Create Scratch Orgs](#3-create-scratch-orgs)
4. [Authenticate and Store Auth URLs](#4-authenticate-and-store-auth-urls)
5. [Configure GitHub Environments](#5-configure-github-environments)
6. [Run Initial Deployment](#6-run-initial-deployment)
7. [Verify with Smoke Tests](#7-verify-with-smoke-tests)
8. [Optional: Configure Slack Notifications](#8-optional-configure-slack-notifications)

---

## 1. Prerequisites

Install the following tools before proceeding.

### Salesforce CLI

The Salesforce CLI (`sf`) is required for all org interactions.

```bash
# macOS (Homebrew)
brew install sf

# npm (all platforms)
npm install -g @salesforce/cli

# Verify installation
sf version
# Expected: @salesforce/cli/2.x.x ...
```

Ensure you are on version **2.x** or later. The legacy `sfdx` command is deprecated.

### Git

```bash
# macOS
brew install git

# Verify
git --version
# Expected: git version 2.x.x
```

### GitHub CLI

The GitHub CLI (`gh`) simplifies repository and secret management.

```bash
# macOS
brew install gh

# Authenticate
gh auth login

# Verify
gh auth status
```

### Dev Hub Access

You need a Salesforce org with Dev Hub enabled to create scratch orgs.

1. Log in to your Dev Hub org.
2. Go to **Setup > Dev Hub** and ensure it is enabled.
3. Authorize the CLI:

```bash
sf org login web --set-default-dev-hub --alias devhub
```

---

## 2. Fork the Repository

```bash
# Fork and clone in one step
gh repo fork christopherramm/TDX-2026-Salesforce-DevOps-Multi-Org --clone --remote
cd TDX-2026-Salesforce-DevOps-Multi-Org

# Verify the remote setup
git remote -v
# origin    https://github.com/YOUR-USERNAME/TDX-2026-Salesforce-DevOps-Multi-Org.git (fetch)
# upstream  https://github.com/christopherramm/TDX-2026-Salesforce-DevOps-Multi-Org.git (fetch)
```

If you prefer to create the fork via the GitHub UI, clone your fork afterward:

```bash
git clone https://github.com/YOUR-USERNAME/TDX-2026-Salesforce-DevOps-Multi-Org.git
cd TDX-2026-Salesforce-DevOps-Multi-Org
```

---

## 3. Create Scratch Orgs

We create three scratch orgs to simulate the EU, US, and APAC environments. Each org uses the same scratch org definition but will receive different metadata.

### Option A: Scratch Orgs (recommended for development)

```bash
# Create the EU scratch org
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias eu-scratch \
  --duration-days 7 \
  --set-default \
  --target-dev-hub devhub

# Create the US scratch org
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias us-scratch \
  --duration-days 7 \
  --target-dev-hub devhub

# Create the APAC scratch org
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias apac-scratch \
  --duration-days 7 \
  --target-dev-hub devhub

# Verify all three orgs exist
sf org list --all
```

### Option B: Sandboxes (for staging and production pipelines)

If you are using sandboxes instead of scratch orgs, authenticate to each one:

```bash
# Authenticate to each sandbox
sf org login web --alias eu-sandbox --instance-url https://test.salesforce.com
sf org login web --alias us-sandbox --instance-url https://test.salesforce.com
sf org login web --alias apac-sandbox --instance-url https://test.salesforce.com
```

---

## 4. Authenticate and Store Auth URLs

GitHub Actions needs SFDX Auth URLs to authenticate with each org. An auth URL is a portable credential string that the CLI can use without interactive login.

### Generate Auth URLs

Run this for each org:

```bash
# EU org
sf org display --target-org eu-scratch --verbose --json | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['sfdxAuthUrl'])"

# US org
sf org display --target-org us-scratch --verbose --json | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['sfdxAuthUrl'])"

# APAC org
sf org display --target-org apac-scratch --verbose --json | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['sfdxAuthUrl'])"
```

Each command outputs a string like `force://PlatformCLI::...@login.salesforce.com`. Copy these values.

### Store as GitHub Secrets

Create the following GitHub repository secrets. The secret names must match exactly — they are referenced in the workflow files and `config/org-registry.json`.

```bash
# Store each auth URL as a GitHub secret
gh secret set SFDX_AUTH_URL_EU     --body "force://PlatformCLI::YOUR_EU_AUTH_URL"
gh secret set SFDX_AUTH_URL_US     --body "force://PlatformCLI::YOUR_US_AUTH_URL"
gh secret set SFDX_AUTH_URL_APAC   --body "force://PlatformCLI::YOUR_APAC_AUTH_URL"
```

For production orgs, use separate secrets:

```bash
gh secret set SFDX_AUTH_URL_PROD_EU   --body "force://PlatformCLI::YOUR_PROD_EU_AUTH_URL"
gh secret set SFDX_AUTH_URL_PROD_US   --body "force://PlatformCLI::YOUR_PROD_US_AUTH_URL"
gh secret set SFDX_AUTH_URL_PROD_APAC --body "force://PlatformCLI::YOUR_PROD_APAC_AUTH_URL"
```

### Complete Secret Reference

| Secret Name | Purpose | Used By |
|---|---|---|
| `SFDX_AUTH_URL_EU` | EU sandbox/scratch org authentication | deploy-shared, deploy-org-deltas, validate-pr |
| `SFDX_AUTH_URL_US` | US sandbox/scratch org authentication | deploy-shared, deploy-org-deltas, validate-pr |
| `SFDX_AUTH_URL_APAC` | APAC sandbox/scratch org authentication | deploy-shared, deploy-org-deltas, validate-pr |
| `SFDX_AUTH_URL_PROD_EU` | EU production org authentication | deploy-shared (production), deploy-org-deltas (production) |
| `SFDX_AUTH_URL_PROD_US` | US production org authentication | deploy-shared (production), deploy-org-deltas (production) |
| `SFDX_AUTH_URL_PROD_APAC` | APAC production org authentication | deploy-shared (production), deploy-org-deltas (production) |
| `SLACK_WEBHOOK_URL` | (Optional) Slack notifications | All workflows |

---

## 5. Configure GitHub Environments

GitHub Environments allow you to add approval gates and environment-specific secrets for production deployments.

### Create Environments

Navigate to your repository on GitHub: **Settings > Environments**, then create:

| Environment Name | Purpose | Required Reviewers | Wait Timer |
|---|---|---|---|
| `eu-sandbox` | EU sandbox deployments | None | None |
| `us-sandbox` | US sandbox deployments | None | None |
| `apac-sandbox` | APAC sandbox deployments | None | None |
| `production-eu` | EU production deployments | 1-2 reviewers | 5 minutes |
| `production-us` | US production deployments | 1-2 reviewers | 5 minutes |
| `production-apac` | APAC production deployments | 1-2 reviewers | 5 minutes |

Alternatively, use the GitHub CLI:

```bash
# Create sandbox environments (no protection rules)
gh api repos/{owner}/{repo}/environments/eu-sandbox --method PUT --input /dev/null
gh api repos/{owner}/{repo}/environments/us-sandbox --method PUT --input /dev/null
gh api repos/{owner}/{repo}/environments/apac-sandbox --method PUT --input /dev/null

# Create production environments
# Note: Protection rules (required reviewers) must be configured via the GitHub UI
# or via the API with appropriate payloads.
gh api repos/{owner}/{repo}/environments/production-eu --method PUT --input /dev/null
gh api repos/{owner}/{repo}/environments/production-us --method PUT --input /dev/null
gh api repos/{owner}/{repo}/environments/production-apac --method PUT --input /dev/null
```

To add required reviewers via the API (replace `REVIEWER_ID` with the GitHub user ID):

```bash
gh api repos/{owner}/{repo}/environments/production-eu \
  --method PUT \
  --input - <<EOF
{
  "reviewers": [
    {"type": "User", "id": REVIEWER_ID}
  ],
  "wait_timer": 5
}
EOF
```

### Branch Protection

Enable branch protection on `main` to enforce PR-based workflows:

```bash
gh api repos/{owner}/{repo}/branches/main/protection --method PUT --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null
}
EOF
```

---

## 6. Run Initial Deployment

Deploy all shared packages and org-specific metadata to each org for the first time. Shared packages must be deployed in dependency order: **core → integration → logic**.

### Deploy to the EU Org

```bash
# Step 1: Shared packages (in order)
sf project deploy start --source-dir packages/core --target-org eu-scratch --wait 10
sf project deploy start --source-dir packages/integration --target-org eu-scratch --wait 10
sf project deploy start --source-dir packages/logic --target-org eu-scratch --wait 10

# Step 2: EU-specific metadata
sf project deploy start --source-dir orgs/eu --target-org eu-scratch --wait 10
```

### Deploy to the US Org

```bash
sf project deploy start --source-dir packages/core --target-org us-scratch --wait 10
sf project deploy start --source-dir packages/integration --target-org us-scratch --wait 10
sf project deploy start --source-dir packages/logic --target-org us-scratch --wait 10
sf project deploy start --source-dir orgs/us --target-org us-scratch --wait 10
```

### Deploy to the APAC Org

```bash
sf project deploy start --source-dir packages/core --target-org apac-scratch --wait 10
sf project deploy start --source-dir packages/integration --target-org apac-scratch --wait 10
sf project deploy start --source-dir packages/logic --target-org apac-scratch --wait 10
sf project deploy start --source-dir orgs/apac --target-org apac-scratch --wait 10
```

### Verify Deployments

Check that all components deployed successfully:

```bash
# Quick check — list recently deployed components
sf project deploy report --target-org eu-scratch
sf project deploy report --target-org us-scratch
sf project deploy report --target-org apac-scratch
```

---

## 7. Verify with Smoke Tests

Run the smoke test script against each org to confirm that the deployment is functional.

```bash
# Make the script executable (if not already)
chmod +x scripts/smoke-test.sh

# Run smoke tests for each org
./scripts/smoke-test.sh eu-scratch
./scripts/smoke-test.sh us-scratch
./scripts/smoke-test.sh apac-scratch
```

To run specific test classes only:

```bash
# Run only specific test classes against the EU org
./scripts/smoke-test.sh eu-scratch "GlobalIdServiceTest,EURoutingServiceTest"
```

Expected output for a passing run:

```
[smoke-test] Smoke Test Run
[smoke-test]   Target org    : eu-scratch
[smoke-test]   Test classes  : all local tests
[smoke-test]   Timeout       : 10 minutes
[smoke-test]   Output format : human
========================================================================
[smoke-test] Verifying connectivity to eu-scratch...
[smoke-test] Org is reachable.

[smoke-test] Running all local tests...
Outcome  : Passed
Total    : 12
Passing  : 12
Failing  : 0
Skipped  : 0
Duration : 8423 ms

========================================================================
[smoke-test] RESULT: ALL SMOKE TESTS PASSED
========================================================================
```

---

## 8. Optional: Configure Slack Notifications

Receive deployment notifications in a Slack channel.

### Create a Slack Webhook

1. Go to [Slack API: Incoming Webhooks](https://api.slack.com/messaging/webhooks).
2. Create a new app (or use an existing one) and enable Incoming Webhooks.
3. Add a webhook to the channel where you want deployment notifications.
4. Copy the webhook URL.

### Store the Webhook URL

```bash
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/services/T.../B.../..."
```

### How It Works

The GitHub Actions workflows include optional Slack notification steps that trigger on deployment success or failure. These steps check for the presence of the `SLACK_WEBHOOK_URL` secret and skip gracefully if it is not configured.

Example notification payload (sent automatically by the workflows):

```json
{
  "text": "Deployment to EU completed successfully",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Deployment Complete*\nOrg: EU Sandbox\nPackages: core, integration, logic\nStatus: Success\nCommit: `abc1234`"
      }
    }
  ]
}
```

---

## Troubleshooting

### Auth URL Not Working

If `sf org display --verbose` does not show an `sfdxAuthUrl`, your org may not support it. Try re-authenticating:

```bash
sf org login web --alias eu-scratch
sf org display --target-org eu-scratch --verbose --json
```

### Scratch Org Creation Fails

Ensure your Dev Hub is properly configured and has available scratch org capacity:

```bash
sf org list limits --target-org devhub --json | \
  python3 -c "import sys,json; [print(f\"{l['name']}: {l['remaining']}/{l['max']}\") for l in json.load(sys.stdin)['result'] if 'Scratch' in l['name']]"
```

### Deployment Fails with Dependency Error

Shared packages must be deployed in order. If `integration` fails because it references a `core` class, ensure `core` was deployed first:

```bash
# Always deploy in this order
sf project deploy start --source-dir packages/core --target-org YOUR_ORG --wait 10
sf project deploy start --source-dir packages/integration --target-org YOUR_ORG --wait 10
sf project deploy start --source-dir packages/logic --target-org YOUR_ORG --wait 10
sf project deploy start --source-dir orgs/YOUR_REGION --target-org YOUR_ORG --wait 10
```

### GitHub Actions Workflow Not Triggering

Verify that:
1. The workflow files are on the `main` branch (GitHub only reads workflows from the default branch).
2. The `paths` filters in the workflow match the directories you changed.
3. GitHub Actions is enabled for your repository (**Settings > Actions > General**).

---

## Next Steps

Once the initial setup is complete:

1. **Create a feature branch** and make a small change to test the PR validation workflow.
2. **Merge to main** and verify that the deployment workflows trigger correctly.
3. **Review the architecture docs** — see [ARCHITECTURE.md](ARCHITECTURE.md) and [DECISION-LOG.md](DECISION-LOG.md).
4. **Add your own packages** — extend the `packages/` directory with additional shared packages as your org grows.
5. **Add more orgs** — update `config/org-registry.json`, `config/deployment-order.json`, the `detect-changes.sh` script, and the workflow files to support additional orgs.
