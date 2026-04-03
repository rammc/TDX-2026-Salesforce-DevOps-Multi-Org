#!/usr/bin/env bash
###############################################################################
# detect-changes.sh
#
# Compare HEAD with the merge base to determine which packages and orgs have
# changed.  Outputs a single JSON object to stdout so downstream CI steps can
# consume it directly (e.g. via jq, GitHub Actions fromJson, or GITHUB_OUTPUT).
#
# Usage:
#   ./scripts/detect-changes.sh [base-ref]
#
# Arguments:
#   base-ref   Branch or ref to compare against.  Defaults to origin/main.
#
# Output (stdout — one-line JSON):
#   {
#     "shared_changed": true|false,
#     "affected_packages": ["core","integration","logic"],
#     "affected_orgs": ["eu","us","apac"]
#   }
#
# Exit codes:
#   0  Success (even when nothing changed — the JSON reflects that)
#   1  Unexpected error
#
# Design notes:
#   - All informational/debug messages are written to stderr so stdout remains
#     clean, parseable JSON.
#   - The script handles three edge cases explicitly:
#       1. No changes detected  → empty arrays, shared_changed=false
#       2. Initial commit (no merge base) → treat every tracked file as changed
#       3. Shared config changed → flag ALL packages and ALL orgs as affected
###############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Base reference for the diff.  Override via the first positional argument.
BASE_REF="${1:-origin/main}"

# Shared package directory prefixes.  Keys become the identifiers in the JSON.
# Order is irrelevant here; deployment-order.json governs sequencing.
declare -A PACKAGE_DIRS=(
  ["core"]="packages/core/"
  ["integration"]="packages/integration/"
  ["logic"]="packages/logic/"
)

# Org-specific directory prefixes.
declare -A ORG_DIRS=(
  ["eu"]="orgs/eu/"
  ["us"]="orgs/us/"
  ["apac"]="orgs/apac/"
)

# Paths whose changes affect the ENTIRE project.  If any file under these
# prefixes changes, every package and every org is considered affected.
SHARED_PATHS=(
  "sfdx-project.json"
  "config/"
  "scripts/"
  ".github/"
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Log to stderr so stdout remains clean JSON.
log() {
  echo "[detect-changes] $*" >&2
}

# Convert a bash array of strings into a JSON array string.
# Usage: to_json_array "core" "logic"  →  ["core","logic"]
to_json_array() {
  local items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then
    echo "[]"
    return
  fi
  local json="["
  local first=true
  for item in "${items[@]}"; do
    if $first; then
      first=false
    else
      json+=","
    fi
    json+="\"${item}\""
  done
  json+="]"
  echo "$json"
}

# Emit the final JSON object to stdout and, when running inside GitHub
# Actions, also write individual values to GITHUB_OUTPUT.
emit_result() {
  local shared="$1"
  local packages="$2"
  local orgs="$3"

  # Primary output: one-line JSON to stdout
  echo "{\"shared_changed\": ${shared}, \"affected_packages\": ${packages}, \"affected_orgs\": ${orgs}}"

  # Secondary output: GitHub Actions step outputs (when available)
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "shared_changed=${shared}"
      echo "affected_packages=${packages}"
      echo "affected_orgs=${orgs}"
    } >> "$GITHUB_OUTPUT"
    log "Wrote results to GITHUB_OUTPUT."
  fi
}

# ---------------------------------------------------------------------------
# Step 1 — Ensure remote refs are available
# ---------------------------------------------------------------------------

# In CI shallow clones the remote tracking branch may not exist locally yet.
if git remote | grep -q origin 2>/dev/null; then
  git fetch origin --quiet 2>/dev/null || log "Warning: git fetch failed — continuing with local refs"
fi

# ---------------------------------------------------------------------------
# Step 2 — Determine changed files
# ---------------------------------------------------------------------------

