#!/usr/bin/env bash
set -euo pipefail

# Test suite for scripts/deploy.sh
# Uses a mock gcloud to verify command invocations without real GCP calls.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY_SCRIPT="${REPO_DIR}/scripts/deploy.sh"

PASS=0
FAIL=0
MOCK_LOG=""

# --- Test helpers ---

setup_mock_gcloud() {
  MOCK_DIR=$(mktemp -d)
  MOCK_LOG="${MOCK_DIR}/gcloud_calls.log"
  touch "${MOCK_LOG}"

  cat > "${MOCK_DIR}/gcloud" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "$@" >> "{{MOCK_LOG}}"

# Handle specific commands
case "$*" in
  *"iam service-accounts describe"*)
    if [[ "${MOCK_SA_EXISTS:-false}" == "true" ]]; then
      exit 0
    else
      exit 1
    fi
    ;;
  *"run services describe"*)
    echo "https://otel-collector-abc123-uc.a.run.app"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
MOCK_EOF

  # Replace placeholder with actual log path
  sed -i '' "s|{{MOCK_LOG}}|${MOCK_LOG}|g" "${MOCK_DIR}/gcloud"
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
  export SA_NAME="otel-collector"
  export SA_EMAIL="otel-collector@test-project.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test-project/otel-collector"
}

unset_all_env_vars() {
  unset PROJECT_ID REGION SERVICE_NAME SA_NAME SA_EMAIL IMAGE_TAG 2>/dev/null || true
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
  if [[ -x "${DEPLOY_SCRIPT}" ]]; then
    assert_pass "deploy.sh exists and is executable"
  else
    assert_fail "deploy.sh exists and is executable" "File missing or not executable"
  fi
}

test_shebang_and_strict_mode() {
  echo "Test: shebang and strict mode"
  local first_line
  first_line=$(head -1 "${DEPLOY_SCRIPT}")
  if [[ "${first_line}" == "#!/usr/bin/env bash" ]]; then
    assert_pass "has correct shebang"
  else
    assert_fail "has correct shebang" "Got: ${first_line}"
  fi

  if grep -q "set -euo pipefail" "${DEPLOY_SCRIPT}"; then
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
  export SA_NAME="otel-collector"
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DEPLOY_SCRIPT}" 2>&1); then
    assert_fail "fails when PROJECT_ID is missing" "Script succeeded unexpectedly"
  else
    if echo "${output}" | grep -q "PROJECT_ID"; then
      assert_pass "fails with clear error mentioning PROJECT_ID"
    else
      assert_fail "fails with clear error mentioning PROJECT_ID" "Error output: ${output}"
    fi
  fi
}

test_missing_region_fails() {
  echo "Test: missing REGION fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export SERVICE_NAME="otel-collector"
  export SA_NAME="otel-collector"
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DEPLOY_SCRIPT}" 2>&1); then
    assert_fail "fails when REGION is missing" "Script succeeded unexpectedly"
  else
    if echo "${output}" | grep -q "REGION"; then
      assert_pass "fails with clear error mentioning REGION"
    else
      assert_fail "fails with clear error mentioning REGION" "Error output: ${output}"
    fi
  fi
}

test_missing_service_name_fails() {
  echo "Test: missing SERVICE_NAME fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SA_NAME="otel-collector"
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DEPLOY_SCRIPT}" 2>&1); then
    assert_fail "fails when SERVICE_NAME is missing"
  else
    if echo "${output}" | grep -q "SERVICE_NAME"; then
      assert_pass "fails with clear error mentioning SERVICE_NAME"
    else
      assert_fail "fails with clear error mentioning SERVICE_NAME" "Error output: ${output}"
    fi
  fi
}

test_missing_sa_name_fails() {
  echo "Test: missing SA_NAME fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DEPLOY_SCRIPT}" 2>&1); then
    assert_fail "fails when SA_NAME is missing"
  else
    if echo "${output}" | grep -q "SA_NAME"; then
      assert_pass "fails with clear error mentioning SA_NAME"
    else
      assert_fail "fails with clear error mentioning SA_NAME" "Error output: ${output}"
    fi
  fi
}

