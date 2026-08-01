#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: neither python3 nor python found in PATH" >&2
    exit 1
  fi
fi
export PYTHON_BIN

GRCH38_FASTA="${1:?Usage: $0 GRCh38.fa gencode.gtf [copy|link]}"
GENCODE_GTF="${2:?Usage: $0 GRCh38.fa gencode.gtf [copy|link]}"
MODE="${3:-link}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

mkdir -p "${REFS_DIR}/GRCh38"

if [[ ! -s "$GRCH38_FASTA" ]]; then
  echo "ERROR: GRCh38 FASTA not found: $GRCH38_FASTA" >&2
  exit 1
fi

if [[ ! -s "$GENCODE_GTF" ]]; then
  echo "ERROR: GENCODE GTF not found: $GENCODE_GTF" >&2
  exit 1
fi

if [[ "$MODE" == "copy" ]]; then
  cp -f "$GRCH38_FASTA" "${REFS_DIR}/GRCh38/GRCh38.fa"
  cp -f "$GENCODE_GTF" "${REFS_DIR}/GRCh38/gencode.gtf"
else
  ln -sf "$(readlink -f "$GRCH38_FASTA")" "${REFS_DIR}/GRCh38/GRCh38.fa"
  ln -sf "$(readlink -f "$GENCODE_GTF")" "${REFS_DIR}/GRCh38/gencode.gtf"
fi

echo "[OK] ${REFS_DIR}/GRCh38/GRCh38.fa"
echo "[OK] ${REFS_DIR}/GRCh38/gencode.gtf"
