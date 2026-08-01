#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/image_common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash 4.Scripts/docker/export_images.sh [options]

Options:
  --output-dir DIR         Directory for the archive and manifest.
  --archive FILE           Exact output archive path. Overrides --output-dir.
  --core-image IMAGE       Override the configured core image.
  --telescope-image IMAGE  Override the configured Telescope image.
  --force                   Replace only the exact target artifact files.
  -h, --help               Show this help message.

Default output directory:
  $ENDO_EXO_IMAGE_ARCHIVE_DIR, when defined;
  otherwise 3.Refs/container_images.
USAGE
}

OUTPUT_DIR="$(image_default_archive_dir)"
ARCHIVE=""
CORE_IMAGE="$ENDO_EXO_CORE_IMAGE"
TELESCOPE_IMAGE="$ENDO_EXO_TELESCOPE_IMAGE"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] ||
        image_die "--output-dir requires a value"

      OUTPUT_DIR="$2"
      shift 2
      ;;

    --archive)
      [[ $# -ge 2 ]] ||
        image_die "--archive requires a value"

      ARCHIVE="$2"
      shift 2
      ;;

    --core-image)
      [[ $# -ge 2 ]] ||
        image_die "--core-image requires a value"

      CORE_IMAGE="$2"
      shift 2
      ;;

    --telescope-image)
      [[ $# -ge 2 ]] ||
        image_die "--telescope-image requires a value"

      TELESCOPE_IMAGE="$2"
      shift 2
      ;;

    --force)
      FORCE=1
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

image_require_command docker
image_require_command gzip
image_require_command sha256sum
image_require_command awk
image_require_command stat
image_require_command hostname
image_require_command date

image_check_docker_access ||
  exit 1

GIT_COMMIT_FULL="$(image_git_commit_full)"
GIT_COMMIT_SHORT="$(image_git_commit_short)"

if [[ -z "$ARCHIVE" ]]; then
  ARCHIVE="${OUTPUT_DIR}/endo-exo_${ENDO_EXO_VERSION}_${GIT_COMMIT_SHORT}_images.tar.gz"
else
  case "$ARCHIVE" in
    *.tar.gz)
      ;;
    *)
      image_die "--archive must end with .tar.gz"
      ;;
  esac

  OUTPUT_DIR="$(dirname "$ARCHIVE")"
fi

mkdir -p "$OUTPUT_DIR"

OUTPUT_DIR="$(readlink -f "$OUTPUT_DIR")"
ARCHIVE="${OUTPUT_DIR}/$(basename "$ARCHIVE")"

CHECKSUM="${ARCHIVE}.sha256"
MANIFEST="${ARCHIVE%.tar.gz}.manifest.env"

TMP_SUFFIX=".tmp.$$.${RANDOM}"
TMP_ARCHIVE="${ARCHIVE}${TMP_SUFFIX}"
TMP_CHECKSUM="${CHECKSUM}${TMP_SUFFIX}"
TMP_MANIFEST="${MANIFEST}${TMP_SUFFIX}"

cleanup() {
  rm -f \
    "$TMP_ARCHIVE" \
    "$TMP_CHECKSUM" \
    "$TMP_MANIFEST"
}

trap cleanup EXIT INT TERM HUP

for target in \
  "$ARCHIVE" \
  "$CHECKSUM" \
  "$MANIFEST"
do
  if [[ -e "$target" && "$FORCE" -ne 1 ]]; then
    image_die "Target already exists: ${target}. Use --force to replace the exact artifact set."
  fi
done

if [[ "$FORCE" -eq 1 ]]; then
  rm -f \
    "$ARCHIVE" \
    "$CHECKSUM" \
    "$MANIFEST"
fi

CORE_ID="$(
  docker image inspect \
    "$CORE_IMAGE" \
    --format '{{.Id}}' \
    2>/dev/null
)" || image_die "Core image is unavailable: ${CORE_IMAGE}"

TELESCOPE_ID="$(
  docker image inspect \
    "$TELESCOPE_IMAGE" \
    --format '{{.Id}}' \
    2>/dev/null
)" || image_die "Telescope image is unavailable: ${TELESCOPE_IMAGE}"

image_validate_image_id "$CORE_ID" ||
  image_die "Invalid core image ID: ${CORE_ID}"

image_validate_image_id "$TELESCOPE_ID" ||
  image_die "Invalid Telescope image ID: ${TELESCOPE_ID}"

CORE_SIZE="$(
  docker image inspect \
    "$CORE_IMAGE" \
    --format '{{.Size}}'
)"

