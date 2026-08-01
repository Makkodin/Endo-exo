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

SAMPLE_ID="${1:?Usage: 11_telescope_expression.sh SAMPLE_ID THREADS}"
THREADS="${2:-8}"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
HOST_PROJECT_DIR="${HOST_PROJECT_DIR:-$PROJECT_DIR}"
HOST_RESULTS_DIR="${HOST_RESULTS_DIR:-${HOST_PROJECT_DIR}/2.Results}"
HOST_REFS_DIR="${HOST_REFS_DIR:-${HOST_PROJECT_DIR}/3.Refs}"
HOST_LOGS_DIR="${HOST_LOGS_DIR:-${HOST_PROJECT_DIR}/_Logs}"

BAM="${RESULTS_DIR}/${SAMPLE_ID}/03_star_grch38/${SAMPLE_ID}.Aligned.sortedByCoord.out.bam"
TE_GTF="${REFS_DIR}/TE/te_loci.gtf"
TE_META="${REFS_DIR}/TE/te_loci.metadata.tsv"
OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/11_telescope"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"
LOG_FILE="${LOG_DIR}/11_telescope.log"
IMAGE="${TELESCOPE_DOCKER_IMAGE:-${ENDO_EXO_TELESCOPE_IMAGE}}"
USE_DOCKER="${TELESCOPE_USE_DOCKER:-1}"

mkdir -p "$OUT_DIR" "$LOG_DIR"
: > "$LOG_FILE"
log() { echo "[$(date)] $*" | tee -a "$LOG_FILE"; }

log "Telescope TE quantification for ${SAMPLE_ID}"
log "Input BAM=${BAM}"
log "TE GTF=${TE_GTF}"
log "Output=${OUT_DIR}"
log "Host project dir for Docker mounts=${HOST_PROJECT_DIR}"

for f in "$BAM" "$TE_GTF" "$TE_META"; do
  [[ -s "$f" ]] || { log "ERROR: missing required file: $f"; exit 1; }
done

STATUS_FILE="${OUT_DIR}/${SAMPLE_ID}.telescope_status.txt"
REPORT_GLOB="${OUT_DIR}"/*telescope_report*.tsv
OVERVIEW="${OUT_DIR}/${SAMPLE_ID}.telescope_overview.tsv"

if [[ "${FORCE:-0}" != "1" && -s "$OVERVIEW" ]]; then
  log "SKIP Telescope: overview already exists"
  exit 0
fi

NAME_BAM="${OUT_DIR}/${SAMPLE_ID}.for_telescope.namegrouped.bam"

if [[ "$USE_DOCKER" == "1" ]]; then
  export DOCKER_API_VERSION="${DOCKER_API_VERSION:-1.41}"
  command -v docker >/dev/null 2>&1 || { log "ERROR: Docker is required for Telescope run"; exit 1; }
  log "Running Telescope in Docker image: $IMAGE"
  docker run --rm \
  --security-opt seccomp=unconfined \
  -e OPENBLAS_NUM_THREADS=1 \
  -e OMP_NUM_THREADS=1 \
  -e MKL_NUM_THREADS=1 \
  -e NUMEXPR_NUM_THREADS=1 \
    -u "$(id -u):$(id -g)" \
    -v "${HOST_PROJECT_DIR}:/project" \
    -v "${HOST_RESULTS_DIR}:/project/2.Results" \
    -v "${HOST_REFS_DIR}:/project/3.Refs:ro" \
    -v "${HOST_LOGS_DIR}:/project/_Logs" \
    -w /project \
    "$IMAGE" \
    bash -lc "set -euo pipefail; \
      mkdir -p '/project/2.Results/${SAMPLE_ID}/11_telescope'; \
      samtools collate -@ ${THREADS} -o '/project/2.Results/${SAMPLE_ID}/11_telescope/${SAMPLE_ID}.for_telescope.namegrouped.bam' '/project/2.Results/${SAMPLE_ID}/03_star_grch38/${SAMPLE_ID}.Aligned.sortedByCoord.out.bam'; \
      telescope assign --theta_prior 200000 --max_iter 200 --attribute locus_id --outdir '/project/2.Results/${SAMPLE_ID}/11_telescope' '/project/2.Results/${SAMPLE_ID}/11_telescope/${SAMPLE_ID}.for_telescope.namegrouped.bam' '/project/3.Refs/TE/te_loci.gtf'" \
    2>&1 | tee -a "$LOG_FILE"
else
  command -v telescope >/dev/null 2>&1 || { log "ERROR: telescope command not found"; exit 1; }
  command -v samtools >/dev/null 2>&1 || { log "ERROR: samtools command not found"; exit 1; }
  log "Running Telescope locally"
  samtools collate -@ "$THREADS" -o "$NAME_BAM" "$BAM" 2>&1 | tee -a "$LOG_FILE"
  telescope assign --theta_prior 200000 --max_iter 200 --attribute locus_id --outdir "$OUT_DIR" "$NAME_BAM" "$TE_GTF" 2>&1 | tee -a "$LOG_FILE"
fi

REPORT=""
for f in "$OUT_DIR"/*telescope_report*.tsv "$OUT_DIR"/*report*.tsv; do
  if [[ -s "$f" ]]; then REPORT="$f"; break; fi
done

if [[ -z "$REPORT" ]]; then
  log "ERROR: Telescope report TSV not found in $OUT_DIR"
  echo "failed: Telescope report TSV not found" > "$STATUS_FILE"
  exit 1
fi

log "Summarizing Telescope report: $REPORT"
"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/te/11_summarize_telescope.py" \
  --sample "$SAMPLE_ID" \
  --report "$REPORT" \
  --metadata "$TE_META" \
  --library-size "${RESULTS_DIR}/${SAMPLE_ID}/qc/${SAMPLE_ID}.library_size.tsv" \
  --out-dir "$OUT_DIR" \
  2>&1 | tee -a "$LOG_FILE"

echo "completed" > "$STATUS_FILE"
log "Telescope done"
