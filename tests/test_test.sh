#!/usr/bin/env bash
set -euo pipefail

# Test suite for scripts/test.sh
# Uses mock gcloud and grpcurl to verify command invocations without real GCP calls.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_SCRIPT="${REPO_DIR}/scripts/test.sh"

PASS=0
FAIL=0
MOCK_LOG=""

# --- Test helpers ---

setup_mocks() {
  MOCK_DIR=$(mktemp -d)
  MOCK_LOG="${MOCK_DIR}/calls.log"
  touch "${MOCK_LOG}"

  # Mock gcloud
  cat > "${MOCK_DIR}/gcloud" <<MOCK_EOF
#!/usr/bin/env bash
echo "gcloud \$@" >> "${MOCK_LOG}"

case "\$*" in
  *"run services describe"*)
    echo "https://otel-collector-abc123-uc.a.run.app"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCK_EOF
  chmod +x "${MOCK_DIR}/gcloud"

  # Mock grpcurl
  cat > "${MOCK_DIR}/grpcurl" <<MOCK_EOF
#!/usr/bin/env bash
echo "grpcurl \$@" >> "${MOCK_LOG}"
echo "{}"
exit 0
MOCK_EOF
  chmod +x "${MOCK_DIR}/grpcurl"

  export PATH="${MOCK_DIR}:${PATH}"
  export MOCK_DIR
}

cleanup_mock() {
  if [[ -n "${MOCK_DIR:-}" ]]; then
    rm -rf "${MOCK_DIR}"
  fi
}

set_env_vars() {
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
}

unset_env_vars() {
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
  if [[ -x "${TEST_SCRIPT}" ]]; then
    assert_pass "test.sh exists and is executable"
  else
    assert_fail "test.sh exists and is executable" "File missing or not executable"
  fi
}

test_shebang_and_strict_mode() {
  echo "Test: shebang and strict mode"
  local first_line
  first_line=$(head -1 "${TEST_SCRIPT}")
  if [[ "${first_line}" == "#!/usr/bin/env bash" ]]; then
    assert_pass "has correct shebang"
  else
    assert_fail "has correct shebang" "Got: ${first_line}"
  fi

  if grep -q "set -euo pipefail" "${TEST_SCRIPT}"; then
    assert_pass "uses set -euo pipefail"
  else
    assert_fail "uses set -euo pipefail"
  fi
}

test_checks_for_grpcurl() {
  echo "Test: checks for grpcurl"
  if grep -q "command -v grpcurl" "${TEST_SCRIPT}" || grep -q "which grpcurl" "${TEST_SCRIPT}"; then
    assert_pass "checks for grpcurl availability"
  else
    assert_fail "checks for grpcurl availability"
  fi

  if grep -q "brew install grpcurl" "${TEST_SCRIPT}"; then
    assert_pass "prints install instructions for grpcurl"
  else
    assert_fail "prints install instructions for grpcurl"
  fi
}

test_missing_grpcurl_exits() {
  echo "Test: exits if grpcurl is missing"
  unset_env_vars
  set_env_vars

  # Create a mock dir WITHOUT grpcurl
  local no_grpcurl_dir
  no_grpcurl_dir=$(mktemp -d)

  cat > "${no_grpcurl_dir}/gcloud" <<MOCK_EOF
#!/usr/bin/env bash
echo "https://otel-collector-abc123-uc.a.run.app"
exit 0
MOCK_EOF
  chmod +x "${no_grpcurl_dir}/gcloud"

  # Override PATH to exclude grpcurl
  local output
  if output=$(PATH="${no_grpcurl_dir}:/usr/bin:/bin" bash "${TEST_SCRIPT}" 2>&1); then
    assert_fail "exits with non-zero when grpcurl missing" "Script succeeded unexpectedly"
  else
    if echo "${output}" | grep -q "grpcurl"; then
      assert_pass "exits with error mentioning grpcurl"
    else
      assert_fail "exits with error mentioning grpcurl" "Output: ${output}"
    fi
  fi

  rm -rf "${no_grpcurl_dir}"
}

test_missing_project_id_fails() {
  echo "Test: missing PROJECT_ID fails"
  unset_env_vars
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
  setup_mocks

  local output
  if output=$(bash "${TEST_SCRIPT}" 2>&1); then
    assert_fail "fails when PROJECT_ID is missing" "Script succeeded unexpectedly"
  else
    if echo "${output}" | grep -q "PROJECT_ID"; then
      assert_pass "fails with clear error mentioning PROJECT_ID"
    else
      assert_fail "fails with clear error mentioning PROJECT_ID" "Error output: ${output}"
    fi
  fi

  cleanup_mock
}

test_missing_region_fails() {
  echo "Test: missing REGION fails"
  unset_env_vars
  export PROJECT_ID="test-project"
  export SERVICE_NAME="otel-collector"
  setup_mocks

  local output
  if output=$(bash "${TEST_SCRIPT}" 2>&1); then
    assert_fail "fails when REGION is missing" "Script succeeded unexpectedly"
  else
    if echo "${output}" | grep -q "REGION"; then
      assert_pass "fails with clear error mentioning REGION"
    else
      assert_fail "fails with clear error mentioning REGION" "Error output: ${output}"
    fi
  fi

  cleanup_mock
}

test_missing_service_name_fails() {
  echo "Test: missing SERVICE_NAME fails"
  unset_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  setup_mocks

  local output
  if output=$(bash "${TEST_SCRIPT}" 2>&1); then
    assert_fail "fails when SERVICE_NAME is missing" "Script succeeded unexpectedly"
  else
    if echo "${output}" | grep -q "SERVICE_NAME"; then
      assert_pass "fails with clear error mentioning SERVICE_NAME"
    else
      assert_fail "fails with clear error mentioning SERVICE_NAME" "Error output: ${output}"
    fi
  fi

  cleanup_mock
}

