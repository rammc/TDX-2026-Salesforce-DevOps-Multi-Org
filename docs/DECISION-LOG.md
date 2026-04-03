# Decision Log — Architecture Decision Records (ADRs)

This document records the key architectural decisions made for the multi-org DevOps blueprint. Each decision follows a lightweight ADR format to capture context, rationale, and consequences.

---

## Table of Contents

- [ADR-001: Monorepo over Multi-Repo](#adr-001-monorepo-over-multi-repo)
- [ADR-002: Trunk-Based Development for Shared Packages](#adr-002-trunk-based-development-for-shared-packages)
- [ADR-003: Path-Based CI Triggers over Org-Specific Branches](#adr-003-path-based-ci-triggers-over-org-specific-branches)
- [ADR-004: GitHub Actions over Jenkins or Azure DevOps](#adr-004-github-actions-over-jenkins-or-azure-devops)
- [ADR-005: Custom Metadata Types for Org-Specific Configuration](#adr-005-custom-metadata-types-for-org-specific-configuration)

---

## ADR-001: Monorepo over Multi-Repo

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-01-15 |

### Context

We manage three Salesforce orgs (EU, US, APAC) that share approximately 60-70% of their metadata. The remaining 30-40% consists of region-specific customizations driven by compliance requirements (GDPR in EU), market differences, and localized business processes.

We needed to decide between:

1. **Multi-repo** — one repository per org, with shared code copied or synced via submodules.
2. **Monorepo** — a single repository containing shared packages and org-specific directories.

### Decision

We chose a **monorepo** (federated model) with a clear separation between shared packages (`packages/`) and org-specific overrides (`orgs/`).

### Rationale

- **Single source of truth.** Shared business logic exists in exactly one place. Bug fixes and improvements propagate to all orgs through a single pull request, eliminating the need to open and synchronize multiple PRs across repos.
- **Atomic cross-cutting changes.** When a change to the data model (Core) requires a corresponding change to a service class (Logic) and an EU-specific layout, all three changes are committed, reviewed, and deployed together.
- **Simplified dependency management.** The dependency chain `core → integration → logic → org-specific` is enforced structurally through directory conventions and `deployment-order.json`, rather than through error-prone submodule pinning.
- **Easier onboarding.** New developers clone one repository and can see the full picture — shared code, org overrides, and CI/CD pipelines — without navigating between repos.
- **Path-based CI.** GitHub Actions supports path-based triggers natively, allowing us to run only the relevant validation/deployment steps when specific directories change.

### Consequences

- **Larger repository.** The repo contains metadata for all orgs. Sparse checkouts or shallow clones may be needed for very large orgs.
- **Shared CI minutes.** A change to shared packages triggers validation across all orgs, consuming more CI minutes than a single-org repo would.
- **Access control.** Fine-grained permissions on subdirectories require GitHub CODEOWNERS rather than repo-level access control. Teams must be disciplined about code ownership boundaries.
- **Merge contention.** High-traffic shared packages may see more merge conflicts. Trunk-based development (see ADR-002) mitigates this.

---

## ADR-002: Trunk-Based Development for Shared Packages

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-01-20 |

### Context

We needed a branching strategy that supports both shared package development (where changes affect all orgs) and org-specific work (where changes affect only one org). Common options include:

1. **GitFlow** — long-lived `develop`, `release/*`, and `hotfix/*` branches with periodic merges to `main`.
2. **Trunk-based development** — short-lived feature branches merged directly to `main`, with all deployments triggered from `main`.
3. **Branch-per-org** — a long-lived branch for each org (e.g., `eu`, `us`, `apac`) with cherry-picks or merges for shared code.

### Decision

We adopted **trunk-based development** with `main` as the single integration branch. All changes — whether to shared packages or org-specific metadata — are developed on short-lived feature branches and merged to `main` via pull requests.

### Rationale

- **Reduced merge complexity.** GitFlow's long-lived branches accumulate drift and create painful merge conflicts, especially when three orgs are involved. Trunk-based development keeps the integration window short.
- **Continuous deployment readiness.** Every merge to `main` is a deployable unit. The path-based detection script determines which orgs and packages to deploy, making `main` the single source of deployment truth.
- **No branch-per-org drift.** Branch-per-org strategies inevitably diverge. Shared bug fixes must be cherry-picked to every org branch, and forgotten cherry-picks cause silent inconsistencies. Our directory-based separation eliminates this entirely.
- **Simpler mental model.** Developers always branch from `main` and merge back to `main`. There is no question about which branch to target.

**When to use feature branches:**
- Always — but keep them short-lived (ideally < 1 day of work).
- Name them descriptively: `feature/gdpr-consent-update`, `fix/apac-routing-bug`.
- Do not create long-lived branches for org-specific streams.

### Consequences

- **Feature flags may be needed.** Large features that span multiple PRs require Custom Metadata Type-based feature flags to hide incomplete work from production.
- **PR discipline is critical.** Every PR to `main` must pass validation. Branch protection rules enforce this.
- **Rollback strategy required.** Since `main` is always deployable, a broken merge needs fast revert-and-redeploy capability. The smoke test script provides a safety net.

---

## ADR-003: Path-Based CI Triggers over Org-Specific Branches

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-01-22 |

### Context

In a monorepo containing shared packages and three org directories, we need CI/CD to be efficient. Running full validation and deployment for every org on every commit is wasteful. We considered two approaches:

1. **Org-specific branches** — a `deploy/eu`, `deploy/us`, `deploy/apac` branch for each org, with merges from `main` triggering org-specific pipelines.
2. **Path-based triggers** — a single `main` branch with CI/CD workflows that use `paths:` filters and a change detection script to determine which packages/orgs are affected.

### Decision

We chose **path-based CI triggers** combined with the `detect-changes.sh` script that analyzes `git diff` output and maps changed files to affected packages and orgs.

### Rationale

- **No branch synchronization overhead.** Org-specific branches must be kept in sync with `main`, creating maintenance overhead and a risk of drift. Path-based triggers eliminate this entirely.
- **Atomic deployments.** A single merge to `main` can trigger both shared package deployments and org-specific deployments in one coordinated pipeline run.
- **Fine-grained control.** The detection script can distinguish between changes to `packages/core/` (deploy to all orgs) and `orgs/eu/` (deploy to EU only), enabling minimal-blast-radius deployments.
- **Native GitHub Actions support.** The `on.push.paths` and `on.pull_request.paths` filters integrate directly with GitHub's event system, and the detection script provides additional granularity within a workflow.
- **Audit trail.** Every deployment is traceable to a specific commit on `main` and a specific workflow run, regardless of which orgs were affected.

### Consequences

- **Custom scripting required.** The `detect-changes.sh` script is a critical piece of infrastructure that must be maintained and tested. A bug in detection could skip necessary deployments or trigger unnecessary ones.
- **All-or-nothing for shared packages.** When `sfdx-project.json` or `.github/` files change, the detection script conservatively flags all packages and orgs, which may trigger more deployments than strictly necessary.
- **Workflow complexity.** Path-based logic inside workflow YAML files (via matrix strategies and conditional steps) is more complex than simple branch-triggered pipelines.

---

## ADR-004: GitHub Actions over Jenkins or Azure DevOps

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-02-01 |

### Context

We evaluated three CI/CD platforms for this blueprint:

1. **Jenkins** — self-hosted, highly customizable, plugin-based.
2. **Azure DevOps Pipelines** — cloud-hosted, strong enterprise features, YAML-based.
3. **GitHub Actions** — cloud-hosted, native GitHub integration, YAML-based, marketplace.

### Decision

We chose **GitHub Actions** as the CI/CD platform for this blueprint.

### Rationale

- **Native GitHub integration.** Since the repository is hosted on GitHub, Actions provides zero-configuration integration with pull requests, branch protection, environments, and secrets. PR checks, deployment gates, and status badges work out of the box.
- **Workflow-as-code.** Workflow definitions live in `.github/workflows/` inside the repository, versioned alongside the code they deploy. There is no external pipeline configuration to manage or synchronize.
- **Path-based triggers.** GitHub Actions natively supports `on.push.paths` and `on.pull_request.paths` filters, which are central to our change detection strategy (ADR-003).
- **Environments and approval gates.** GitHub Environments allow us to define `eu-sandbox`, `production-eu`, etc., with required reviewers and wait timers — without third-party plugins.
- **Community actions.** The GitHub Marketplace provides well-maintained actions for Salesforce CLI installation, SFDX auth URL handling, Slack notifications, and more.
- **Portability.** While this blueprint uses GitHub Actions, the core scripts (`detect-changes.sh`, `smoke-test.sh`) are platform-agnostic bash scripts. Migrating to another CI/CD platform requires only rewriting the workflow YAML files, not the underlying logic.

### Consequences

- **GitHub lock-in for workflow syntax.** The `.github/workflows/*.yml` files are GitHub-specific. However, the detection and deployment logic lives in portable shell scripts.
- **Runner minutes.** GitHub-hosted runners have usage limits on free and team plans. Large organizations may need self-hosted runners or larger GitHub Enterprise plans.
- **Limited built-in artifact management.** Unlike Azure DevOps, GitHub Actions does not have a built-in artifact feed. We rely on workflow artifacts and the deployment history for traceability.
- **Concurrent job limits.** Free plans allow limited concurrent jobs. Fan-out deployments to three orgs may queue during peak usage.

---

## ADR-005: Custom Metadata Types for Org-Specific Configuration

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-02-10 |

### Context

Shared packages need to behave differently across orgs. For example, the routing service must direct cases to region-specific queues, and compliance handlers must be enabled/disabled based on the org's regulatory environment. We considered three mechanisms for org-specific configuration:

1. **Environment variables / Named Credentials** — external configuration injected at deploy time or runtime.
2. **Custom Settings** — Salesforce-native, hierarchy or list-based, editable via UI or API.
3. **Custom Metadata Types (CMDT)** — Salesforce-native, deployable as metadata, version-controlled, available in declarative tools (formulas, validation rules, flows).

### Decision

We chose **Custom Metadata Types** as the primary mechanism for org-specific configuration within shared packages.

### Rationale

- **Deployable as metadata.** CMDT records are metadata, not data. They can be version-controlled in the repository, deployed through CI/CD, and treated identically to other Salesforce metadata. This aligns perfectly with our source-driven approach.
- **Available in declarative contexts.** Unlike Custom Settings, CMDT records can be referenced in formula fields, validation rules, and flows without Apex code. This makes them accessible to admins and declarative developers.
- **No SOQL governor limits.** CMDT queries (`[SELECT ... FROM MyConfig__mdt]`) do not count against SOQL query limits, making them safe to use in trigger contexts and batch operations.
- **Test isolation.** CMDT records are visible in test contexts without `@SeeAllData=true`, simplifying test setup and improving test reliability.
- **Natural fit for the federated model.** Shared packages define the CMDT object (in `packages/core/`), and each org provides its own records (in `orgs/{region}/`). This cleanly separates the schema from the configuration values.

**Example pattern:**
```
packages/core/objects/OrgConfig__mdt/          ← CMDT object definition (shared)
packages/core/objects/OrgConfig__mdt/fields/   ← Field definitions (shared)
orgs/eu/customMetadata/OrgConfig.EU.md-meta.xml   ← EU-specific record
orgs/us/customMetadata/OrgConfig.US.md-meta.xml   ← US-specific record
orgs/apac/customMetadata/OrgConfig.APAC.md-meta.xml ← APAC-specific record
```

### Consequences

- **Cannot be modified at runtime via UI.** CMDT records are metadata and are deployed, not edited in production via the Setup UI (unless using the Metadata API). For configuration that admins need to change frequently without a deployment, Custom Settings or Custom Permissions may be more appropriate.
- **Schema changes require deployment.** Adding a new field to the CMDT object requires a deployment to all orgs (since the object lives in a shared package). This is by design but adds coordination overhead.
- **Limited data types.** CMDT supports fewer field types than Custom Objects (e.g., no lookup to standard objects, no roll-up summaries). Complex configuration may require multiple CMDT objects.
- **Mixed approach may be needed.** Some configuration (e.g., API endpoints, credentials) is better handled through Named Credentials or Custom Settings. CMDT is the default choice, but not the only tool.

---

## Template for Future ADRs

```markdown
## ADR-NNN: [Title]

| Field | Value |
|-------|-------|
| **Status** | Proposed / Accepted / Deprecated / Superseded |
| **Date** | YYYY-MM-DD |

### Context
[What is the issue that we're seeing that is motivating this decision?]

### Decision
[What is the change that we're proposing and/or doing?]

### Rationale
[Why is this the best choice among the alternatives considered?]

### Consequences
[What becomes easier or harder as a result of this decision?]
```