CHANGED_FILES=""

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  # Repository is completely empty — nothing to compare.
  log "HEAD does not exist (empty repository).  No changes detected."
  emit_result "false" "[]" "[]"
  exit 0
fi

if ! MERGE_BASE=$(git merge-base HEAD "$BASE_REF" 2>/dev/null); then
  # No common ancestor found.  This typically happens on the very first
  # commit or when the base ref does not exist.  Fall back to listing every
  # tracked file so the first pipeline run validates everything.
  log "No merge base found with ${BASE_REF} (initial commit?).  Treating ALL tracked files as changed."
  CHANGED_FILES=$(git ls-tree -r --name-only HEAD 2>/dev/null || true)
else
  log "Merge base: ${MERGE_BASE:0:12} (HEAD vs ${BASE_REF})"
  # Use two-dot diff (MERGE_BASE..HEAD) to capture exactly the commits on
  # this branch that are not yet on the base ref.
  CHANGED_FILES=$(git diff --name-only "$MERGE_BASE" HEAD 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# Step 3 — Handle "no changes" edge case
# ---------------------------------------------------------------------------

if [[ -z "$CHANGED_FILES" ]]; then
  log "No changed files detected."
  emit_result "false" "[]" "[]"
  exit 0
fi

# Print changed file list to stderr for debugging.
FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
log "${FILE_COUNT} file(s) changed:"
echo "$CHANGED_FILES" | while IFS= read -r f; do log "  $f"; done

# ---------------------------------------------------------------------------
# Step 4 — Classify each changed file
# ---------------------------------------------------------------------------

SHARED_CHANGED=false
declare -A PKG_HIT=()
declare -A ORG_HIT=()

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Check shared / global paths first.
  for sp in "${SHARED_PATHS[@]}"; do
    if [[ "$file" == "${sp}"* ]]; then
      SHARED_CHANGED=true
      break
    fi
  done

  # Check package directories.
  for pkg in "${!PACKAGE_DIRS[@]}"; do
    if [[ "$file" == "${PACKAGE_DIRS[$pkg]}"* ]]; then
      PKG_HIT[$pkg]=1
    fi
  done

  # Check org directories.
  for org in "${!ORG_DIRS[@]}"; do
    if [[ "$file" == "${ORG_DIRS[$org]}"* ]]; then
      ORG_HIT[$org]=1
    fi
  done
done <<< "$CHANGED_FILES"

# ---------------------------------------------------------------------------
# Step 5 — If shared config changed, flag everything
# ---------------------------------------------------------------------------

if $SHARED_CHANGED; then
  log "Shared configuration changed — marking ALL packages and orgs as affected."
  for pkg in "${!PACKAGE_DIRS[@]}"; do PKG_HIT[$pkg]=1; done
  for org in "${!ORG_DIRS[@]}"; do ORG_HIT[$org]=1; done
fi

# ---------------------------------------------------------------------------
# Step 6 — Build sorted result arrays (deterministic output)
# ---------------------------------------------------------------------------

AFFECTED_PKGS=()
for pkg in $(echo "${!PKG_HIT[@]}" | tr ' ' '\n' | sort); do
  AFFECTED_PKGS+=("$pkg")
done

AFFECTED_ORGS=()
for org in $(echo "${!ORG_HIT[@]}" | tr ' ' '\n' | sort); do
  AFFECTED_ORGS+=("$org")
done

# ---------------------------------------------------------------------------
# Step 7 — Emit results
# ---------------------------------------------------------------------------

log "Summary:"
log "  shared_changed  : $SHARED_CHANGED"
log "  affected_packages: ${AFFECTED_PKGS[*]:-none}"
log "  affected_orgs    : ${AFFECTED_ORGS[*]:-none}"

emit_result \
  "$SHARED_CHANGED" \
  "$(to_json_array "${AFFECTED_PKGS[@]}")" \
  "$(to_json_array "${AFFECTED_ORGS[@]}")"