TELESCOPE_SIZE="$(
  docker image inspect \
    "$TELESCOPE_IMAGE" \
    --format '{{.Size}}'
)"

CORE_CREATED="$(
  docker image inspect \
    "$CORE_IMAGE" \
    --format '{{.Created}}'
)"

TELESCOPE_CREATED="$(
  docker image inspect \
    "$TELESCOPE_IMAGE" \
    --format '{{.Created}}'
)"

DOCKER_SERVER_VERSION="$(
  docker info \
    --format '{{.ServerVersion}}'
)"

echo "project_version=$ENDO_EXO_VERSION"
echo "git_commit=$GIT_COMMIT_FULL"
echo "core_image=$CORE_IMAGE"
echo "core_image_id=$CORE_ID"
echo "telescope_image=$TELESCOPE_IMAGE"
echo "telescope_image_id=$TELESCOPE_ID"
echo "archive=$ARCHIVE"

echo
echo "===== STORAGE BEFORE EXPORT ====="

df -h "$OUTPUT_DIR"

echo
echo "===== EXPORT ====="

docker save \
  "$CORE_IMAGE" \
  "$TELESCOPE_IMAGE" |
gzip -n -1 \
  > "$TMP_ARCHIVE"

echo "docker_export_exit=0"

gzip -t "$TMP_ARCHIVE"

echo "gzip_test_exit=0"

ARCHIVE_SHA256="$(
  sha256sum "$TMP_ARCHIVE" |
  awk '{print $1}'
)"

image_validate_sha256 "$ARCHIVE_SHA256" ||
  image_die "Invalid SHA-256 generated for archive"

ARCHIVE_BYTES="$(
  stat -c '%s' "$TMP_ARCHIVE"
)"

ARCHIVE_NAME="$(basename "$ARCHIVE")"

printf '%s  %s\n' \
  "$ARCHIVE_SHA256" \
  "$ARCHIVE_NAME" \
  > "$TMP_CHECKSUM"

{
  echo "FORMAT_VERSION=1"
  echo "EXPORT_COMPLETE=1"
  echo "PROJECT_NAME=Endo-exo"
  echo "PROJECT_VERSION=$ENDO_EXO_VERSION"
  echo "GIT_COMMIT=$GIT_COMMIT_FULL"
  echo "GIT_COMMIT_SHORT=$GIT_COMMIT_SHORT"
  echo "CREATED_AT=$(date -Is)"
  echo "CREATED_ON=$(hostname)"
  echo "DOCKER_SERVER_VERSION=$DOCKER_SERVER_VERSION"
  echo "COMPRESSION=gzip"
  echo "CORE_IMAGE=$CORE_IMAGE"
  echo "CORE_IMAGE_ID=$CORE_ID"
  echo "CORE_IMAGE_SIZE_BYTES=$CORE_SIZE"
  echo "CORE_IMAGE_CREATED=$CORE_CREATED"
  echo "TELESCOPE_IMAGE=$TELESCOPE_IMAGE"
  echo "TELESCOPE_IMAGE_ID=$TELESCOPE_ID"
  echo "TELESCOPE_IMAGE_SIZE_BYTES=$TELESCOPE_SIZE"
  echo "TELESCOPE_IMAGE_CREATED=$TELESCOPE_CREATED"
  echo "ARCHIVE_FILE=$ARCHIVE_NAME"
  echo "ARCHIVE_SIZE_BYTES=$ARCHIVE_BYTES"
  echo "ARCHIVE_SHA256=$ARCHIVE_SHA256"
  echo "CHECKSUM_FILE=$(basename "$CHECKSUM")"
} > "$TMP_MANIFEST"

mv "$TMP_ARCHIVE" "$ARCHIVE"
mv "$TMP_CHECKSUM" "$CHECKSUM"

(
  cd "$OUTPUT_DIR"
  sha256sum -c "$(basename "$CHECKSUM")"
)

echo "sha256_verify_exit=0"

mv "$TMP_MANIFEST" "$MANIFEST"

trap - EXIT INT TERM HUP

echo
echo "===== EXPORTED ARTIFACTS ====="

ls -lh \
  "$ARCHIVE" \
  "$CHECKSUM" \
  "$MANIFEST"

echo
echo "archive=$ARCHIVE"
echo "checksum=$CHECKSUM"
echo "manifest=$MANIFEST"
echo "archive_sha256=$ARCHIVE_SHA256"
echo "export_final_status=OK"
