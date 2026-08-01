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

SAMPLE_ID="${1:?Usage: $0 SAMPLE_ID SRA_ACC [THREADS]}"
SRA_ACC="${2:?Usage: $0 SAMPLE_ID SRA_ACC [THREADS]}"
THREADS="${3:-8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

SRA_ROOT="${DATA_DIR}/sra"
SRA_DIR="${SRA_ROOT}/${SRA_ACC}"
FASTQ_DIR="${DATA_DIR}/fastq_raw/${SAMPLE_ID}"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"
LOG_FILE="${LOG_DIR}/01_download_sra.log"

mkdir -p "$SRA_DIR" "$FASTQ_DIR" "$LOG_DIR"

R1_GZ="${FASTQ_DIR}/${SRA_ACC}_1.fastq.gz"
R2_GZ="${FASTQ_DIR}/${SRA_ACC}_2.fastq.gz"

if [[ "${FORCE:-0}" != "1" && -s "$R1_GZ" && -s "$R2_GZ" ]]; then
  echo "[$(date)] SKIP download: FASTQ already exists" | tee "$LOG_FILE"
  ls -lh "$R1_GZ" "$R2_GZ" | tee -a "$LOG_FILE"
  exit 0
fi

for cmd in prefetch fasterq-dump gzip; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: command not found: $cmd" | tee "$LOG_FILE"; exit 1; }
done

echo "[$(date)] Downloading SRA: ${SRA_ACC}" | tee "$LOG_FILE"
prefetch --output-directory "$SRA_ROOT" "$SRA_ACC" 2>&1 | tee -a "$LOG_FILE"

SRA_FILE="$(find "$SRA_DIR" -name "${SRA_ACC}.sra" | head -n 1 || true)"
if [[ ! -s "$SRA_FILE" ]]; then
  echo "ERROR: cannot find downloaded SRA file under $SRA_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

echo "[$(date)] Converting SRA to FASTQ: ${SRA_FILE}" | tee -a "$LOG_FILE"
rm -f "${FASTQ_DIR}/${SRA_ACC}_1.fastq" "${FASTQ_DIR}/${SRA_ACC}_2.fastq" "$R1_GZ" "$R2_GZ"
rm -rf "${FASTQ_DIR}/tmp"
mkdir -p "${FASTQ_DIR}/tmp"

fasterq-dump "$SRA_FILE" \
  --outdir "$FASTQ_DIR" \
  --threads "$THREADS" \
  --split-files \
  --temp "${FASTQ_DIR}/tmp" \
  2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Compressing FASTQ files" | tee -a "$LOG_FILE"
gzip -f "${FASTQ_DIR}"/*.fastq

if [[ ! -s "$R1_GZ" || ! -s "$R2_GZ" ]]; then
  echo "ERROR: SRA run did not produce paired-end split FASTQ files:" | tee -a "$LOG_FILE"
  echo "  expected R1: $R1_GZ" | tee -a "$LOG_FILE"
  echo "  expected R2: $R2_GZ" | tee -a "$LOG_FILE"
  echo "This pipeline currently supports paired-end RNA-seq only." | tee -a "$LOG_FILE"
  echo "Available files in $FASTQ_DIR:" | tee -a "$LOG_FILE"
  ls -lh "$FASTQ_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

echo "[$(date)] FASTQ files:" | tee -a "$LOG_FILE"
ls -lh "$FASTQ_DIR" | tee -a "$LOG_FILE"
