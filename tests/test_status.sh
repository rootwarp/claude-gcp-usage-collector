#!/usr/bin/env bash
set -euo pipefail

# Test suite for scripts/status.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATUS_SCRIPT="${REPO_DIR}/scripts/status.sh"

PASS=0
FAIL=0
MOCK_LOG=""

# --- Test helpers ---

setup_mock_gcloud() {
  MOCK_DIR=$(mktemp -d)
  MOCK_LOG="${MOCK_DIR}/gcloud_calls.log"
  touch "${MOCK_LOG}"

  cat > "${MOCK_DIR}/gcloud" <<MOCK_EOF
#!/usr/bin/env bash
echo "\$@" >> "${MOCK_LOG}"
case "\$*" in
  *"run services describe"*)
    echo "URL                                     STATUS  CONCURRENCY  MIN  MAX"
    echo "https://otel-collector-abc-uc.a.run.app True    80           0    2"
    exit 0
    ;;
  *"run revisions list"*)
    echo "REVISION                  STATUS  IMAGE"
    echo "otel-collector-00001-abc  True    gcr.io/test-project/otel-collector"
    exit 0
    ;;
  *) exit 0 ;;
esac
MOCK_EOF

  chmod +x "${MOCK_DIR}/gcloud"
  export PATH="${MOCK_DIR}:${PATH}"
  export MOCK_DIR
}

cleanup_mock() {
  if [[ -n "${MOCK_DIR:-}" ]]; then
    rm -rf "${MOCK_DIR}"
  fi
}

set_all_env_vars() {
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
}

unset_all_env_vars() {
  unset PROJECT_ID REGION SERVICE_NAME 2>/dev/null || true
}

assert_pass() {
  local test_name="$1"
  echo "  PASS: ${test_name}"
  PASS=$((PASS + 1))
}

assert_fail() {
  local test_name="$1"
  local detail="${2:-}"
  echo "  FAIL: ${test_name}"
  if [[ -n "${detail}" ]]; then
    echo "        ${detail}"
  fi
  FAIL=$((FAIL + 1))
}

log_contains() {
  grep -qF -- "$1" "${MOCK_LOG}"
}

# --- Tests ---

test_script_exists_and_executable() {
  echo "Test: script exists and is executable"
  if [[ -x "${STATUS_SCRIPT}" ]]; then
    assert_pass "status.sh exists and is executable"
  else
    assert_fail "status.sh exists and is executable"
  fi
}

test_shebang_and_strict_mode() {
  echo "Test: shebang and strict mode"
  local first_line
  first_line=$(head -1 "${STATUS_SCRIPT}")
  if [[ "${first_line}" == "#!/usr/bin/env bash" ]]; then
    assert_pass "has correct shebang"
  else
    assert_fail "has correct shebang" "Got: ${first_line}"
  fi

  if grep -q "set -euo pipefail" "${STATUS_SCRIPT}"; then
    assert_pass "uses set -euo pipefail"
  else
    assert_fail "uses set -euo pipefail"
  fi
}

test_missing_project_id_fails() {
  echo "Test: missing PROJECT_ID fails"
  unset_all_env_vars
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"

  local output
  if output=$(bash "${STATUS_SCRIPT}" 2>&1); then
    assert_fail "fails when PROJECT_ID is missing"
  else
    if echo "${output}" | grep -q "PROJECT_ID"; then
      assert_pass "fails with clear error mentioning PROJECT_ID"
    else
      assert_fail "fails with clear error mentioning PROJECT_ID"
    fi
  fi
}

test_missing_region_fails() {
  echo "Test: missing REGION fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export SERVICE_NAME="otel-collector"

  local output
  if output=$(bash "${STATUS_SCRIPT}" 2>&1); then
    assert_fail "fails when REGION is missing"
  else
    if echo "${output}" | grep -q "REGION"; then
      assert_pass "fails with clear error mentioning REGION"
    else
      assert_fail "fails with clear error mentioning REGION"
    fi
  fi
}

test_missing_service_name_fails() {
  echo "Test: missing SERVICE_NAME fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"

  local output
  if output=$(bash "${STATUS_SCRIPT}" 2>&1); then
    assert_fail "fails when SERVICE_NAME is missing"
  else
    if echo "${output}" | grep -q "SERVICE_NAME"; then
      assert_pass "fails with clear error mentioning SERVICE_NAME"
    else
      assert_fail "fails with clear error mentioning SERVICE_NAME"
    fi
  fi
}

test_describes_service() {
  echo "Test: describes Cloud Run service"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${STATUS_SCRIPT}" > /dev/null 2>&1

  if log_contains "run services describe otel-collector"; then
    assert_pass "calls gcloud run services describe"
  else
    assert_fail "calls gcloud run services describe"
  fi

  if log_contains "--region us-central1" && log_contains "--project test-project"; then
    assert_pass "passes correct region and project"
  else
    assert_fail "passes correct region and project"
  fi

  cleanup_mock
}

test_lists_revisions() {
  echo "Test: lists active revisions"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${STATUS_SCRIPT}" > /dev/null 2>&1

  if log_contains "run revisions list"; then
    assert_pass "calls gcloud run revisions list"
  else
    assert_fail "calls gcloud run revisions list"
  fi

  if log_contains "--service otel-collector"; then
    assert_pass "filters revisions by service name"
  else
    assert_fail "filters revisions by service name"
  fi

  cleanup_mock
}

test_output_has_sections() {
  echo "Test: output has service and revisions sections"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  local output
  output=$(bash "${STATUS_SCRIPT}" 2>&1)

  if echo "${output}" | grep -q "Cloud Run Service"; then
    assert_pass "output contains Cloud Run Service section"
  else
    assert_fail "output contains Cloud Run Service section"
  fi

  if echo "${output}" | grep -q "Active Revisions"; then
    assert_pass "output contains Active Revisions section"
  else
    assert_fail "output contains Active Revisions section"
  fi

  cleanup_mock
}

# --- Run all tests ---

echo "=== status.sh test suite ==="
echo ""

test_script_exists_and_executable
echo ""
test_shebang_and_strict_mode
echo ""
test_missing_project_id_fails
echo ""
test_missing_region_fails
echo ""
test_missing_service_name_fails
echo ""
test_describes_service
echo ""
test_lists_revisions
echo ""
test_output_has_sections
echo ""

# --- Summary ---

TOTAL=$((PASS + FAIL))
echo "=== Results: ${PASS}/${TOTAL} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
