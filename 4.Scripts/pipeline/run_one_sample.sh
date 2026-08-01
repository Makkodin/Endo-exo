#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
PIPELINE_DIR="${PROJECT_DIR}/4.Scripts/pipeline"

SAMPLE_ID=""; INPUT_TYPE=""; SRA_ACC=""; R1_FASTQ=""; R2_FASTQ=""
RUN_THREADS="${THREADS}"; COPY_FASTQ=0; CLEAN_INCOMPLETE=0
CLEANUP_HEAVY=0; [[ "$HEAVY_FILES_POLICY" == delete ]] && CLEANUP_HEAVY=1

usage(){ cat <<EOF_HELP
Usage:
  $0 --sample ID --input-type fastq --r1 /abs/R1.fastq.gz --r2 /abs/R2.fastq.gz [options]
  $0 --sample ID --input-type sra --sra SRR123 [options]
Options:
  --threads N --copy-fastq --clean-incomplete --cleanup-heavy --keep-heavy
EOF_HELP
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample) SAMPLE_ID="${2:?}"; shift 2;; --input-type) INPUT_TYPE="${2:?}"; shift 2;;
    --sra) SRA_ACC="${2:?}"; shift 2;; --r1) R1_FASTQ="${2:?}"; shift 2;; --r2) R2_FASTQ="${2:?}"; shift 2;;
    --threads|--main-threads) RUN_THREADS="${2:?}"; shift 2;; --copy-fastq) COPY_FASTQ=1; shift;;
    --clean-incomplete) CLEAN_INCOMPLETE=1; shift;; --cleanup-heavy) CLEANUP_HEAVY=1; shift;; --keep-heavy) CLEANUP_HEAVY=0; shift;;
    -h|--help) usage; exit 0;; *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1;;
  esac
