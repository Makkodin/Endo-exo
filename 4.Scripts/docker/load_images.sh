#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/image_common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash 4.Scripts/docker/load_images.sh --archive FILE [options]

Options:
  --archive FILE       Docker image archive in .tar.gz format.
  --manifest FILE      Manifest path. By default inferred from the archive.
  --checksum FILE      SHA-256 file. By default inferred from the archive.
  --ids-only           Verify image IDs without full runtime tests.
  --replace-tags       Allow docker load to replace mismatching local tags.
  -h, --help           Show this help message.

Safety:
  Existing matching images are not reloaded.
  Existing mismatching tags cause an error unless --replace-tags is used.
  Images and Docker data are never deleted by this script.
USAGE
}

ARCHIVE=""
MANIFEST=""
CHECKSUM=""
IDS_ONLY=0
REPLACE_TAGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] ||
        image_die "--archive requires a value"

      ARCHIVE="$2"
      shift 2
      ;;

    --manifest)
      [[ $# -ge 2 ]] ||
        image_die "--manifest requires a value"

      MANIFEST="$2"
      shift 2
      ;;

    --checksum)
      [[ $# -ge 2 ]] ||
        image_die "--checksum requires a value"

      CHECKSUM="$2"
      shift 2
      ;;

    --ids-only)
      IDS_ONLY=1
      shift
      ;;

    --replace-tags)
      REPLACE_TAGS=1
      shift
      ;;

    -h|--help)
      usage
      exit 0
      ;;

    *)
      image_die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$ARCHIVE" ]] ||
  image_die "--archive is required"

[[ -f "$ARCHIVE" ]] ||
  image_die "Archive is unavailable: $ARCHIVE"

case "$ARCHIVE" in
  *.tar.gz)
    ;;
  *)
    image_die "Archive must end with .tar.gz"
    ;;
esac

ARCHIVE="$(readlink -f "$ARCHIVE")"

if [[ -z "$MANIFEST" ]]; then
  MANIFEST="${ARCHIVE%.tar.gz}.manifest.env"
fi

if [[ -z "$CHECKSUM" ]]; then
  CHECKSUM="${ARCHIVE}.sha256"
fi

[[ -f "$MANIFEST" ]] ||
  image_die "Manifest is unavailable: $MANIFEST"

[[ -f "$CHECKSUM" ]] ||
  image_die "Checksum file is unavailable: $CHECKSUM"

MANIFEST="$(readlink -f "$MANIFEST")"
CHECKSUM="$(readlink -f "$CHECKSUM")"

image_require_command docker
image_require_command gzip
image_require_command sha256sum
image_require_command awk
image_require_command stat
image_require_command df

FORMAT_VERSION="$(
  image_manifest_require \
    "$MANIFEST" \
    FORMAT_VERSION
)"

EXPORT_COMPLETE="$(
  image_manifest_require \
    "$MANIFEST" \
    EXPORT_COMPLETE
)"

CORE_IMAGE="$(
  image_manifest_require \
    "$MANIFEST" \
    CORE_IMAGE
)"

CORE_IMAGE_ID="$(
  image_manifest_require \
    "$MANIFEST" \
    CORE_IMAGE_ID
)"

TELESCOPE_IMAGE="$(
  image_manifest_require \
    "$MANIFEST" \
    TELESCOPE_IMAGE
)"

TELESCOPE_IMAGE_ID="$(
  image_manifest_require \
    "$MANIFEST" \
    TELESCOPE_IMAGE_ID
)"

MANIFEST_ARCHIVE_FILE="$(
  image_manifest_require \
    "$MANIFEST" \
    ARCHIVE_FILE
)"

MANIFEST_ARCHIVE_BYTES="$(
  image_manifest_require \
    "$MANIFEST" \
    ARCHIVE_SIZE_BYTES
)"

MANIFEST_ARCHIVE_SHA256="$(
  image_manifest_require \
    "$MANIFEST" \
    ARCHIVE_SHA256
)"

[[ "$FORMAT_VERSION" == "1" ]] ||
  image_die "Unsupported manifest format: $FORMAT_VERSION"

[[ "$EXPORT_COMPLETE" == "1" ]] ||
  image_die "Manifest does not describe a completed export"

image_validate_image_id "$CORE_IMAGE_ID" ||
  image_die "Invalid CORE_IMAGE_ID in manifest"

image_validate_image_id "$TELESCOPE_IMAGE_ID" ||
  image_die "Invalid TELESCOPE_IMAGE_ID in manifest"

image_validate_sha256 "$MANIFEST_ARCHIVE_SHA256" ||
  image_die "Invalid ARCHIVE_SHA256 in manifest"

image_is_positive_integer "$MANIFEST_ARCHIVE_BYTES" ||
  image_die "Invalid ARCHIVE_SIZE_BYTES in manifest"

[[ "$(basename "$ARCHIVE")" == "$MANIFEST_ARCHIVE_FILE" ]] ||
  image_die "Archive filename does not match the manifest"

ACTUAL_ARCHIVE_BYTES="$(
  stat -c '%s' "$ARCHIVE"
)"

[[ "$ACTUAL_ARCHIVE_BYTES" == "$MANIFEST_ARCHIVE_BYTES" ]] ||
  image_die "Archive size does not match the manifest"

CHECKSUM_SHA256="$(
  awk 'NF >= 2 {print $1; exit}' \
    "$CHECKSUM"
)"

CHECKSUM_ARCHIVE_FILE="$(
  awk 'NF >= 2 {print $2; exit}' \
    "$CHECKSUM"
)"

image_validate_sha256 "$CHECKSUM_SHA256" ||
  image_die "Invalid SHA-256 value in checksum file"

