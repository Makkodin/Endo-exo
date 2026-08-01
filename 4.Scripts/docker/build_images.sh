#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
BUILD_CORE=1; BUILD_TELESCOPE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --core-only) BUILD_TELESCOPE=0; shift ;;
    --telescope-only) BUILD_CORE=0; shift ;;
    --core-image) ENDO_EXO_CORE_IMAGE="${2:?}"; shift 2 ;;
    --telescope-image) ENDO_EXO_TELESCOPE_IMAGE="${2:?}"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--core-only|--telescope-only] [--core-image IMAGE] [--telescope-image IMAGE]"; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
  esac
done
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found" >&2; exit 1; }
[[ "$BUILD_CORE" == 1 ]] && docker build -t "$ENDO_EXO_CORE_IMAGE" "$SCRIPT_DIR/core"
[[ "$BUILD_TELESCOPE" == 1 ]] && docker build -t "$ENDO_EXO_TELESCOPE_IMAGE" "$SCRIPT_DIR/telescope"
printf '[OK] core=%s telescope=%s\n' "$ENDO_EXO_CORE_IMAGE" "$ENDO_EXO_TELESCOPE_IMAGE"
