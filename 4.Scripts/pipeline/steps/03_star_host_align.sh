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

SAMPLE_ID="${1:?Usage: $0 SAMPLE_ID [THREADS]}"
THREADS="${2:-12}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

TRIM_DIR="${DATA_DIR}/fastq_trimmed/${SAMPLE_ID}"
STAR_INDEX="${REFS_DIR}/GRCh38/STAR_index"
OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/03_star_grch38"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"
LOG_FILE="${LOG_DIR}/03_star_host_align.log"

mkdir -p "$OUT_DIR" "$LOG_DIR"

R1="${TRIM_DIR}/${SAMPLE_ID}_R1.trimmed.fastq.gz"
R2="${TRIM_DIR}/${SAMPLE_ID}_R2.trimmed.fastq.gz"
BAM="${OUT_DIR}/${SAMPLE_ID}.Aligned.sortedByCoord.out.bam"

if [[ ! -s "$R1" || ! -s "$R2" ]]; then
  echo "ERROR: trimmed FASTQ pair not found: $R1 / $R2" | tee "$LOG_FILE"
  exit 1
fi
if [[ ! -s "${STAR_INDEX}/Genome" ]]; then
  echo "ERROR: STAR GRCh38 index not found: ${STAR_INDEX}/Genome" | tee "$LOG_FILE"
  exit 1
fi

if [[ "${FORCE:-0}" != "1" && -s "$BAM" && -s "${BAM}.bai" && -s "${OUT_DIR}/${SAMPLE_ID}.Unmapped.out.mate1" ]]; then
  echo "[$(date)] SKIP STAR host alignment: outputs already exist" | tee "$LOG_FILE"
  exit 0
fi

rm -rf "${OUT_DIR}/${SAMPLE_ID}._STARtmp"

echo "[$(date)] Running STAR human alignment for ${SAMPLE_ID}" | tee "$LOG_FILE"
STAR \
  --runThreadN "$THREADS" \
  --genomeDir "$STAR_INDEX" \
  --readFilesIn "$R1" "$R2" \
  --readFilesCommand zcat \
  --outFileNamePrefix "${OUT_DIR}/${SAMPLE_ID}." \
  --outSAMtype BAM SortedByCoordinate \
  --quantMode GeneCounts \
  --outReadsUnmapped Fastx \
  --outFilterMultimapNmax 100 \
  --winAnchorMultimapNmax 200 \
  --chimSegmentMin 15 \
  --chimJunctionOverhangMin 15 \
  --chimOutType Junctions WithinBAM \
  --chimMultimapNmax 20 \
  --alignSJDBoverhangMin 1 \
  --alignMatesGapMax 1000000 \
  --alignIntronMax 1000000 \
  2>&1 | tee -a "$LOG_FILE"

samtools index "$BAM"
echo "[$(date)] STAR alignment done" | tee -a "$LOG_FILE"
