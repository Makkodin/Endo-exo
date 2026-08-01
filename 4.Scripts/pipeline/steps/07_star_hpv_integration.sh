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
THREADS="${2:-12}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

TRIM_DIR="${DATA_DIR}/fastq_trimmed/${SAMPLE_ID}"
STAR_INDEX="${REFS_DIR}/GRCh38_HPV/STAR_index"

OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/07_hpv_integration"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"

mkdir -p "$OUT_DIR" "$LOG_DIR"

R1="${TRIM_DIR}/${SAMPLE_ID}_R1.trimmed.fastq.gz"
R2="${TRIM_DIR}/${SAMPLE_ID}_R2.trimmed.fastq.gz"

PREFIX="${OUT_DIR}/${SAMPLE_ID}.GRCh38_HPV."

BAM="${PREFIX}Aligned.sortedByCoord.out.bam"
JUNCTION="${PREFIX}Chimeric.out.junction"

CANDIDATES="${OUT_DIR}/${SAMPLE_ID}.hpv_integration_candidates.tsv"
SUMMARY="${OUT_DIR}/${SAMPLE_ID}.hpv_integration_summary.tsv"
LOCI="${OUT_DIR}/${SAMPLE_ID}.hpv_integration_loci.tsv"
ANNOTATED_LOCI="${OUT_DIR}/${SAMPLE_ID}.hpv_integration_loci.annotated.tsv"

LOG_FILE="${LOG_DIR}/07_star_hpv_integration.log"

echo "[$(date)] Running STAR GRCh38+HPV integration detection" | tee "$LOG_FILE"
echo "Sample:  ${SAMPLE_ID}" | tee -a "$LOG_FILE"
echo "Project: ${PROJECT_DIR}" | tee -a "$LOG_FILE"
echo "Threads: ${THREADS}" | tee -a "$LOG_FILE"

if [[ ! -s "$R1" ]]; then
  echo "ERROR: missing R1: $R1" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "$R2" ]]; then
  echo "ERROR: missing R2: $R2" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -s "${STAR_INDEX}/Genome" ]]; then
  echo "ERROR: STAR index not found: ${STAR_INDEX}/Genome" | tee -a "$LOG_FILE"
  echo "Build it first with GRCh38 + HPV reference." | tee -a "$LOG_FILE"
  exit 1
fi

if [[ "${FORCE:-0}" != "1" \
      && -s "$BAM" \
      && -s "${BAM}.bai" \
      && -s "$JUNCTION" \
      && -s "$CANDIDATES" \
      && -s "$SUMMARY" \
      && -s "$LOCI" \
      && -s "$ANNOTATED_LOCI" ]]; then
  echo "[$(date)] SKIP STAR GRCh38+HPV integration detection: outputs already exist" | tee -a "$LOG_FILE"
  ls -lh "$BAM" "$JUNCTION" "$SUMMARY" "$ANNOTATED_LOCI" | tee -a "$LOG_FILE"
  exit 0
fi

STAR \
  --runThreadN "$THREADS" \
  --genomeDir "$STAR_INDEX" \
  --readFilesIn "$R1" "$R2" \
  --readFilesCommand zcat \
  --outFileNamePrefix "$PREFIX" \
  --outSAMtype BAM SortedByCoordinate \
  --outFilterMultimapNmax 100 \
  --winAnchorMultimapNmax 200 \
  --alignSJDBoverhangMin 1 \
  --alignMatesGapMax 1000000 \
  --alignIntronMax 1000000 \
  --chimSegmentMin 12 \
  --chimJunctionOverhangMin 12 \
  --chimOutType Junctions WithinBAM \
  --chimMultimapNmax 20 \
  2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Indexing BAM" | tee -a "$LOG_FILE"

samtools index "$BAM"

echo "[$(date)] Parsing human–HPV junction candidates" | tee -a "$LOG_FILE"

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/integration/07_parse_star_hpv_junctions.py" \
  --sample "$SAMPLE_ID" \
  --junction "$JUNCTION" \
  --out "$CANDIDATES"

echo "[$(date)] Summarizing human–HPV junction candidates" | tee -a "$LOG_FILE"

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/integration/07_summarize_hpv_integration.py" \
  --candidates "$CANDIDATES" \
  --out "$SUMMARY"

echo "[$(date)] Integration candidate summary:" | tee -a "$LOG_FILE"
cat "$SUMMARY" | tee -a "$LOG_FILE"

echo "[$(date)] Clustering human–HPV junction loci" | tee -a "$LOG_FILE"

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/integration/07_cluster_hpv_integration_loci.py" \
  --summary "$SUMMARY" \
  --out "$LOCI" \
  --window 50000 \
  --min-support 2

echo "[$(date)] Integration loci table:" | tee -a "$LOG_FILE"
cat "$LOCI" | tee -a "$LOG_FILE"

echo "[$(date)] Annotating integration loci with GENCODE genes" | tee -a "$LOG_FILE"

"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/integration/07_annotate_hpv_integration_loci.py" \
  --loci "$LOCI" \
  --gtf "${REFS_DIR}/GRCh38/gencode.gtf" \
  --out "$ANNOTATED_LOCI" \
  --window 100000

echo "[$(date)] Annotated integration loci table:" | tee -a "$LOG_FILE"
cat "$ANNOTATED_LOCI" | tee -a "$LOG_FILE"

echo "[$(date)] Done" | tee -a "$LOG_FILE"
