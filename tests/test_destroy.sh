#!/usr/bin/env bash
set -euo pipefail

# Test suite for scripts/destroy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DESTROY_SCRIPT="${REPO_DIR}/scripts/destroy.sh"

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
exit 0
MOCK_EOF

  chmod +x "${MOCK_DIR}/gcloud"
  export PATH="${MOCK_DIR}:${PATH}"
  export MOCK_DIR
}

setup_mock_gcloud_failing_delete() {
  MOCK_DIR=$(mktemp -d)
  MOCK_LOG="${MOCK_DIR}/gcloud_calls.log"
  touch "${MOCK_LOG}"

  cat > "${MOCK_DIR}/gcloud" <<MOCK_EOF
#!/usr/bin/env bash
echo "\$@" >> "${MOCK_LOG}"
case "\$*" in
  *"remove-iam-policy-binding"*) exit 1 ;;
  *"service-accounts delete"*) exit 1 ;;
  *"container images delete"*) exit 1 ;;
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
  export SA_EMAIL="otel-collector@test-project.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test-project/otel-collector"
}

unset_all_env_vars() {
  unset PROJECT_ID REGION SERVICE_NAME SA_EMAIL IMAGE_TAG 2>/dev/null || true
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
  if [[ -x "${DESTROY_SCRIPT}" ]]; then
    assert_pass "destroy.sh exists and is executable"
  else
    assert_fail "destroy.sh exists and is executable"
  fi
}

test_shebang_and_strict_mode() {
  echo "Test: shebang and strict mode"
  local first_line
  first_line=$(head -1 "${DESTROY_SCRIPT}")
  if [[ "${first_line}" == "#!/usr/bin/env bash" ]]; then
    assert_pass "has correct shebang"
  else
    assert_fail "has correct shebang" "Got: ${first_line}"
  fi

  if grep -q "set -euo pipefail" "${DESTROY_SCRIPT}"; then
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
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DESTROY_SCRIPT}" 2>&1); then
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
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DESTROY_SCRIPT}" 2>&1); then
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
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DESTROY_SCRIPT}" 2>&1); then
    assert_fail "fails when SERVICE_NAME is missing"
  else
    if echo "${output}" | grep -q "SERVICE_NAME"; then
      assert_pass "fails with clear error mentioning SERVICE_NAME"
    else
      assert_fail "fails with clear error mentioning SERVICE_NAME"
    fi
  fi
}

test_missing_sa_email_fails() {
  echo "Test: missing SA_EMAIL fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
  export IMAGE_TAG="gcr.io/test/otel"

  local output
  if output=$(bash "${DESTROY_SCRIPT}" 2>&1); then
    assert_fail "fails when SA_EMAIL is missing"
  else
    if echo "${output}" | grep -q "SA_EMAIL"; then
      assert_pass "fails with clear error mentioning SA_EMAIL"
    else
      assert_fail "fails with clear error mentioning SA_EMAIL"
    fi
  fi
}

test_missing_image_tag_fails() {
  echo "Test: missing IMAGE_TAG fails"
  unset_all_env_vars
  export PROJECT_ID="test-project"
  export REGION="us-central1"
  export SERVICE_NAME="otel-collector"
  export SA_EMAIL="sa@test.iam.gserviceaccount.com"

  local output
  if output=$(bash "${DESTROY_SCRIPT}" 2>&1); then
    assert_fail "fails when IMAGE_TAG is missing"
  else
    if echo "${output}" | grep -q "IMAGE_TAG"; then
      assert_pass "fails with clear error mentioning IMAGE_TAG"
    else
      assert_fail "fails with clear error mentioning IMAGE_TAG"
    fi
  fi
}

test_deletes_cloud_run_service() {
  echo "Test: deletes Cloud Run service"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DESTROY_SCRIPT}" > /dev/null 2>&1

  if log_contains "run services delete otel-collector"; then
    assert_pass "deletes Cloud Run service"
  else
    assert_fail "deletes Cloud Run service"
  fi

  if log_contains "--quiet"; then
    assert_pass "uses --quiet flag"
  else
    assert_fail "uses --quiet flag"
  fi

  cleanup_mock
}