[[ "$CHECKSUM_ARCHIVE_FILE" == "$(basename "$ARCHIVE")" ]] ||
  image_die "Checksum filename does not match the archive"

[[ "$CHECKSUM_SHA256" == "$MANIFEST_ARCHIVE_SHA256" ]] ||
  image_die "Checksum and manifest contain different SHA-256 values"

echo "archive=$ARCHIVE"
echo "manifest=$MANIFEST"
echo "checksum=$CHECKSUM"
echo "core_image=$CORE_IMAGE"
echo "expected_core_image_id=$CORE_IMAGE_ID"
echo "telescope_image=$TELESCOPE_IMAGE"
echo "expected_telescope_image_id=$TELESCOPE_IMAGE_ID"

echo
echo "===== ARCHIVE INTEGRITY ====="

ACTUAL_ARCHIVE_SHA256="$(
  sha256sum "$ARCHIVE" |
  awk '{print $1}'
)"

[[ "$ACTUAL_ARCHIVE_SHA256" == "$MANIFEST_ARCHIVE_SHA256" ]] ||
  image_die "Archive SHA-256 verification failed"

echo "archive_sha256=$ACTUAL_ARCHIVE_SHA256"
echo "sha256_verify_status=OK"

gzip -t "$ARCHIVE"

echo "gzip_test_status=OK"

echo
echo "===== DOCKER ACCESS ====="

image_check_docker_access ||
  exit 1

DOCKER_ROOT="$(
  docker info \
    --format '{{.DockerRootDir}}'
)"

echo "docker_root=$DOCKER_ROOT"

if [[ -d "$DOCKER_ROOT" ]]; then
  df -h "$DOCKER_ROOT"
else
  image_warn "Docker root directory is not directly readable: $DOCKER_ROOT"
fi

CURRENT_CORE_ID="$(
  docker image inspect \
    "$CORE_IMAGE" \
    --format '{{.Id}}' \
    2>/dev/null ||
  true
)"

CURRENT_TELESCOPE_ID="$(
  docker image inspect \
    "$TELESCOPE_IMAGE" \
    --format '{{.Id}}' \
    2>/dev/null ||
  true
)"

echo
echo "===== EXISTING TAGS ====="

echo "current_core_image_id=${CURRENT_CORE_ID:-missing}"
echo "current_telescope_image_id=${CURRENT_TELESCOPE_ID:-missing}"

MISMATCH=0

if [[ -n "$CURRENT_CORE_ID" &&
      "$CURRENT_CORE_ID" != "$CORE_IMAGE_ID" ]]; then
  image_error "The local core tag points to a different image ID."
  MISMATCH=1
fi

if [[ -n "$CURRENT_TELESCOPE_ID" &&
      "$CURRENT_TELESCOPE_ID" != "$TELESCOPE_IMAGE_ID" ]]; then
  image_error "The local Telescope tag points to a different image ID."
  MISMATCH=1
fi

if [[ "$MISMATCH" -eq 1 &&
      "$REPLACE_TAGS" -ne 1 ]]; then
  image_die "Refusing to replace existing tags. Review the mismatch or rerun with --replace-tags."
fi

NEED_LOAD=1

if [[ "$CURRENT_CORE_ID" == "$CORE_IMAGE_ID" &&
      "$CURRENT_TELESCOPE_ID" == "$TELESCOPE_IMAGE_ID" ]]; then
  NEED_LOAD=0
fi

if [[ "$NEED_LOAD" -eq 1 ]]; then
  echo
  echo "===== DOCKER LOAD ====="

  set +e

  gzip -dc "$ARCHIVE" |
  docker load

  PIPE_STATUS=("${PIPESTATUS[@]}")

  set -e

  GZIP_EXIT="${PIPE_STATUS[0]}"
  DOCKER_LOAD_EXIT="${PIPE_STATUS[1]}"

  echo "archive_decompression_exit=$GZIP_EXIT"
  echo "docker_load_exit=$DOCKER_LOAD_EXIT"

  [[ "$GZIP_EXIT" -eq 0 ]] ||
    image_die "Archive decompression failed"

  [[ "$DOCKER_LOAD_EXIT" -eq 0 ]] ||
    image_die "Docker image loading failed"
else
  echo
  echo "docker_load_status=SKIPPED_ALREADY_MATCHING"
fi

LOADED_CORE_ID="$(
  docker image inspect \
    "$CORE_IMAGE" \
    --format '{{.Id}}'
)"

LOADED_TELESCOPE_ID="$(
  docker image inspect \
    "$TELESCOPE_IMAGE" \
    --format '{{.Id}}'
)"

echo
echo "===== LOADED IMAGE IDS ====="

echo "loaded_core_image_id=$LOADED_CORE_ID"
echo "loaded_telescope_image_id=$LOADED_TELESCOPE_ID"

[[ "$LOADED_CORE_ID" == "$CORE_IMAGE_ID" ]] ||
  image_die "Loaded core image ID does not match the manifest"

[[ "$LOADED_TELESCOPE_ID" == "$TELESCOPE_IMAGE_ID" ]] ||
  image_die "Loaded Telescope image ID does not match the manifest"

echo "image_id_verification_status=OK"

echo
echo "===== RUNTIME VERIFICATION ====="

VERIFY_ARGS=(
  --manifest "$MANIFEST"
)

if [[ "$IDS_ONLY" -eq 1 ]]; then
  VERIFY_ARGS+=(--ids-only)
fi

bash "${SCRIPT_DIR}/verify_images.sh" \
  "${VERIFY_ARGS[@]}"

echo
echo "load_final_status=OK"
