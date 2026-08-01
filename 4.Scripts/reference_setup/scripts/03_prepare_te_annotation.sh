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
RMSK_URL="https://hgdownload.soe.ucsc.edu/goldenPath/hg38/database/rmsk.txt.gz"
RMSK_DIR="${REFS_DIR}/UCSC"
RMSK="${RMSK_DIR}/rmsk.txt.gz"
GRCH38_FA="${REFS_DIR}/GRCh38/GRCh38.fa"
TE_DIR="${REFS_DIR}/TE"

mkdir -p "$RMSK_DIR" "$TE_DIR"

if [[ ! -s "$GRCH38_FA" ]]; then
  echo "ERROR: missing GRCh38 FASTA: $GRCH38_FA" >&2
  exit 1
fi

if [[ ! -s "${GRCH38_FA}.fai" ]]; then
  echo "[TE] Building FASTA index: ${GRCH38_FA}.fai"
  samtools faidx "$GRCH38_FA"
fi

if [[ ! -s "$RMSK" ]]; then
  echo "[TE] Downloading UCSC RepeatMasker hg38 rmsk.txt.gz"
  wget -O "$RMSK" "$RMSK_URL"
else
  echo "[TE] Using existing rmsk: $RMSK"
fi

first_contig="$(cut -f1 "${GRCH38_FA}.fai" | head -1)"
chr_style="ensembl"
[[ "$first_contig" == chr* ]] && chr_style="ucsc"

echo "[TE] Reference chromosome style: $chr_style"
"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/reference_setup/scripts/03_prepare_te_annotation.py" \
  --rmsk "$RMSK" \
  --fai "${GRCH38_FA}.fai" \
  --chr-style "$chr_style" \
  --out-dir "$TE_DIR" \
  --classes "LTR,LINE,SINE,DNA,Simple_repeat,Satellite,Low_complexity,RNA,RC,Unknown,Other"

echo "[TE] Annotation is ready: $TE_DIR"