done
[[ "$SAMPLE_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: invalid sample" >&2; exit 1; }
[[ "$INPUT_TYPE" == fastq || "$INPUT_TYPE" == sra ]] || { echo "ERROR: input type must be fastq or sra" >&2; exit 1; }
[[ "$RUN_THREADS" =~ ^[0-9]+$ && "$RUN_THREADS" -ge 1 ]] || { echo "ERROR: threads must be positive" >&2; exit 1; }

RAW_DIR="${DATA_DIR}/fastq_raw/${SAMPLE_ID}"; TRIM_DIR="${DATA_DIR}/fastq_trimmed/${SAMPLE_ID}"
RESULT_DIR="${RESULTS_DIR}/${SAMPLE_ID}"; LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"; STATUS_DIR="${RESULT_DIR}/.status"
MARKER="${RESULT_DIR}/${SAMPLE_ID}.features_complete.json"; MAIN_LOG="${LOG_DIR}/run_one_sample.full.log"
if [[ "${FORCE:-0}" != 1 && -s "$MARKER" ]] && python3 -c 'import json,sys; assert json.load(open(sys.argv[1])).get("strict_validation_passed") is True' "$MARKER" 2>/dev/null; then
  echo "[$(date -Is)] SKIP ${SAMPLE_ID}: strict feature marker exists" | tee -a "$MAIN_LOG"
  [[ "$CLEANUP_HEAVY" == 1 ]] && bash "${PIPELINE_DIR}/cleanup_sample_heavy_outputs.sh" "$SAMPLE_ID"
  exit 0
fi
if [[ "$CLEAN_INCOMPLETE" == 1 ]]; then rm -rf "$RESULT_DIR" "$LOG_DIR" "$TRIM_DIR" "$RAW_DIR"; fi
mkdir -p "$RAW_DIR" "$TRIM_DIR" "$RESULT_DIR" "$LOG_DIR" "$STATUS_DIR"
: > "$MAIN_LOG"
log(){ echo "[$(date -Is)] $*" | tee -a "$MAIN_LOG"; }
status(){ printf '%s\t%s\t%s\n' "$2" "$(date -Is)" "${3:-}" > "${STATUS_DIR}/$1.status"; }
fail(){ status sample failed "$1"; log "ERROR: $1"; exit 1; }
trap 'fail "unexpected error at line ${LINENO}"' ERR
run_step(){ local id="$1" label="$2"; shift 2; status "$id" running "$label"; log "STEP $id: $label"; "$@" 2>&1 | tee -a "$MAIN_LOG"; status "$id" done "$label"; }
skip_step(){ status "$1" skipped "$2"; log "SKIP STEP $1: $2"; }

prepare_input(){
  local dst1="${RAW_DIR}/${SAMPLE_ID}_R1.fastq.gz" dst2="${RAW_DIR}/${SAMPLE_ID}_R2.fastq.gz"
  if [[ "$INPUT_TYPE" == sra ]]; then
    [[ "$SRA_ACC" =~ ^[SED]RR[0-9]+$ ]] || fail "invalid SRA accession: $SRA_ACC"
    bash "${PIPELINE_DIR}/steps/01_download_sra.sh" "$SAMPLE_ID" "$SRA_ACC" "$RUN_THREADS"
    local src1="${RAW_DIR}/${SRA_ACC}_1.fastq.gz" src2="${RAW_DIR}/${SRA_ACC}_2.fastq.gz"
    [[ -s "$src1" && -s "$src2" ]] || fail "SRA FASTQ pair missing after download"
    rm -f "$dst1" "$dst2"; ln -s "$(readlink -f "$src1")" "$dst1"; ln -s "$(readlink -f "$src2")" "$dst2"
    R1_FASTQ="$dst1"; R2_FASTQ="$dst2"
  else
    [[ "$R1_FASTQ" = /* && "$R2_FASTQ" = /* ]] || fail "FASTQ paths must be absolute"
    [[ -s "$R1_FASTQ" && -s "$R2_FASTQ" ]] || fail "FASTQ missing or empty"
    rm -f "$dst1" "$dst2"
    if [[ "$COPY_FASTQ" == 1 ]]; then cp "$R1_FASTQ" "$dst1"; cp "$R2_FASTQ" "$dst2"; else ln -s "$(readlink -f "$R1_FASTQ")" "$dst1"; ln -s "$(readlink -f "$R2_FASTQ")" "$dst2"; fi
  fi
  printf 'sample_id\tinput_type\tsra_accession\tFq1\tFq2\tcopy_fastq\n%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$SAMPLE_ID" "$INPUT_TYPE" "$SRA_ACC" "$R1_FASTQ" "$R2_FASTQ" "$COPY_FASTQ" > "${RESULT_DIR}/${SAMPLE_ID}.input_manifest.tsv"
}

status sample running started
log "Endo-exo ${ENDO_EXO_VERSION}"
log "sample=${SAMPLE_ID} input_type=${INPUT_TYPE} threads=${RUN_THREADS} cleanup_heavy=${CLEANUP_HEAVY}"
run_step 01 "Input FASTQ registration" prepare_input
run_step 02 "Numeric FASTQ QC and optional fastp" bash "${PIPELINE_DIR}/steps/02_qc_trim.sh" "$SAMPLE_ID" "$RUN_THREADS"
run_step 03 "STAR GRCh38 alignment" bash "${PIPELINE_DIR}/steps/03_star_host_align.sh" "$SAMPLE_ID" "$RUN_THREADS"

BAM="${RESULT_DIR}/03_star_grch38/${SAMPLE_ID}.Aligned.sortedByCoord.out.bam"
run_step 04 "Numeric BAM QC" bash -c "samtools flagstat '$BAM' > '${RESULT_DIR}/03_star_grch38/${SAMPLE_ID}.samtools.flagstat.txt'; samtools stats '$BAM' > '${RESULT_DIR}/03_star_grch38/${SAMPLE_ID}.samtools.stats.txt'; samtools idxstats '$BAM' > '${RESULT_DIR}/03_star_grch38/${SAMPLE_ID}.samtools.idxstats.tsv'"
if [[ "$ENABLE_HUMAN_GENE_EXPRESSION" == 1 ]]; then run_step 05 "Human gene expression" bash "${PIPELINE_DIR}/gene/04_human_gene_expression.sh" "$SAMPLE_ID" "$RUN_THREADS"; else skip_step 05 "Human gene expression disabled"; fi

if [[ "$ENABLE_HPV" == 1 ]]; then
  run_step 06 "Prepare unmapped reads" bash "${PIPELINE_DIR}/steps/04_prepare_unmapped_fastq.sh" "$SAMPLE_ID"
  run_step 07 "HPV alignment and signal" bash "${PIPELINE_DIR}/steps/05_hpv_align_call.sh" "$SAMPLE_ID" "$RUN_THREADS"
  run_step 08 "HPV gene expression" bash "${PIPELINE_DIR}/steps/06_hpv_gene_expression.sh" "$SAMPLE_ID" "$RUN_THREADS"
  run_step 09 "HPV final numerical classification" python3 "${PIPELINE_DIR}/hpv/05d_finalize_hpv_status.py" \
    --sample "$SAMPLE_ID" --hpv-call "${RESULT_DIR}/05_hpv_calling/${SAMPLE_ID}.hpv_call.tsv" \
    --signal-qc "${RESULT_DIR}/05_hpv_calling/${SAMPLE_ID}.hpv_signal_qc.tsv" --depth "${RESULT_DIR}/05_hpv_calling/${SAMPLE_ID}.hpv.depth.tsv" \
    --gtf "${REFS_DIR}/HPV/hpv_genes.gtf" --gene-counts "${RESULT_DIR}/06_hpv_expression/${SAMPLE_ID}.hpv_gene_counts.tsv" \
    --out "${RESULT_DIR}/05_hpv_calling/${SAMPLE_ID}.hpv_final_status.tsv"
  run_step 10 "Human-HPV junction candidates" bash "${PIPELINE_DIR}/steps/07_star_hpv_integration.sh" "$SAMPLE_ID" "$RUN_THREADS"
else
  for id in 06 07 08 09 10; do skip_step "$id" "HPV module disabled"; done
fi
if [[ "$ENABLE_HERV" == 1 ]]; then run_step 11 "HERV/LTR/ERV featureCounts" bash "${PIPELINE_DIR}/herv/09_herv_expression.sh" "$SAMPLE_ID" "$RUN_THREADS"; else skip_step 11 "HERV disabled"; fi
if [[ "$ENABLE_TE" == 1 ]]; then run_step 12 "Broad TE featureCounts" bash "${PIPELINE_DIR}/te/10_te_expression.sh" "$SAMPLE_ID" "$RUN_THREADS"; else skip_step 12 "TE disabled"; fi
if [[ "$ENABLE_TELESCOPE" == 1 ]]; then
  [[ "$ENABLE_TE" == 1 ]] || fail "Telescope requires TE annotation/module"
  run_step 13 "Telescope locus assignment" bash "${PIPELINE_DIR}/te/11_telescope_expression.sh" "$SAMPLE_ID" "${TELESCOPE_THREADS}"
else skip_step 13 "Telescope disabled"; fi

TECH="${RESULT_DIR}/${SAMPLE_ID}.technical_features.tsv"
run_step 14 "Collect all technical features before cleanup" python3 "${PIPELINE_DIR}/features/12_collect_sample_technical_features.py" \
  --sample "$SAMPLE_ID" --sample-dir "$RESULT_DIR" --log-dir "$LOG_DIR" \
  --r1 "$R1_FASTQ" --r2 "$R2_FASTQ" --input-type "$INPUT_TYPE" --sra "$SRA_ACC" --checksum-mode "$INPUT_CHECKSUM_MODE" \
  --out "$TECH" --inventory-out "${RESULT_DIR}/${SAMPLE_ID}.file_inventory_before_cleanup.tsv" --versions-out "${RESULT_DIR}/${SAMPLE_ID}.software_versions.tsv"
run_step 15 "Collect sample feature row" python3 "${PIPELINE_DIR}/features/12_collect_sample_features.py" --sample "$SAMPLE_ID" --sample-dir "$RESULT_DIR" --technical "$TECH" --out "${RESULT_DIR}/${SAMPLE_ID}.sample_features.tsv"
run_step 16 "Strict feature validation" python3 "${PIPELINE_DIR}/features/12_validate_sample_features.py" \
  --sample "$SAMPLE_ID" --sample-dir "$RESULT_DIR" --enable-human "$ENABLE_HUMAN_GENE_EXPRESSION" --enable-hpv "$ENABLE_HPV" \
  --enable-herv "$ENABLE_HERV" --enable-te "$ENABLE_TE" --enable-telescope "$ENABLE_TELESCOPE" \
  --out "${RESULT_DIR}/${SAMPLE_ID}.feature_validation.tsv" --marker "$MARKER"
status sample done complete; trap - ERR
log "COMPLETE: strict feature marker $MARKER"
if [[ "$CLEANUP_HEAVY" == 1 ]]; then run_step 17 "Validated heavy-file cleanup" bash "${PIPELINE_DIR}/cleanup_sample_heavy_outputs.sh" "$SAMPLE_ID"; fi
