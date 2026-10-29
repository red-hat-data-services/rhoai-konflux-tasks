#!/usr/bin/env bash
# Quay publication safeguards for rhoai-init (RHOAIENG-97056).
# Sourced by unit tests; the same logic is embedded in rhoai-init 0.4.

readonly RELEASE_TAG_REGEX='^rhoai-[0-9]+\.[0-9]+(-ea\.[0-9]+)?$'
readonly RELEASE_BRANCH_REGEX='^rhoai-[0-9]+\.[0-9]+(-ea\.[0-9]+)?$'
readonly RHDS_GITHUB_ORG='red-hat-data-services'

fail_validation() {
  echo "ERROR: Quay tagging safeguard violated: $1" >&2
  exit 1
}

fail_missing_context() {
  echo "ERROR: Quay tagging safeguard: missing or malformed required context: $1" >&2
  exit 1
}

is_release_tag() {
  [[ "$1" =~ $RELEASE_TAG_REGEX ]]
}

is_release_branch() {
  [[ "$1" =~ $RELEASE_BRANCH_REGEX ]]
}

is_push_like_event() {
  [[ "$1" == "push" || "$1" == "incoming" ]]
}

normalize_github_repo_url() {
  local url="${1%/}"
  url="${url%.git}"
  url="${url#https://}"
  url="${url#http://}"
  url="${url#github.com/}"
  url="${url#www.github.com/}"
  echo "$url"
}

parse_image_reference() {
  local image_ref="$1"
  local registry path_with_tag image_path

  registry="${image_ref%%/*}"
  if [[ "$registry" == "$image_ref" || -z "$registry" ]]; then
    fail_missing_context "image reference must include a registry and path (got: ${image_ref})"
  fi

  path_with_tag="${image_ref#*/}"
  if [[ "$path_with_tag" == *":"* ]]; then
    IMAGE_REGISTRY="$registry"
    IMAGE_PATH="${path_with_tag%:*}"
    IMAGE_TAG="${path_with_tag##*:}"
  else
    IMAGE_REGISTRY="$registry"
    IMAGE_PATH="$path_with_tag"
    IMAGE_TAG=""
  fi

  IMAGE_NAME="${IMAGE_PATH##*/}"
  IMAGE_NAMESPACE="${IMAGE_PATH%/*}"
  if [[ "$IMAGE_NAMESPACE" == "$IMAGE_PATH" ]]; then
    IMAGE_NAMESPACE=""
  fi
}

publishes_to_rhoai_quay_namespace() {
  [[ "${IMAGE_REGISTRY}" == "quay.io" && "${IMAGE_NAMESPACE}" == "rhoai" ]]
}

collect_publication_tags() {
  PUBLICATION_TAGS=()
  if [[ -n "${IMAGE_TAG}" ]]; then
    PUBLICATION_TAGS+=("${IMAGE_TAG}")
  fi
  if [[ -n "${ADDITIONAL_TAGS:-}" ]]; then
    # Tekton array params expand to a whitespace-separated list in rhoai-init.
    local -a extra=()
    read -r -a extra <<< "${ADDITIONAL_TAGS}"
    local tag
    for tag in "${extra[@]}"; do
      [[ -n "$tag" ]] && PUBLICATION_TAGS+=("$tag")
    done
  fi
}

validate_quay_tagging() {
  local event_type="${PAC_EVENT_TYPE:-}"
  local target_branch="${TARGET_BRANCH:-}"
  local governing_repo_url="${GOVERNING_REPO_URL:-}"
  local image_output="${IMAGE_OUTPUT:-}"

  if [[ -z "$event_type" ]]; then
    fail_missing_context "event type (pipelinesascode.tekton.dev/event-type)"
  fi
  if [[ -z "$target_branch" ]]; then
    fail_missing_context "target branch (build.appstudio.redhat.com/target_branch)"
  fi
  if [[ -z "$governing_repo_url" ]]; then
    fail_missing_context "governing repository URL (pipelinesascode.tekton.dev/repo-url)"
  fi
  if [[ -z "$image_output" ]]; then
    fail_missing_context "primary image output (image-output parameter)"
  fi

  if [[ "$event_type" != "pull_request" ]] && ! is_push_like_event "$event_type"; then
    fail_missing_context "unsupported event type '${event_type}'"
  fi

  parse_image_reference "$image_output"
  collect_publication_tags

  if [[ ${#PUBLICATION_TAGS[@]} -eq 0 ]]; then
    fail_missing_context "at least one publication tag (primary image tag or additional-tags)"
  fi

  local governing_slug
  governing_slug="$(normalize_github_repo_url "$governing_repo_url")"
  local governing_org="${governing_slug%%/*}"
  local is_rhds=false
  if [[ "$governing_org" == "$RHDS_GITHUB_ORG" ]]; then
    is_rhds=true
  fi

  if publishes_to_rhoai_quay_namespace && [[ "$is_rhds" == "false" ]]; then
    fail_validation "non-RHDS governing repository '${governing_slug}' cannot publish to quay.io/rhoai (event=${event_type}, branch=${target_branch}, image=${image_output})"
  fi

  local tag
  for tag in "${PUBLICATION_TAGS[@]}"; do
    if [[ "$event_type" == "pull_request" ]] && is_release_tag "$tag"; then
      fail_validation "pull request builds must not publish release tag '${tag}' (event=${event_type}, branch=${target_branch}, governing_repo=${governing_slug})"
    fi

    if is_push_like_event "$event_type" && [[ "$target_branch" == "main" ]] && is_release_tag "$tag"; then
      fail_validation "main-branch push builds must not publish release tag '${tag}' (branch=${target_branch}, governing_repo=${governing_slug})"
    fi

    if is_push_like_event "$event_type" && is_release_tag "$tag"; then
      if ! is_release_branch "$target_branch"; then
        fail_validation "release tag '${tag}' is only allowed on release branches matching ${RELEASE_BRANCH_REGEX} (branch=${target_branch})"
      fi
      if [[ "$tag" != "$target_branch" ]]; then
        fail_validation "release tag '${tag}' must match release branch '${target_branch}' (governing_repo=${governing_slug})"
      fi
    fi
  done

  echo "Quay tagging safeguards passed (event=${event_type}, branch=${target_branch}, governing_repo=${governing_slug}, tags=${PUBLICATION_TAGS[*]})"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  validate_quay_tagging
fi
