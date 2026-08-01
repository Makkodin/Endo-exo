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

UNMAPPED_DIR="${RESULTS_DIR}/${SAMPLE_ID}/04_unmapped_fastq"
HPV_INDEX="${REFS_DIR}/HPV/bowtie2_index/hpv_curated"

OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/05_hpv_calling"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"

mkdir -p "$OUT_DIR" "$LOG_DIR"

R1="${UNMAPPED_DIR}/${SAMPLE_ID}.unmapped_R1.fastq.gz"
R2="${UNMAPPED_DIR}/${SAMPLE_ID}.unmapped_R2.fastq.gz"

SAM="${OUT_DIR}/${SAMPLE_ID}.hpv.sam"
BAM="${OUT_DIR}/${SAMPLE_ID}.hpv.sorted.bam"

LOG_FILE="${LOG_DIR}/05_hpv_align_call.log"

echo "[$(date)] HPV alignment/calling for ${SAMPLE_ID}" | tee "$LOG_FILE"
echo "PROJECT_DIR=${PROJECT_DIR}" | tee -a "$LOG_FILE"

if [[ ! -s "$R1" ]]; then
  echo "ERROR: missing R1: $R1" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "$R2" ]]; then
  echo "ERROR: missing R2: $R2" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -f "${REFS_DIR}/HPV/hpv_curated.fa" ]]; then
  echo "ERROR: missing HPV FASTA: ${REFS_DIR}/HPV/hpv_curated.fa" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ "${FORCE:-0}" != "1" \
      && -s "$BAM" \
      && -s "${BAM}.bai" \
      && -s "${OUT_DIR}/${SAMPLE_ID}.hpv.idxstats.tsv" \
      && -s "${OUT_DIR}/${SAMPLE_ID}.hpv.depth.tsv" \
      && -s "${OUT_DIR}/${SAMPLE_ID}.hpv_call.tsv" \
      && -s "${OUT_DIR}/${SAMPLE_ID}.hpv_signal_qc.tsv" ]]; then
  echo "[$(date)] SKIP HPV alignment/calling: outputs already exist" | tee -a "$LOG_FILE"
  ls -lh "$BAM" "${BAM}.bai" "${OUT_DIR}/${SAMPLE_ID}.hpv_call.tsv" "${OUT_DIR}/${SAMPLE_ID}.hpv_signal_qc.tsv" | tee -a "$LOG_FILE"
  exit 0
fi

echo "[$(date)] Aligning unmapped reads to HPV database" | tee -a "$LOG_FILE"

bowtie2 \
  -x "$HPV_INDEX" \
  -1 "$R1" \
  -2 "$R2" \
  --very-sensitive-local \
  -p "$THREADS" \
  -S "$SAM" \
  2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Converting SAM to sorted BAM" | tee -a "$LOG_FILE"

samtools view -@ "$THREADS" -bS "$SAM" \
  | samtools sort -@ "$THREADS" -o "$BAM"

samtools index "$BAM"

rm -f "$SAM"

echo "[$(date)] Creating idxstats" | tee -a "$LOG_FILE"

samtools idxstats "$BAM" \
  > "${OUT_DIR}/${SAMPLE_ID}.hpv.idxstats.tsv"

echo "[$(date)] Creating depth table" | tee -a "$LOG_FILE"

samtools depth -a "$BAM" \
  > "${OUT_DIR}/${SAMPLE_ID}.hpv.depth.tsv"

echo "[$(date)] Parsing HPV call" | tee -a "$LOG_FILE"

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/hpv/parse_hpv_call.py" \
  --sample "$SAMPLE_ID" \
  --idxstats "${OUT_DIR}/${SAMPLE_ID}.hpv.idxstats.tsv" \
  --depth "${OUT_DIR}/${SAMPLE_ID}.hpv.depth.tsv" \
  --out-tsv "${OUT_DIR}/${SAMPLE_ID}.hpv_call.tsv" \
  --out-json "${OUT_DIR}/${SAMPLE_ID}.hpv_call.json"

echo "[$(date)] Running HPV signal QC" | tee -a "$LOG_FILE"

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/hpv/05b_hpv_signal_qc.py" \
  --sample "$SAMPLE_ID" \
  --bam "${OUT_DIR}/${SAMPLE_ID}.hpv.sorted.bam" \
  --depth "${OUT_DIR}/${SAMPLE_ID}.hpv.depth.tsv" \
  --out "${OUT_DIR}/${SAMPLE_ID}.hpv_signal_qc.tsv"

echo "[$(date)] HPV signal QC table:" | tee -a "$LOG_FILE"
cat "${OUT_DIR}/${SAMPLE_ID}.hpv_signal_qc.tsv" | tee -a "$LOG_FILE"

echo "[$(date)] HPV calling done" | tee -a "$LOG_FILE"

echo "[$(date)] HPV call table:" | tee -a "$LOG_FILE"
cat "${OUT_DIR}/${SAMPLE_ID}.hpv_call.tsv" | tee -a "$LOG_FILE"
