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

SAMPLE_ID="${1:?Usage: 09_herv_expression.sh SAMPLE_ID THREADS}"
THREADS="${2:-8}"

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

BAM="${RESULTS_DIR}/${SAMPLE_ID}/03_star_grch38/${SAMPLE_ID}.Aligned.sortedByCoord.out.bam"
GTF="${REFS_DIR}/HERV/herv_loci.gtf"
METADATA="${REFS_DIR}/HERV/herv_loci.metadata.tsv"

OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/09_herv_expression"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"

mkdir -p "$OUT_DIR" "$LOG_DIR"

LOG_FILE="${LOG_DIR}/09_herv_expression.log"

COUNTS="${OUT_DIR}/${SAMPLE_ID}.herv_locus_counts.tsv"
OVERVIEW="${OUT_DIR}/${SAMPLE_ID}.herv_expression_overview.tsv"
CLASS_SUMMARY="${OUT_DIR}/${SAMPLE_ID}.herv_repeat_class_summary.tsv"
FAMILY_SUMMARY="${OUT_DIR}/${SAMPLE_ID}.herv_repeat_family_summary.tsv"
NAME_SUMMARY="${OUT_DIR}/${SAMPLE_ID}.herv_repeat_name_summary.tsv"

echo "[$(date)] HERV expression counting for ${SAMPLE_ID}" | tee "$LOG_FILE"
echo "PROJECT_DIR=${PROJECT_DIR}" | tee -a "$LOG_FILE"
echo "BAM=${BAM}" | tee -a "$LOG_FILE"
echo "GTF=${GTF}" | tee -a "$LOG_FILE"

if [[ ! -s "$BAM" ]]; then
  echo "ERROR: missing BAM: $BAM" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "$GTF" ]]; then
  echo "ERROR: missing HERV GTF: $GTF" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "$METADATA" ]]; then
  echo "ERROR: missing HERV metadata: $METADATA" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "${BAM}.bai" ]]; then
  echo "[$(date)] Indexing BAM" | tee -a "$LOG_FILE"
  samtools index "$BAM"
fi

if [[ "${FORCE:-0}" != "1" && -s "$COUNTS" && -s "$OVERVIEW" && -s "$CLASS_SUMMARY" && -s "$FAMILY_SUMMARY" && -s "$NAME_SUMMARY" ]]; then
  echo "[$(date)] SKIP HERV expression: outputs already exist" | tee -a "$LOG_FILE"
  ls -lh "$COUNTS" "$OVERVIEW" "$CLASS_SUMMARY" "$FAMILY_SUMMARY" "$NAME_SUMMARY" | tee -a "$LOG_FILE"
  exit 0
fi

echo "[$(date)] Running featureCounts for HERV loci" | tee -a "$LOG_FILE"

featureCounts \
  -T "$THREADS" \
  -p \
  --countReadPairs \
  -O \
  -M \
  --fraction \
  -t exon \
  -g gene_id \
  -a "$GTF" \
  -o "$COUNTS" \
  "$BAM" \
  2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Summarizing HERV expression" | tee -a "$LOG_FILE"

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/herv/09_summarize_herv_expression.py" \
  --sample "$SAMPLE_ID" \
  --counts "$COUNTS" \
  --metadata "$METADATA" \
  --library-size "${RESULTS_DIR}/${SAMPLE_ID}/qc/${SAMPLE_ID}.library_size.tsv" \
  --out-dir "$OUT_DIR" \
  2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] HERV expression done" | tee -a "$LOG_FILE"

echo "[$(date)] Top HERV repeat names:" | tee -a "$LOG_FILE"
head -20 "${OUT_DIR}/${SAMPLE_ID}.herv_repeat_name_summary.tsv" | tee -a "$LOG_FILE"

echo "[$(date)] Top HERV loci:" | tee -a "$LOG_FILE"
head -20 "${OUT_DIR}/${SAMPLE_ID}.herv_top_loci.tsv" | tee -a "$LOG_FILE"