test_retrieves_service_url() {
  echo "Test: retrieves service URL dynamically"
  unset_env_vars
  set_env_vars
  setup_mocks

  bash "${TEST_SCRIPT}" > /dev/null 2>&1

  if log_contains "run services describe"; then
    assert_pass "calls gcloud run services describe"
  else
    assert_fail "calls gcloud run services describe"
  fi

  if log_contains "${SERVICE_NAME}" && log_contains "${REGION}" && log_contains "${PROJECT_ID}"; then
    assert_pass "passes SERVICE_NAME, REGION, and PROJECT_ID to gcloud"
  else
    assert_fail "passes SERVICE_NAME, REGION, and PROJECT_ID to gcloud"
  fi

  cleanup_mock
}

test_sends_otlp_metric_via_grpcurl() {
  echo "Test: sends OTLP metric via grpcurl"
  unset_env_vars
  set_env_vars
  setup_mocks

  bash "${TEST_SCRIPT}" > /dev/null 2>&1

  if log_contains "grpcurl"; then
    assert_pass "invokes grpcurl"
  else
    assert_fail "invokes grpcurl"
  fi

  if log_contains "otel-collector-abc123-uc.a.run.app:443"; then
    assert_pass "targets service URL with port 443"
  else
    assert_fail "targets service URL with port 443"
  fi

  if log_contains "opentelemetry.proto.collector.metrics.v1.MetricsService/Export"; then
    assert_pass "calls MetricsService/Export method"
  else
    assert_fail "calls MetricsService/Export method"
  fi

  cleanup_mock
}

test_otlp_payload_structure() {
  echo "Test: OTLP payload has required fields"
  local content
  content=$(cat "${TEST_SCRIPT}")

  if echo "${content}" | grep -q "resource_metrics"; then
    assert_pass "payload contains resource_metrics"
  else
    assert_fail "payload contains resource_metrics"
  fi

  if echo "${content}" | grep -q "service.name"; then
    assert_pass "payload contains service.name attribute"
  else
    assert_fail "payload contains service.name attribute"
  fi

  if echo "${content}" | grep -q "smoke-test"; then
    assert_pass "service.name is smoke-test"
  else
    assert_fail "service.name is smoke-test"
  fi

  if echo "${content}" | grep -q "test.metric"; then
    assert_pass "payload contains test.metric"
  else
    assert_fail "payload contains test.metric"
  fi

  if echo "${content}" | grep -q "gauge"; then
    assert_pass "metric type is gauge"
  else
    assert_fail "metric type is gauge"
  fi

  if echo "${content}" | grep -q "as_int"; then
    assert_pass "data point uses as_int"
  else
    assert_fail "data point uses as_int"
  fi

  if echo "${content}" | grep -q 'time_unix_nano'; then
    assert_pass "data point includes time_unix_nano"
  else
    assert_fail "data point includes time_unix_nano"
  fi

  if echo "${content}" | grep -q 'date +%s'; then
    assert_pass "time_unix_nano uses current epoch"
  else
    assert_fail "time_unix_nano uses current epoch"
  fi
}

test_prints_monitoring_url() {
  echo "Test: prints Cloud Monitoring URL"
  unset_env_vars
  set_env_vars
  setup_mocks

  local output
  output=$(bash "${TEST_SCRIPT}" 2>&1)

  if echo "${output}" | grep -q "console.cloud.google.com/monitoring/metrics-explorer"; then
    assert_pass "prints Cloud Monitoring console URL"
  else
    assert_fail "prints Cloud Monitoring console URL" "Output: ${output}"
  fi

  if echo "${output}" | grep -q "project=test-project"; then
    assert_pass "monitoring URL contains project ID"
  else
    assert_fail "monitoring URL contains project ID" "Output: ${output}"
  fi
}

test_prints_verification_instructions() {
  echo "Test: prints verification instructions"
  unset_env_vars
  set_env_vars
  setup_mocks

  local output
  output=$(bash "${TEST_SCRIPT}" 2>&1)

  if echo "${output}" | grep -q "test_metric"; then
    assert_pass "mentions test_metric for verification"
  else
    assert_fail "mentions test_metric for verification" "Output: ${output}"
  fi
}

test_no_hardcoded_values() {
  echo "Test: no hardcoded project IDs or secrets"
  local content
  content=$(cat "${TEST_SCRIPT}")

  if echo "${content}" | grep -Eq '[a-z]+-[a-z]+-[0-9]{6}'; then
    assert_fail "no hardcoded project IDs" "Found what looks like a hardcoded project ID"
  else
    assert_pass "no hardcoded project IDs"
  fi

  if echo "${content}" | grep -v "^#" | grep -qE "(api[_-]?key|secret|password|token)" 2>/dev/null; then
    assert_fail "no hardcoded secrets" "Found what looks like a hardcoded secret"
  else
    assert_pass "no hardcoded secrets"
  fi
}

# --- Run all tests ---

echo "=== test.sh test suite ==="
echo ""

test_script_exists_and_executable
echo ""
test_shebang_and_strict_mode
echo ""
test_checks_for_grpcurl
echo ""
test_missing_grpcurl_exits
echo ""
test_missing_project_id_fails
echo ""
test_missing_region_fails
echo ""
test_missing_service_name_fails
echo ""
test_retrieves_service_url
echo ""
test_sends_otlp_metric_via_grpcurl
echo ""
test_otlp_payload_structure
echo ""
test_prints_monitoring_url
echo ""
test_prints_verification_instructions
echo ""
test_no_hardcoded_values
echo ""

# --- Summary ---

TOTAL=$((PASS + FAIL))
echo "=== Results: ${PASS}/${TOTAL} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
