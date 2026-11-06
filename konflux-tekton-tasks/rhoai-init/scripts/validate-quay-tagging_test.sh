#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_YAML="${SCRIPT_DIR}/../0.4/rhoai-init.yaml"
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

# Exercise the CPE logic embedded in the Tekton task with its own image parser.
check_cpe() {
  local image_output="$1"
  local expected="$2"
  local IMAGE_OUTPUT="$image_output" RHOAI_VERSION="${3:-3.6.2}" is_pull_request=false
  local cpe_id=unset

  source <(sed -n '/^      parse_image_reference() {$/,/^      }$/p' "$TASK_YAML" | sed 's/^      //')
  parse_image_reference "$IMAGE_OUTPUT"
  source <(sed -n '/^      semver_ge() {$/,/^      }$/p' "$TASK_YAML" | sed 's/^      //')
  source <(sed -n '/^      # No need to set CPE ID for pull request builds$/,/^      echo "CPE ID: \$cpe_id"$/p' "$TASK_YAML" | sed 's/^      //')

  [[ "$cpe_id" == "$expected" ]] || {
    echo "Expected CPE ${expected}, got ${cpe_id}" >&2
    return 1
  }
}

run_pass "PR case: RHEL 9 dashboard" \
  check_cpe quay.io/rhoai/odh-dashboard-rhel9:rhoai-3.3 'cpe:/a:redhat:openshift_ai:3.3::el9' 3.3 || failures=$((failures + 1))
run_pass "PR case: RHEL 8 dashboard" \
  check_cpe quay.io/rhoai/odh-dashboard-rhel8:rhoai-2.16 'cpe:/a:redhat:openshift_ai:2.16::el8' 2.16 || failures=$((failures + 1))
run_pass "PR case: RHEL 10 dashboard" \
  check_cpe quay.io/rhoai/odh-dashboard-rhel10:rhoai-4.0 'cpe:/a:redhat:openshift_ai:4.0::el10' 4.0 || failures=$((failures + 1))
run_fail "PR case: dashboard without RHEL suffix" \
  check_cpe quay.io/rhoai/odh-dashboard:rhoai-3.3 'cpe:/a:redhat:openshift_ai:3.3::el9' 3.3 || failures=$((failures + 1))
run_pass "Bundle image: RHEL 8 for RHOAI < 2.20" \
  check_cpe quay.io/rhoai/odh-operator-bundle:rhoai-2.16 'cpe:/a:redhat:openshift_ai:2.16::el8' 2.16 || failures=$((failures + 1))
run_pass "Bundle image: RHEL 9 for RHOAI >= 2.20" \
  check_cpe quay.io/rhoai/odh-operator-bundle:rhoai-2.25 'cpe:/a:redhat:openshift_ai:2.25::el9' 2.25 || failures=$((failures + 1))
run_pass "Bundle image: RHEL 9 at RHOAI 3.7 (< 3.8)" \
  check_cpe quay.io/rhoai/odh-operator-bundle:rhoai-3.7 'cpe:/a:redhat:openshift_ai:3.7::el9' 3.7 || failures=$((failures + 1))
run_pass "Bundle image: RHEL 10 for RHOAI >= 3.8" \
  check_cpe quay.io/rhoai/odh-operator-bundle:rhoai-3.8 'cpe:/a:redhat:openshift_ai:3.8::el10' 3.8 || failures=$((failures + 1))
run_pass "Bundle image: RHEL 10 for RHOAI 4.0" \
  check_cpe quay.io/rhoai/odh-operator-bundle:rhoai-4.0 'cpe:/a:redhat:openshift_ai:4.0::el10' 4.0 || failures=$((failures + 1))
run_pass "Chart image: RHEL 9 for RHOAI >= 2.20" \
  check_cpe quay.io/rhoai/odh-dashboard-chart:rhoai-3.6 'cpe:/a:redhat:openshift_ai:3.6::el9' 3.6 || failures=$((failures + 1))
run_pass "Chart image: RHEL 10 for RHOAI >= 3.8" \
  check_cpe quay.io/rhoai/odh-dashboard-chart:rhoai-3.8 'cpe:/a:redhat:openshift_ai:3.8::el10' 3.8 || failures=$((failures + 1))
