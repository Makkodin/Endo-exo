#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/image_common.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash 4.Scripts/docker/verify_images.sh [options]

Options:
  --manifest FILE          Compare local image IDs with an export manifest.
  --core-image IMAGE       Override the configured core image reference.
  --telescope-image IMAGE  Override the configured Telescope image reference.
  --ids-only               Check image presence and IDs without runtime tests.
  -h, --help               Show this help message.
USAGE
}

MANIFEST=""
CORE_IMAGE="$ENDO_EXO_CORE_IMAGE"
TELESCOPE_IMAGE="$ENDO_EXO_TELESCOPE_IMAGE"

CORE_IMAGE_EXPLICIT=0
TELESCOPE_IMAGE_EXPLICIT=0
IDS_ONLY=0
FINAL_RC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      [[ $# -ge 2 ]] ||
        image_die "--manifest requires a value"

      MANIFEST="$2"
      shift 2
      ;;

    --core-image)
      [[ $# -ge 2 ]] ||
        image_die "--core-image requires a value"

      CORE_IMAGE="$2"
      CORE_IMAGE_EXPLICIT=1
      shift 2
      ;;

    --telescope-image)
      [[ $# -ge 2 ]] ||
        image_die "--telescope-image requires a value"

      TELESCOPE_IMAGE="$2"
      TELESCOPE_IMAGE_EXPLICIT=1
      shift 2
      ;;

    --ids-only)
      IDS_ONLY=1
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

EXPECTED_CORE_ID=""
EXPECTED_TELESCOPE_ID=""

if [[ -n "$MANIFEST" ]]; then
  [[ -f "$MANIFEST" ]] ||
    image_die "Manifest file is unavailable: $MANIFEST"

  MANIFEST="$(readlink -f "$MANIFEST")"

  MANIFEST_CORE_IMAGE="$(
    image_manifest_require \
      "$MANIFEST" \
      CORE_IMAGE
  )"

  MANIFEST_TELESCOPE_IMAGE="$(
    image_manifest_require \
      "$MANIFEST" \
      TELESCOPE_IMAGE
  )"

  EXPECTED_CORE_ID="$(
    image_manifest_require \
      "$MANIFEST" \
      CORE_IMAGE_ID
  )"

  EXPECTED_TELESCOPE_ID="$(
    image_manifest_require \
      "$MANIFEST" \
      TELESCOPE_IMAGE_ID
  )"

  image_validate_image_id "$EXPECTED_CORE_ID" ||
    image_die "Invalid CORE_IMAGE_ID in manifest"

  image_validate_image_id "$EXPECTED_TELESCOPE_ID" ||
    image_die "Invalid TELESCOPE_IMAGE_ID in manifest"

  if [[ "$CORE_IMAGE_EXPLICIT" -eq 0 ]]; then
    CORE_IMAGE="$MANIFEST_CORE_IMAGE"
  fi

  if [[ "$TELESCOPE_IMAGE_EXPLICIT" -eq 0 ]]; then
    TELESCOPE_IMAGE="$MANIFEST_TELESCOPE_IMAGE"
  fi
fi

image_check_docker_access ||
  exit 1

echo "core_image=$CORE_IMAGE"
echo "telescope_image=$TELESCOPE_IMAGE"

CORE_ID="$(
  docker image inspect \
    "$CORE_IMAGE" \
    --format '{{.Id}}' \
    2>/dev/null
)"

CORE_INSPECT_RC=$?

if [[ "$CORE_INSPECT_RC" -ne 0 || -z "$CORE_ID" ]]; then
  echo "core_image_status=MISSING"
  FINAL_RC=1
else
  echo "core_image_id=$CORE_ID"

  if [[ -n "$EXPECTED_CORE_ID" &&
        "$CORE_ID" != "$EXPECTED_CORE_ID" ]]; then
    echo "core_image_status=MISMATCH"
    FINAL_RC=1
  else
    echo "core_image_status=OK"
  fi
fi

TELESCOPE_ID="$(
  docker image inspect \
    "$TELESCOPE_IMAGE" \
    --format '{{.Id}}' \
    2>/dev/null
)"

TELESCOPE_INSPECT_RC=$?

