#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=validate-quay-tagging.sh
source "${SCRIPT_DIR}/validate-quay-tagging.sh"

run_pass() {
  local name="$1"
  shift
  (
    set -euo pipefail
    "$@"
  ) && echo "PASS: ${name}" || { echo "FAIL: ${name}"; return 1; }
}

run_fail() {
  local name="$1"
  shift
  if (
    set -euo pipefail
    "$@"
  ); then
    echo "FAIL: ${name} (expected rejection)"
    return 1
  fi
  echo "PASS: ${name} (rejected as expected)"
}

base_rhds_pr() {
  PAC_EVENT_TYPE=pull_request
  TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-123
  ADDITIONAL_TAGS=""
}

base_rhds_release_push() {
  PAC_EVENT_TYPE=push
  TARGET_BRANCH=rhoai-3.6
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6
  ADDITIONAL_TAGS=""
}

failures=0

run_pass "RHDS PR on-pr tag" base_rhds_pr validate_quay_tagging || failures=$((failures + 1))

run_fail "RHDS PR GA release tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS PR EA release tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6-ea.1
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS PR additional GA tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-123
  ADDITIONAL_TAGS="rhoai-3.6"
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS PR additional EA tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-123
  ADDITIONAL_TAGS="rhoai-3.6-ea.1"
  validate_quay_tagging
' || failures=$((failures + 1))

run_pass "RHDS PR multiple permitted additional tags" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-123
  ADDITIONAL_TAGS="pr-snapshot-1 pr-snapshot-2"
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS PR multiple additional tags with release tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-123
  ADDITIONAL_TAGS="pr-snapshot-1 rhoai-3.6"
  validate_quay_tagging
' || failures=$((failures + 1))

run_pass "RHDS release push matching tag" base_rhds_release_push validate_quay_tagging || failures=$((failures + 1))

run_pass "RHDS EA release push matching tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=rhoai-3.6-ea.1
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6-ea.1
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS release push mismatched GA tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=rhoai-3.6
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.5
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS EA branch wrong EA tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=rhoai-3.6-ea.1
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6-ea.2
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS EA branch GA tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=rhoai-3.6-ea.1
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "RHDS GA branch EA tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=rhoai-3.6
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6-ea.1
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "main push release tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "main push EA release tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6-ea.1
  validate_quay_tagging
' || failures=$((failures + 1))

run_pass "fork PR targeting RHDS" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-99
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "non-RHDS PR to rhoai namespace" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/some-org/some-repo
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-1
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "non-RHDS push to rhoai namespace" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=push TARGET_BRANCH=rhoai-3.6
  GOVERNING_REPO_URL=https://github.com/some-org/some-repo
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:rhoai-3.6
  validate_quay_tagging
' || failures=$((failures + 1))

run_pass "governing repo URL normalization" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=http://github.com/red-hat-data-services/kserve.git/
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-1
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "missing target branch" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request
  TARGET_BRANCH=
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-1
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "missing governing repo URL" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-1
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "malformed image reference" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=pull_request TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=not-a-valid-image-ref
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "missing event type" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  unset PAC_EVENT_TYPE
  TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/kserve
  IMAGE_OUTPUT=quay.io/rhoai/some-image-rhel9:on-pr-1
  validate_quay_tagging
' || failures=$((failures + 1))

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} test(s) failed"
  exit 1
fi

echo "All validate-quay-tagging tests passed."