run_pass "Fragment image: RHEL 9 for RHOAI >= 2.20" \
  check_cpe quay.io/rhoai/odh-fragment-catalog:rhoai-3.6 'cpe:/a:redhat:openshift_ai:3.6::el9' 3.6 || failures=$((failures + 1))
run_pass "Fragment image: RHEL 10 for RHOAI >= 3.8" \
  check_cpe quay.io/rhoai/odh-fragment-catalog:rhoai-3.8 'cpe:/a:redhat:openshift_ai:3.8::el10' 3.8 || failures=$((failures + 1))
run_pass "PR case: TrustyAI image" \
  check_cpe quay.io/rhoai/odh-trustyai-nemo-guardrails-server-rhel9:rhoai-3.3 'cpe:/a:redhat:openshift_ai:3.3::el9' 3.3 || failures=$((failures + 1))
run_pass "CPE accepts the operator image name" \
  check_cpe quay.io/rhoai/odh-rhel9-operator:rhoai-2.25 'cpe:/a:redhat:openshift_ai:2.25::el9' 2.25 || failures=$((failures + 1))
run_pass "CPE uses the operator image name, not its tag" \
  check_cpe quay.io/rhoai/odh-rhel9-operator:build-rhel10 'cpe:/a:redhat:openshift_ai:3.6::el9' || failures=$((failures + 1))

run_pass "CPE uses image-name suffix, not tag" \
  check_cpe quay.io/rhoai/some-image-rhel9:build-rhel10 'cpe:/a:redhat:openshift_ai:3.6::el9' || failures=$((failures + 1))
run_pass "CPE uses image-name suffix, not registry or namespace" \
  check_cpe registry-rhel10.example/team-rhel10/some-image-rhel9:build 'cpe:/a:redhat:openshift_ai:3.6::el9' || failures=$((failures + 1))
run_pass "CPE accepts a two-digit RHEL suffix" \
  check_cpe quay.io/rhoai/some-image-rhel10:build 'cpe:/a:redhat:openshift_ai:3.6::el10' || failures=$((failures + 1))
run_fail "CPE rejects RHEL suffix only in tag" \
  check_cpe quay.io/rhoai/some-image:build-rhel10 'cpe:/a:redhat:openshift_ai:3.6::el10' || failures=$((failures + 1))
run_fail "CPE rejects RHEL suffix only in namespace" \
  check_cpe quay.io/team-rhel10/some-image:build 'cpe:/a:redhat:openshift_ai:3.6::el10' || failures=$((failures + 1))
run_fail "CPE rejects RHEL suffix only in registry" \
  check_cpe registry-rhel10.example/rhoai/some-image:build 'cpe:/a:redhat:openshift_ai:3.6::el10' || failures=$((failures + 1))
run_pass "CPE accepts a hyphen-delimited RHEL marker within the image name" \
  check_cpe quay.io/rhoai/some-image-rhel9-debug:build 'cpe:/a:redhat:openshift_ai:3.6::el9' || failures=$((failures + 1))
run_fail "CPE rejects a RHEL marker without a trailing delimiter" \
  check_cpe quay.io/rhoai/some-image-rhel9debug:build 'cpe:/a:redhat:openshift_ai:3.6::el9' || failures=$((failures + 1))

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

run_pass "RHDS release incoming (nudge) matching tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=incoming TARGET_BRANCH=rhoai-3.6
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/distributed-workloads.git
  IMAGE_OUTPUT=quay.io/rhoai/odh-th-torch-rocm-py312-rhel9:rhoai-3.6
  ADDITIONAL_TAGS="rhoai-3.6-deadbeef"
  validate_quay_tagging
' || failures=$((failures + 1))

run_pass "RHDS PR on-comment (/build-konflux) on-pr tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=on-comment TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/llama-stack-provider-trustyai-garak.git
  IMAGE_OUTPUT=quay.io/rhoai/odh-trustyai-garak-lls-provider-dsp-rhel9:on-pr-736
  validate_quay_tagging
' || failures=$((failures + 1))

run_fail "on-comment with release tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=on-comment TARGET_BRANCH=main
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/llama-stack-provider-trustyai-garak.git
  IMAGE_OUTPUT=quay.io/rhoai/odh-trustyai-garak-lls-provider-dsp-rhel9:rhoai-3.6
  validate_quay_tagging
' || failures=$((failures + 1))