test_missing_sa_email_fails() {
  echo "Test: missing SA_EMAIL fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
  export SA_NAME="otel-collector"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DEPLOY_SCRIPT}" 2>&1); then
    assert_fail "fails when SA_EMAIL is missing"
  else
    if echo "${output}" | grep -q "SA_EMAIL"; then
      assert_pass "fails with clear error mentioning SA_EMAIL"
    else
      assert_fail "fails with clear error mentioning SA_EMAIL" "Error output: ${output}"
    fi
  fi
}

test_missing_image_tag_fails() {
  echo "Test: missing IMAGE_TAG fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
  export SA_NAME="otel-collector"
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"

  local output
  if output=$(bash "${DEPLOY_SCRIPT}" 2>&1); then
    assert_fail "fails when IMAGE_TAG is missing"
  else
    if echo "${output}" | grep -q "IMAGE_TAG"; then
      assert_pass "fails with clear error mentioning IMAGE_TAG"
    else
      assert_fail "fails with clear error mentioning IMAGE_TAG" "Error output: ${output}"
    fi
  fi
}

test_enables_required_apis() {
  echo "Test: enables required APIs"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DEPLOY_SCRIPT}" > /dev/null 2>&1

  if log_contains "services enable"; then
    assert_pass "calls gcloud services enable"
  else
    assert_fail "calls gcloud services enable"
  fi

  if log_contains "run.googleapis.com" && log_contains "monitoring.googleapis.com" && log_contains "cloudbuild.googleapis.com"; then
    assert_pass "enables all three required APIs"
  else
    assert_fail "enables all three required APIs"
  fi

  cleanup_mock
}

test_creates_service_account_when_missing() {
  echo "Test: creates service account when missing"
  unset_all_env_vars
  set_all_env_vars
  export MOCK_SA_EXISTS="false"
  setup_mock_gcloud

  bash "${DEPLOY_SCRIPT}" > /dev/null 2>&1

  if log_contains "iam service-accounts create"; then
    assert_pass "creates service account when it doesn't exist"
  else
    assert_fail "creates service account when it doesn't exist"
  fi

  cleanup_mock
}

test_skips_service_account_when_exists() {
  echo "Test: skips service account creation when exists"
  unset_all_env_vars
  set_all_env_vars
  export MOCK_SA_EXISTS="true"
  setup_mock_gcloud

  bash "${DEPLOY_SCRIPT}" > /dev/null 2>&1

  if log_contains "iam service-accounts create"; then
    assert_fail "should skip service account creation when it exists"
  else
    assert_pass "skips service account creation when it exists"
  fi

  cleanup_mock
}

test_grants_iam_role() {
  echo "Test: grants IAM role"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DEPLOY_SCRIPT}" > /dev/null 2>&1

  if log_contains "add-iam-policy-binding" && log_contains "roles/monitoring.metricWriter"; then
    assert_pass "grants monitoring.metricWriter role"
  else
    assert_fail "grants monitoring.metricWriter role"
  fi

  if log_contains "--condition=None" && log_contains "--quiet"; then
    assert_pass "uses --condition=None --quiet flags"
  else
    assert_fail "uses --condition=None --quiet flags"
  fi

  cleanup_mock
}

test_builds_image() {
  echo "Test: builds image"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DEPLOY_SCRIPT}" > /dev/null 2>&1

  if log_contains "builds submit" && log_contains "gcr.io/test-project/otel-collector"; then
    assert_pass "builds image with correct tag"
  else
    assert_fail "builds image with correct tag"
  fi

  cleanup_mock
}

