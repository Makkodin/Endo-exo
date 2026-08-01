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

SAMPLE_ID="${1:?Usage: 04_prepare_unmapped_fastq.sh SAMPLE_ID}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

STAR_DIR="${RESULTS_DIR}/${SAMPLE_ID}/03_star_grch38"
OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/04_unmapped_fastq"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"

mkdir -p "$OUT_DIR" "$LOG_DIR"

MATE1="${STAR_DIR}/${SAMPLE_ID}.Unmapped.out.mate1"
MATE2="${STAR_DIR}/${SAMPLE_ID}.Unmapped.out.mate2"

OUT_R1="${OUT_DIR}/${SAMPLE_ID}.unmapped_R1.fastq.gz"
OUT_R2="${OUT_DIR}/${SAMPLE_ID}.unmapped_R2.fastq.gz"
STATS="${OUT_DIR}/${SAMPLE_ID}.unmapped_stats.tsv"

LOG_FILE="${LOG_DIR}/04_prepare_unmapped_fastq.log"

: > "$LOG_FILE"
echo "[$(date)] Preparing unmapped FASTQ for ${SAMPLE_ID}" | tee -a "$LOG_FILE"
echo "PROJECT_DIR=${PROJECT_DIR}" | tee -a "$LOG_FILE"

if [[ "${FORCE:-0}" != "1" && -s "$OUT_R1" && -s "$OUT_R2" && -s "$STATS" ]]; then
  echo "[$(date)] SKIP unmapped FASTQ preparation: outputs already exist" | tee -a "$LOG_FILE"
  ls -lh "$OUT_R1" "$OUT_R2" "$STATS" | tee -a "$LOG_FILE"
  exit 0
fi

if [[ ! -s "$MATE1" ]]; then
  echo "ERROR: not found or empty: $MATE1" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "$MATE2" ]]; then
  echo "ERROR: not found or empty: $MATE2" | tee -a "$LOG_FILE"
  exit 1
fi

command -v seqkit >/dev/null 2>&1 || {
  echo "ERROR: command not found: seqkit" | tee -a "$LOG_FILE"
  exit 1
}

echo "[$(date)] Compressing STAR unmapped mate files" | tee -a "$LOG_FILE"

gzip -c "$MATE1" > "$OUT_R1"
gzip -c "$MATE2" > "$OUT_R2"

echo "[$(date)] Created:" | tee -a "$LOG_FILE"
ls -lh "$OUT_R1" "$OUT_R2" | tee -a "$LOG_FILE"

echo "[$(date)] Running seqkit stats" | tee -a "$LOG_FILE"

seqkit stats "$OUT_R1" "$OUT_R2" > "$STATS"
cat "$STATS" | tee -a "$LOG_FILE"

echo "[$(date)] Done" | tee -a "$LOG_FILE"