run_pass "RHDS PR retest-all-comment on-pr tag" bash -c '
  source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
  PAC_EVENT_TYPE=retest-all-comment TARGET_BRANCH=stable
  GOVERNING_REPO_URL=https://github.com/red-hat-data-services/odh-dashboard.git
  IMAGE_OUTPUT=quay.io/rhoai/odh-core-bff-rhel9:on-pr-2696
  validate_quay_tagging
' || failures=$((failures + 1))

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

# Patch releases must follow the same publication safeguards as minor releases.
patch_release_case() {
  base_rhds_release_push
  PAC_EVENT_TYPE="$1"
  TARGET_BRANCH="$2"
  IMAGE_OUTPUT="quay.io/rhoai/some-image-rhel9:$3"
  ADDITIONAL_TAGS="${4:-}"
  validate_quay_tagging
}

for release in rhoai-2.25.13 rhoai-2.25.13-ea.1; do
  run_pass "release branch ${release}" is_release_branch "$release" || failures=$((failures + 1))
  run_pass "release tag ${release}" is_release_tag "$release" || failures=$((failures + 1))
  for event in push incoming; do
    run_pass "${event} matching ${release}" patch_release_case "$event" "$release" "$release" || failures=$((failures + 1))
    run_pass "${event} additional ${release}" patch_release_case "$event" "$release" snapshot "$release" || failures=$((failures + 1))
    run_fail "${event} mismatched ${release}" patch_release_case "$event" rhoai-2.25.12 "$release" || failures=$((failures + 1))
    run_fail "${event} minor branch with ${release}" patch_release_case "$event" rhoai-2.25 "$release" || failures=$((failures + 1))
    run_fail "${event} main with ${release}" patch_release_case "$event" main "$release" || failures=$((failures + 1))
  done
  for event in pull_request pull_request_labeled on-comment retest-comment retest-all-comment test-comment; do
    run_fail "${event} primary ${release}" patch_release_case "$event" "$release" "$release" || failures=$((failures + 1))
    run_fail "${event} additional ${release}" patch_release_case "$event" "$release" on-pr-123 "$release" || failures=$((failures + 1))
  done
done

# Z-streams publish minor tags (rhoai-X.Y) from patch branches (rhoai-X.Y.Z).
for event in push incoming; do
  run_pass "${event} z-stream minor tag on patch branch" \
    patch_release_case "$event" rhoai-2.25.13 rhoai-2.25 || failures=$((failures + 1))
  run_pass "${event} z-stream minor tag as additional on patch branch" \
    patch_release_case "$event" rhoai-2.25.13 snapshot rhoai-2.25 || failures=$((failures + 1))
  run_pass "${event} z-stream EA minor tag on patch EA branch" \
    patch_release_case "$event" rhoai-2.25.13-ea.1 rhoai-2.25-ea.1 || failures=$((failures + 1))
  run_pass "${event} odh-operator z-stream case" bash -c '
    source "'"${SCRIPT_DIR}"'/validate-quay-tagging.sh"
    PAC_EVENT_TYPE='"${event}"'
    TARGET_BRANCH=rhoai-2.25.13
    GOVERNING_REPO_URL=https://github.com/red-hat-data-services/rhods-operator
    IMAGE_OUTPUT=quay.io/rhoai/odh-rhel9-operator:rhoai-2.25
    validate_quay_tagging
  ' || failures=$((failures + 1))
  run_fail "${event} z-stream wrong minor on patch branch" \
    patch_release_case "$event" rhoai-2.25.13 rhoai-2.24 || failures=$((failures + 1))
  run_fail "${event} z-stream GA tag on EA patch branch" \
    patch_release_case "$event" rhoai-2.25.13-ea.1 rhoai-2.25 || failures=$((failures + 1))
  run_fail "${event} z-stream EA tag on GA patch branch" \
    patch_release_case "$event" rhoai-2.25.13 rhoai-2.25-ea.1 || failures=$((failures + 1))
done

for branch in rhoai-2.25. rhoai-2.25.x rhoai-2.25.13.1 rhoai-2.25.13-extra prefix-rhoai-2.25.13; do
  run_fail "invalid release branch ${branch}" is_release_branch "$branch" || failures=$((failures + 1))
  run_fail "invalid release tag ${branch}" is_release_tag "$branch" || failures=$((failures + 1))
done

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} test(s) failed"
  exit 1
fi

echo "All validate-quay-tagging tests passed."
