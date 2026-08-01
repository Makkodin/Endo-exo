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

SAMPLE_ID="$1"
THREADS="${2:-8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

BAM="${RESULTS_DIR}/${SAMPLE_ID}/05_hpv_calling/${SAMPLE_ID}.hpv.sorted.bam"
GTF="${REFS_DIR}/HPV/hpv_genes.gtf"

OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/06_hpv_expression"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"

mkdir -p "$OUT_DIR" "$LOG_DIR"

LOG_FILE="${LOG_DIR}/06_hpv_gene_expression.log"

echo "[$(date)] Running HPV gene expression counting for ${SAMPLE_ID}" | tee "$LOG_FILE"

if [[ ! -s "$BAM" ]]; then
  echo "ERROR: missing BAM: $BAM" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "$GTF" ]]; then
  echo "ERROR: missing GTF: $GTF" | tee -a "$LOG_FILE"
  exit 1
fi

COUNTS="${OUT_DIR}/${SAMPLE_ID}.hpv_gene_counts.tsv"

if [[ "${FORCE:-0}" != "1" && -s "$COUNTS" && -s "${COUNTS}.summary" && -s "${OUT_DIR}/${SAMPLE_ID}.hpv_gene_counts.normalized.tsv" ]]; then
  echo "[$(date)] SKIP HPV gene expression: outputs already exist" | tee -a "$LOG_FILE"
  ls -lh "$COUNTS" "${COUNTS}.summary" | tee -a "$LOG_FILE"
  exit 0
fi

featureCounts \
  -T "$THREADS" \
  -p \
  --countReadPairs \
  -O \
  -M \
  --fraction \
  -t CDS \
  -g gene_id \
  -a "$GTF" \
  -o "$COUNTS" \
  "$BAM" \
  2>&1 | tee -a "$LOG_FILE"

python3 "${PROJECT_DIR}/4.Scripts/pipeline/hpv/06_summarize_hpv_gene_expression.py" \
  --sample "$SAMPLE_ID" --counts "$COUNTS" --gtf "$GTF" \
  --library-size "${RESULTS_DIR}/${SAMPLE_ID}/qc/${SAMPLE_ID}.library_size.tsv" --out-dir "$OUT_DIR" \
  2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] HPV gene expression done" | tee -a "$LOG_FILE"