test_removes_iam_binding() {
  echo "Test: removes IAM binding"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DESTROY_SCRIPT}" > /dev/null 2>&1

  if log_contains "remove-iam-policy-binding" && log_contains "roles/monitoring.metricWriter"; then
    assert_pass "removes monitoring.metricWriter IAM binding"
  else
    assert_fail "removes monitoring.metricWriter IAM binding"
  fi

  cleanup_mock
}

test_deletes_service_account() {
  echo "Test: deletes service account"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DESTROY_SCRIPT}" > /dev/null 2>&1

  if log_contains "iam service-accounts delete" && log_contains "otel-collector@test-project.iam.gserviceaccount.com"; then
    assert_pass "deletes service account"
  else
    assert_fail "deletes service account"
  fi

  cleanup_mock
}

test_deletes_container_image() {
  echo "Test: deletes container image"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DESTROY_SCRIPT}" > /dev/null 2>&1

  if log_contains "container images delete" && log_contains "gcr.io/test-project/otel-collector"; then
    assert_pass "deletes container image"
  else
    assert_fail "deletes container image"
  fi

  if log_contains "--force-delete-tags"; then
    assert_pass "uses --force-delete-tags"
  else
    assert_fail "uses --force-delete-tags"
  fi

  cleanup_mock
}

test_idempotent_tolerates_failures() {
  echo "Test: idempotent — tolerates already-deleted resources"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud_failing_delete

  local output
  if output=$(bash "${DESTROY_SCRIPT}" 2>&1); then
    assert_pass "script succeeds even when IAM/SA/image deletes fail"
  else
    assert_fail "script succeeds even when IAM/SA/image deletes fail" "Exit code was non-zero"
  fi

  cleanup_mock
}

test_command_order() {
  echo "Test: commands execute in correct order"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  bash "${DESTROY_SCRIPT}" > /dev/null 2>&1

  local svc_line iam_line sa_line img_line
  svc_line=$(grep -n "run services delete" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  iam_line=$(grep -n "remove-iam-policy-binding" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  sa_line=$(grep -n "service-accounts delete" "${MOCK_LOG}" | head -1 | cut -d: -f1)
  img_line=$(grep -n "container images delete" "${MOCK_LOG}" | head -1 | cut -d: -f1)

  if [[ "${svc_line}" -lt "${iam_line}" ]] && \
     [[ "${iam_line}" -lt "${sa_line}" ]] && \
     [[ "${sa_line}" -lt "${img_line}" ]]; then
    assert_pass "correct order: service → IAM → SA → image"
  else
    assert_fail "correct order" "Order: svc=${svc_line} iam=${iam_line} sa=${sa_line} img=${img_line}"
  fi

  cleanup_mock
}

test_prints_completion_message() {
  echo "Test: prints completion message"
  unset_all_env_vars
  set_all_env_vars
  setup_mock_gcloud

  local output
  output=$(bash "${DESTROY_SCRIPT}" 2>&1)

  if echo "${output}" | grep -q "All resources deleted"; then
    assert_pass "prints 'All resources deleted' message"
  else
    assert_fail "prints 'All resources deleted' message"
  fi

  cleanup_mock
}

# --- Run all tests ---

echo "=== destroy.sh test suite ==="
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
test_missing_sa_email_fails
echo ""
test_missing_image_tag_fails
echo ""
test_deletes_cloud_run_service
echo ""
test_removes_iam_binding
echo ""
test_deletes_service_account
echo ""
test_deletes_container_image
echo ""
test_idempotent_tolerates_failures
echo ""
test_command_order
echo ""
test_prints_completion_message
echo ""

# --- Summary ---

TOTAL=$((PASS + FAIL))
echo "=== Results: ${PASS}/${TOTAL} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
