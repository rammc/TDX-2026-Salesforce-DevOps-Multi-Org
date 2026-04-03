#!/usr/bin/env bash
###############################################################################
# smoke-test.sh
#
# Run Apex smoke tests against a target Salesforce org and report results.
#
# Usage:
#   ./scripts/smoke-test.sh <org-alias> [test-classes]
#
# Arguments:
#   org-alias      Required.  The Salesforce CLI alias or username of the org.
#   test-classes   Optional.  Comma-separated list of specific Apex test class
#                  names to run.  When omitted, all local tests are executed.
#
# Examples:
#   ./scripts/smoke-test.sh eu-sandbox
#   ./scripts/smoke-test.sh eu-sandbox "GDPRComplianceHandlerTest,EURoutingTest"
#
# Exit codes:
#   0  All tests passed
#   1  One or more tests failed, or the test run could not be completed
#
# Environment variables:
#   SMOKE_TEST_TIMEOUT   Maximum wait time in minutes (default: 10)
#   SMOKE_TEST_FORMAT    Output format: human | json | junit (default: human)
###############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

TARGET_ORG="${1:?Error: org alias is required.  Usage: smoke-test.sh <org-alias> [test-classes]}"
TEST_CLASSES="${2:-}"
TIMEOUT="${SMOKE_TEST_TIMEOUT:-10}"
FORMAT="${SMOKE_TEST_FORMAT:-human}"

# Temporary directory for test result artifacts.
RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

log() {
  echo "[smoke-test] $*"
}

separator() {
  echo "========================================================================"
}

# Parse the JSON result from 'sf apex run test --json' and print a summary.
# Returns 0 if all tests passed, 1 otherwise.
parse_results() {
  local json_file="$1"

  if [[ ! -s "$json_file" ]]; then
    log "ERROR: Test result file is empty or missing."
    return 1
  fi

  # Extract summary fields using python3 (available on all GitHub-hosted
  # runners and most developer machines).
  local summary
  summary=$(python3 -c "
import json, sys

with open('${json_file}') as f:
    data = json.load(f)

result = data.get('result', {})
summary = result.get('summary', {})

passing   = summary.get('passing', 0)
failing   = summary.get('failing', 0)
skipped   = summary.get('skipped', 0)
total     = summary.get('testsRan', 0)
duration  = summary.get('testExecutionTimeInMs', 0)
outcome   = summary.get('outcome', 'Unknown')

print(f'Outcome  : {outcome}')
print(f'Total    : {total}')
print(f'Passing  : {passing}')
print(f'Failing  : {failing}')
print(f'Skipped  : {skipped}')
print(f'Duration : {duration} ms')

# Print details for any failed test methods
failures = result.get('tests', [])
fail_details = [t for t in failures if t.get('Outcome') == 'Fail']
if fail_details:
    print()
    print('Failed tests:')
    for t in fail_details:
        name = t.get('FullName', t.get('MethodName', 'Unknown'))
        msg  = t.get('Message', 'No message')
        print(f'  FAIL  {name}')
        print(f'        {msg}')

# Exit with non-zero if there were failures
sys.exit(0 if failing == 0 and outcome == 'Passed' else 1)
" 2>&1) || {
    echo "$summary"
    return 1
  }

  echo "$summary"
  return 0
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

separator
log "Smoke Test Run"
log "  Target org    : ${TARGET_ORG}"
log "  Test classes  : ${TEST_CLASSES:-all local tests}"
log "  Timeout       : ${TIMEOUT} minutes"
log "  Output format : ${FORMAT}"
separator
echo ""

# Verify the Salesforce CLI is installed.
if ! command -v sf &>/dev/null; then
  log "ERROR: Salesforce CLI (sf) is not installed or not in PATH."
  exit 1
fi

# Verify org connectivity before running tests.
log "Verifying connectivity to ${TARGET_ORG}..."
if ! sf org display --target-org "$TARGET_ORG" --json >/dev/null 2>&1; then
  log "ERROR: Cannot connect to org '${TARGET_ORG}'.  Check authentication."
  exit 1
fi
log "Org is reachable."
echo ""

# ---------------------------------------------------------------------------
# Build the test command
# ---------------------------------------------------------------------------

# Base command arguments shared by all invocations.
CMD_ARGS=(
  sf apex run test
  --target-org "$TARGET_ORG"
  --wait "$TIMEOUT"
  --result-format "$FORMAT"
  --code-coverage
  --output-dir "$RESULT_DIR"
)

if [[ -n "$TEST_CLASSES" ]]; then
  # Run specific test classes provided by the caller.
  # The --class-names flag accepts a comma-separated list.
  CMD_ARGS+=(--class-names "$TEST_CLASSES")
  log "Running specified test classes: ${TEST_CLASSES}"
else
  # Run all tests that are local to this project (not from managed packages).
  CMD_ARGS+=(--test-level RunLocalTests)
  log "Running all local tests..."
fi

echo ""

# ---------------------------------------------------------------------------
# Execute tests
# ---------------------------------------------------------------------------

# We also capture JSON output for structured parsing, regardless of the
# human-readable format sent to the terminal.
JSON_RESULT="${RESULT_DIR}/test-result.json"

# Run the test command.  We allow it to "fail" (non-zero exit) because we
# want to parse and report results ourselves.
set +e
sf apex run test \
  --target-org "$TARGET_ORG" \
  --wait "$TIMEOUT" \
  --result-format json \
  --code-coverage \
  --output-dir "$RESULT_DIR" \
  ${TEST_CLASSES:+--class-names "$TEST_CLASSES"} \
  ${TEST_CLASSES:---test-level RunLocalTests} \
  > "$JSON_RESULT" 2>&1
TEST_EXIT_CODE=$?
set -e

echo ""
separator
log "Test Results"
separator
echo ""

# ---------------------------------------------------------------------------
# Parse and display results
# ---------------------------------------------------------------------------

PARSE_OK=true
if [[ -s "$JSON_RESULT" ]]; then
  parse_results "$JSON_RESULT" || PARSE_OK=false
else
  # No JSON file — fall back to the raw exit code from sf.
  if [[ $TEST_EXIT_CODE -eq 0 ]]; then
    log "Tests completed successfully (no detailed results available)."
  else
    log "Test run failed with exit code ${TEST_EXIT_CODE}."
    PARSE_OK=false
  fi
fi

echo ""
separator

# ---------------------------------------------------------------------------
# Final verdict
# ---------------------------------------------------------------------------

if $PARSE_OK && [[ $TEST_EXIT_CODE -eq 0 ]]; then
  log "RESULT: ALL SMOKE TESTS PASSED"
  separator
  exit 0
else
  log "RESULT: SMOKE TESTS FAILED"
  separator

  # If JUnit XML was generated, note the path for CI artifact upload.
  JUNIT_FILE=$(find "$RESULT_DIR" -name "*.xml" -print -quit 2>/dev/null || true)
  if [[ -n "$JUNIT_FILE" ]]; then
    log "JUnit results available at: ${JUNIT_FILE}"
  fi

  exit 1
fi