if [[ "$TELESCOPE_INSPECT_RC" -ne 0 ||
      -z "$TELESCOPE_ID" ]]; then
  echo "telescope_image_status=MISSING"
  FINAL_RC=1
else
  echo "telescope_image_id=$TELESCOPE_ID"

  if [[ -n "$EXPECTED_TELESCOPE_ID" &&
        "$TELESCOPE_ID" != "$EXPECTED_TELESCOPE_ID" ]]; then
    echo "telescope_image_status=MISMATCH"
    FINAL_RC=1
  else
    echo "telescope_image_status=OK"
  fi
fi

if [[ "$IDS_ONLY" -eq 0 &&
      "$CORE_INSPECT_RC" -eq 0 ]]; then
  echo
  echo "===== CORE RUNTIME ====="

  CORE_OUTPUT="$(
    docker run --rm \
      "$CORE_IMAGE" \
      bash -lc '
        set -eu

        for tool in \
          STAR \
          samtools \
          bowtie2 \
          fastp \
          featureCounts \
          bedtools \
          seqkit \
          python3
        do
          command -v "$tool" >/dev/null 2>&1
          echo "tool_${tool}=present"
        done

        echo "STAR=$(STAR --version)"
        samtools --version | sed -n "1p"
        bowtie2 --version | sed -n "1p"
        fastp --version 2>&1
        featureCounts -v 2>&1 | sed -n "1p"
        bedtools --version
        seqkit version
        python3 --version

        python3 -c "
import Bio
import numpy
import pandas
import pyarrow
import pysam
import scipy
print(\"core_python_imports=OK\")
"
      ' 2>&1
  )"

  CORE_RUNTIME_RC=$?

  printf '%s\n' "$CORE_OUTPUT"

  if [[ "$CORE_RUNTIME_RC" -eq 0 ]]; then
    echo "core_runtime_status=OK"
  else
    echo "core_runtime_status=FAILED"
    FINAL_RC=1
  fi
elif [[ "$IDS_ONLY" -eq 0 ]]; then
  echo "core_runtime_status=SKIPPED_IMAGE_MISSING"
fi

if [[ "$IDS_ONLY" -eq 0 &&
      "$TELESCOPE_INSPECT_RC" -eq 0 ]]; then
  echo
  echo "===== TELESCOPE RUNTIME ====="

  TELESCOPE_OUTPUT="$(
    docker run --rm \
      "$TELESCOPE_IMAGE" \
      bash -lc '
        set -eu

        HELP_FILE="/tmp/telescope_help_$$.txt"
        ASSIGN_FILE="/tmp/telescope_assign_help_$$.txt"

        trap \
          "rm -f \"$HELP_FILE\" \"$ASSIGN_FILE\"" \
          EXIT

        command -v telescope >/dev/null 2>&1
        command -v samtools >/dev/null 2>&1

        test -x /opt/conda/bin/python

        /opt/conda/bin/python --version

        /opt/conda/bin/python -c "
import importlib.metadata as metadata
print(
    \"telescope_package_version=\" +
    metadata.version(\"telescope-ngs\")
)
"

        telescope --help \
          > "$HELP_FILE" \
          2>&1

        grep -Eq \
          "assign|usage|Usage" \
          "$HELP_FILE"

        echo "telescope_help_exit=0"

        telescope assign -h \
          > "$ASSIGN_FILE" \
          2>&1

        grep -Eq \
          "samfile|gtffile|attribute" \
          "$ASSIGN_FILE"

        echo "telescope_assign_help_exit=0"

        samtools --version |
          sed -n "1p"
      ' 2>&1
  )"

  TELESCOPE_RUNTIME_RC=$?

  printf '%s\n' "$TELESCOPE_OUTPUT"

  if [[ "$TELESCOPE_RUNTIME_RC" -eq 0 ]]; then
    echo "telescope_runtime_status=OK"
  else
    echo "telescope_runtime_status=FAILED"
    FINAL_RC=1
  fi
elif [[ "$IDS_ONLY" -eq 0 ]]; then
  echo "telescope_runtime_status=SKIPPED_IMAGE_MISSING"
fi

if [[ "$FINAL_RC" -eq 0 ]]; then
  echo "final_status=OK"
else
  echo "final_status=FAILED"
fi

exit "$FINAL_RC"
