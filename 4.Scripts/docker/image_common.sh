#!/usr/bin/env bash
# shellcheck shell=bash

IMAGE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_PROJECT_DIR="$(cd "${IMAGE_SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${IMAGE_PROJECT_DIR}/4.Scripts/common/load_config.sh"

image_log() {
  printf '[INFO] %s\n' "$*"
}

image_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

image_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

image_die() {
  image_error "$*"
  exit 1
}

image_require_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 ||
    image_die "Required command is unavailable: ${command_name}"
}

image_check_docker_access() {
  local output rc

  if ! command -v docker >/dev/null 2>&1; then
    image_error "Docker CLI is not installed or is not available in PATH."
    image_error "Contact the system administrator to install or expose Docker."
    return 1
  fi

  output="$(docker info --format '{{.ServerVersion}}' 2>&1)"
  rc=$?

  if [[ "$rc" -ne 0 ]]; then
    image_error "Docker is installed, but the current user cannot access the Docker daemon."
    image_error "Contact the system administrator for the approved Docker access method."
    image_error "Do not use sudo or change Docker socket permissions unless cluster policy explicitly permits it."
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf 'docker_server_version=%s\n' "$output"
  return 0
}

image_default_archive_dir() {
  printf '%s\n' \
    "${ENDO_EXO_IMAGE_ARCHIVE_DIR:-${REFS_DIR}/container_images}"
}

image_git_commit_full() {
  git -C "$IMAGE_PROJECT_DIR" rev-parse HEAD 2>/dev/null ||
    printf 'unknown\n'
}

image_git_commit_short() {
  git -C "$IMAGE_PROJECT_DIR" rev-parse --short HEAD 2>/dev/null ||
    printf 'unknown\n'
}

image_manifest_get() {
  local manifest="$1"
  local key="$2"

  awk -v wanted="$key" '
    index($0, wanted "=") == 1 {
      sub(/^[^=]*=/, "", $0)
      print
      exit
    }
  ' "$manifest"
}

image_manifest_require() {
  local manifest="$1"
  local key="$2"
  local value

  value="$(image_manifest_get "$manifest" "$key")"

  [[ -n "$value" ]] ||
    image_die "Manifest key is missing: ${key}"

  printf '%s\n' "$value"
}

image_validate_sha256() {
  local value="$1"

  [[ "$value" =~ ^[0-9a-f]{64}$ ]]
}

image_validate_image_id() {
  local value="$1"

  [[ "$value" =~ ^sha256:[0-9a-f]{64}$ ]]
}

image_is_positive_integer() {
  local value="$1"

  [[ "$value" =~ ^[1-9][0-9]*$ ]]
}
