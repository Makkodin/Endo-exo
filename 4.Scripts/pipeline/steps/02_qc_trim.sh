#!/usr/bin/env bash
set -euo pipefail
SAMPLE_ID="${1:?Usage: $0 SAMPLE THREADS}"
THREADS="${2:-16}"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

RAW_DIR="${DATA_DIR}/fastq_raw/${SAMPLE_ID}"
TRIM_DIR="${DATA_DIR}/fastq_trimmed/${SAMPLE_ID}"
QC_DIR="${RESULTS_DIR}/${SAMPLE_ID}/qc"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"
R1="${RAW_DIR}/${SAMPLE_ID}_R1.fastq.gz"
R2="${RAW_DIR}/${SAMPLE_ID}_R2.fastq.gz"
OUT_R1="${TRIM_DIR}/${SAMPLE_ID}_R1.trimmed.fastq.gz"
OUT_R2="${TRIM_DIR}/${SAMPLE_ID}_R2.trimmed.fastq.gz"
FASTP_JSON="${QC_DIR}/${SAMPLE_ID}.fastp.json"
RAW_STATS="${QC_DIR}/${SAMPLE_ID}.raw_seqkit_stats.tsv"
PROCESSED_STATS="${QC_DIR}/${SAMPLE_ID}.processed_seqkit_stats.tsv"
LIBRARY_SIZE="${QC_DIR}/${SAMPLE_ID}.library_size.tsv"
LOG="${LOG_DIR}/02_qc_trim.log"
mkdir -p "$TRIM_DIR" "$QC_DIR" "$LOG_DIR"
: > "$LOG"
log(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }
for f in "$R1" "$R2"; do [[ -s "$f" ]] || { log "ERROR: FASTQ missing or empty: $f"; exit 1; }; done

write_seqkit_stats(){
  local out="$1"; shift
  seqkit stats -T -a -j "$THREADS" "$@" > "${out}.tmp"
  mv "${out}.tmp" "$out"
}
write_library_size(){
  python3 - "$SAMPLE_ID" "$PROCESSED_STATS" "$LIBRARY_SIZE" "$FASTP_MODE" "$OUT_R1" "$OUT_R2" <<'PY'
import csv, sys
sample, stats_path, out_path, mode, r1, r2 = sys.argv[1:]
with open(stats_path, newline='') as fh:
    rows=list(csv.DictReader(fh, delimiter='\t'))
def n(row):
    for key in ('num_seqs','num_sequences'):
        if key in row: return int(float(row[key]))
    raise SystemExit('ERROR: seqkit stats lacks num_seqs')
r1n=n(rows[0]); r2n=n(rows[1])
with open(out_path,'w',newline='') as out:
    w=csv.writer(out,delimiter='\t',lineterminator='\n')
    w.writerow(['sample_id','library_read_pairs_after_qc','library_R1_records_after_qc','library_R2_records_after_qc','pair_count_consistent','library_unit','library_source','fastp_mode','processed_R1','processed_R2'])
    w.writerow([sample,min(r1n,r2n),r1n,r2n,str(r1n==r2n).lower(),'read_pairs','processed_fastq',mode,r1,r2])
PY
}

if [[ "${FORCE:-0}" != 1 && -s "$OUT_R1" && -s "$OUT_R2" && -s "$LIBRARY_SIZE" && -s "$RAW_STATS" && -s "$PROCESSED_STATS" ]]; then
  log "SKIP: QC outputs already exist"
  exit 0
fi

log "Collecting raw numeric FASTQ statistics"
write_seqkit_stats "$RAW_STATS" "$R1" "$R2"
rm -f "$OUT_R1" "$OUT_R2" "$FASTP_JSON"

case "$FASTP_MODE" in
  skip)
    log "FASTP_MODE=skip: preserving raw reads through symlinks"
    ln -s "$(readlink -f "$R1")" "$OUT_R1"
    ln -s "$(readlink -f "$R2")" "$OUT_R2"
    ;;
  run)
    log "Running fastp; only JSON numerical output is retained"
    cmd=(fastp -i "$R1" -I "$R2" -o "$OUT_R1" -O "$OUT_R2" --thread "$THREADS" --json "$FASTP_JSON" --html "${QC_DIR}/.${SAMPLE_ID}.fastp.tmp.html")
    if [[ "${FASTP_DETECT_ADAPTER:-0}" == 1 ]]; then cmd+=(--detect_adapter_for_pe); else cmd+=(--disable_adapter_trimming); fi
    set +e
    timeout "${FASTP_TIMEOUT_SECONDS:-3600}s" "${cmd[@]}" 2>&1 | tee -a "$LOG"
    status=${PIPESTATUS[0]}
    set -e
    rm -f "${QC_DIR}/.${SAMPLE_ID}.fastp.tmp.html"
    if [[ "$status" -ne 0 || ! -s "$OUT_R1" || ! -s "$OUT_R2" ]]; then
      rm -f "$OUT_R1" "$OUT_R2"
      if [[ "${FASTP_FALLBACK_TO_RAW:-0}" == 1 ]]; then
        log "WARNING: fastp failed; explicit fallback to raw is enabled"
        ln -s "$(readlink -f "$R1")" "$OUT_R1"
        ln -s "$(readlink -f "$R2")" "$OUT_R2"
      else
        log "ERROR: fastp failed and fallback is disabled"
        exit "${status:-1}"
      fi
    fi
    ;;
  *) log "ERROR: FASTP_MODE must be skip or run"; exit 1 ;;
esac

log "Collecting processed numeric FASTQ statistics"
write_seqkit_stats "$PROCESSED_STATS" "$OUT_R1" "$OUT_R2"
write_library_size
log "QC numeric outputs complete"
