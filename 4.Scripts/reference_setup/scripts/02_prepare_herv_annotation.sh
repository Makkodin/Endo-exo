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

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

OUT_DIR="${REFS_DIR}/HERV"
GRCH38_FA="${REFS_DIR}/GRCh38/GRCh38.fa"
GRCH38_FAI="${GRCH38_FA}.fai"

RMSK_URL="${RMSK_URL:-https://hgdownload.soe.ucsc.edu/goldenPath/hg38/database/rmsk.txt.gz}"
RMSK_RAW="${OUT_DIR}/rmsk.hg38.txt.gz"

mkdir -p "$OUT_DIR"

echo "[HERV] Project: $PROJECT_DIR"
echo "[HERV] Output:  $OUT_DIR"

if [[ ! -s "$GRCH38_FA" ]]; then
  echo "ERROR: missing GRCh38 FASTA: $GRCH38_FA" >&2
  exit 1
fi

if [[ ! -s "$GRCH38_FAI" ]]; then
  echo "[HERV] Creating FASTA index: $GRCH38_FAI"
  samtools faidx "$GRCH38_FA"
fi

echo "[HERV] Detecting chromosome naming style from $GRCH38_FAI"

if cut -f1 "$GRCH38_FAI" | grep -qx "chr1"; then
  CHR_STYLE="ucsc"
else
  CHR_STYLE="ensembl"
fi

echo "[HERV] Target chromosome style: $CHR_STYLE"

if [[ ! -s "$RMSK_RAW" ]]; then
  echo "[HERV] Downloading UCSC rmsk:"
  echo "[HERV] $RMSK_URL"
  wget -O "$RMSK_RAW" "$RMSK_URL"
else
  echo "[HERV] SKIP download: $RMSK_RAW already exists"
fi

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/reference_setup/scripts/02_prepare_herv_annotation.py" \
  --rmsk "$RMSK_RAW" \
  --fai "$GRCH38_FAI" \
  --chr-style "$CHR_STYLE" \
  --out-dir "$OUT_DIR"

echo "[HERV] Done"
echo "[HERV] Main files:"
ls -lh \
  "${OUT_DIR}/herv_loci.bed" \
  "${OUT_DIR}/herv_loci.gtf" \
  "${OUT_DIR}/herv_loci.metadata.tsv" \
  "${OUT_DIR}/herv_family_summary.tsv"
