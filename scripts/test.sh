#!/bin/bash
set -euo pipefail

# =============================================================================
# test.sh — One-command local test runner for Clicky.
#
# Mirrors the unit job in .github/workflows/tests.yml so what passes locally
# also passes in CI. See docs/specs/14-testing-strategy.md for the full
# testing strategy.
#
# Usage:
#   ./scripts/test.sh              # just run the Xcode tests
#   ./scripts/test.sh --worker     # also spawn the local Cloudflare Worker
#                                  # on :8787 for integration tests
#
# Notes:
#   - We deliberately do NOT run `sudo xcodebuild -license accept` or any
#     other interactive command. The developer's machine should already
#     have Xcode set up.
#   - The Cloudflare Worker needs `worker/.dev.vars` to be populated with
#     real or stub API keys. If it isn't there, --worker will still try
#     and the script will fail loudly — wire up .dev.vars first.
# =============================================================================

# Resolve the repo root from this script's location so the script works no
# matter where it's invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

START_WORKER="false"
WORKER_PID=""

for arg in "$@"; do
  case "$arg" in
    --worker)
      START_WORKER="true"
      ;;
    -h|--help)
      cat <<'USAGE'
test.sh — run the Clicky test suite locally.

Options:
  --worker        Spawn the local Cloudflare Worker on :8787 in the
                  background before running tests. Required for any
                  integration test that talks to the Worker.
  -h, --help      Show this help.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      echo "Run \`./scripts/test.sh --help\` for usage." >&2
      exit 2
      ;;
  esac
done

printf '\n'
printf '=============================================================\n'
printf ' Clicky test runner\n'
printf '   repo root  : %s\n' "${REPO_ROOT}"
printf '   local Worker: %s\n' "${START_WORKER}"
printf '=============================================================\n\n'

# Make sure the Worker we spawn here is always killed on exit, even if
# xcodebuild crashes or the user hits ctrl-c.
cleanup_worker() {
  if [ -n "${WORKER_PID}" ]; then
    echo ""
    echo "Stopping local Cloudflare Worker (pid ${WORKER_PID})..."
    kill "${WORKER_PID}" 2>/dev/null || true
  fi
}
trap cleanup_worker EXIT

if [ "${START_WORKER}" = "true" ]; then
  echo "Starting local Cloudflare Worker on :8787..."
  pushd "${REPO_ROOT}/worker" > /dev/null

  # Only run `npm install` if node_modules is missing — keeps re-runs fast.
  if [ ! -d "node_modules" ]; then
    echo "Installing Worker dependencies (one-time)..."
    npm install
  fi

  npx wrangler dev --port 8787 &
  WORKER_PID=$!
  popd > /dev/null

  echo "Waiting for the Worker to respond on http://localhost:8787 ..."
  npx --yes wait-on http://localhost:8787 --timeout 30000
  echo "Worker is up."
  echo ""
fi

echo "Running xcodebuild test ..."
echo ""

# Forward the exit code from xcodebuild so CI / shell pipelines can react.
set +e
xcodebuild test \
  -project "${REPO_ROOT}/leanring-buddy.xcodeproj" \
  -scheme leanring-buddy \
  -destination 'platform=macOS' \
  -resultBundlePath "${REPO_ROOT}/TestResults.xcresult"
TEST_EXIT_CODE=$?
set -e

echo ""
if [ "${TEST_EXIT_CODE}" -eq 0 ]; then
  printf 'Tests passed. Result bundle: %s/TestResults.xcresult\n' "${REPO_ROOT}"
else
  printf 'Tests failed (exit %d). Result bundle: %s/TestResults.xcresult\n' \
    "${TEST_EXIT_CODE}" "${REPO_ROOT}"
fi

exit "${TEST_EXIT_CODE}"