test_deploys_cloud_run() {
  echo "Test: deploys to Cloud Run with correct flags"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DEPLOY_SCRIPT}" > /dev/null 2>&1

  if log_contains "run deploy otel-collector"; then
    assert_pass "deploys Cloud Run service"
  else
    assert_fail "deploys Cloud Run service"
  fi

  if log_contains "--port 4317"; then
    assert_pass "uses --port 4317"
  else
    assert_fail "uses --port 4317"
  fi

  if log_contains "--use-http2"; then
    assert_pass "uses --use-http2 for gRPC"
  else
    assert_fail "uses --use-http2 for gRPC"
  fi

  if log_contains "--memory 512Mi" && log_contains "--cpu 1"; then
    assert_pass "sets memory and CPU"
  else
    assert_fail "sets memory and CPU"
  fi

  if log_contains "--min-instances 0" && log_contains "--max-instances 2"; then
    assert_pass "sets min/max instances"
  else
    assert_fail "sets min/max instances"
  fi

  if log_contains "--allow-unauthenticated"; then
    assert_pass "allows unauthenticated access"
  else
    assert_fail "allows unauthenticated access"
  fi

  if log_contains "--service-account otel-collector@test-project.iam.gserviceaccount.com"; then
    assert_pass "sets service account"
  else
    assert_fail "sets service account"
  fi

  if log_contains "GOOGLE_CLOUD_PROJECT=test-project" && log_contains "GOOGLE_CLOUD_REGION=us-central1"; then
    assert_pass "sets GOOGLE_CLOUD_PROJECT and GOOGLE_CLOUD_REGION env vars"
  else
    assert_fail "sets GOOGLE_CLOUD_PROJECT and GOOGLE_CLOUD_REGION env vars"
  fi

  cleanup_mock
}

test_prints_service_url() {
  echo "Test: prints service URL and config snippet"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  local output
  output=$(bash "${DEPLOY_SCRIPT}" 2>&1)

  if echo "${output}" | grep -q "Collector deployed:"; then
    assert_pass "prints service URL"
  else
    assert_fail "prints service URL" "Output: ${output}"
  fi

  if echo "${output}" | grep -q "OTEL_EXPORTER_OTLP_ENDPOINT="; then
    assert_pass "prints Claude Code config snippet"
  else
    assert_fail "prints Claude Code config snippet"
  fi

  cleanup_mock
}

test_no_hardcoded_values() {
  echo "Test: no hardcoded project IDs or regions"
  local content
  content=$(cat "${DEPLOY_SCRIPT}")

  # Check there are no hardcoded GCP project IDs (pattern: word-word-123456)
  if echo "${content}" | grep -Eq '[a-z]+-[a-z]+-[0-9]{6}'; then
    assert_fail "no hardcoded project IDs" "Found what looks like a hardcoded project ID"
  else
    assert_pass "no hardcoded project IDs"
  fi

  # Check no hardcoded region values outside of comments
  if echo "${content}" | grep -v "^#" | grep -q "us-central1\|us-east1\|europe-west1"; then
    assert_fail "no hardcoded region values" "Found hardcoded region"
  else
    assert_pass "no hardcoded region values"
  fi
}

test_command_order() {
  echo "Test: commands execute in correct order"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DEPLOY_SCRIPT}" > /dev/null 2>&1

  local enable_line describe_sa_line iam_line build_line deploy_line url_line
  enable_line=$(grep -n "services enable" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  describe_sa_line=$(grep -n "iam service-accounts describe" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  iam_line=$(grep -n "add-iam-policy-binding" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  build_line=$(grep -n "builds submit" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  deploy_line=$(grep -n "run deploy" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  url_line=$(grep -n "run services describe" "${MOCK_LOG}" | head -1 | cut -d: -f1)

  if [[ "${enable_line}" -lt "${describe_sa_line}" ]] && \
     [[ "${describe_sa_line}" -lt "${iam_line}" ]] && \
     [[ "${iam_line}" -lt "${build_line}" ]] && \
     [[ "${build_line}" -lt "${deploy_line}" ]] && \
     [[ "${deploy_line}" -lt "${url_line}" ]]; then
    assert_pass "commands execute in correct order (enable → SA → IAM → build → deploy → URL)"
  else
    assert_fail "commands execute in correct order" "Order: enable=${enable_line} sa=${describe_sa_line} iam=${iam_line} build=${build_line} deploy=${deploy_line} url=${url_line}"
  fi

  cleanup_mock
}

# --- Run all tests ---

echo "=== deploy.sh test suite ==="
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
test_missing_sa_name_fails
echo ""
test_missing_sa_email_fails
echo ""
test_missing_image_tag_fails
echo ""
test_enables_required_apis
echo ""
test_creates_service_account_when_missing
echo ""
test_skips_service_account_when_exists
echo ""
test_grants_iam_role
echo ""
test_builds_image
echo ""
test_deploys_cloud_run
echo ""
test_prints_service_url
echo ""
test_no_hardcoded_values
echo ""
test_command_order
echo ""

# --- Summary ---

TOTAL=$((PASS + FAIL))
echo "=== Results: ${PASS}/${TOTAL} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
