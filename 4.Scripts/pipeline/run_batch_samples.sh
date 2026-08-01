#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
SAMPLES="${1:?Usage: $0 samples.csv [options]}"; shift
RUN_NAME="run_$(date +%Y%m%d_%H%M%S)"; RUN_THREADS="$THREADS"; JOBS="$LOCAL_JOBS"; COPY_FASTQ=0; CLEAN_INCOMPLETE=0; CLEANUP_HEAVY=0
[[ "$HEAVY_FILES_POLICY" == delete ]] && CLEANUP_HEAVY=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-name) RUN_NAME="${2:?}"; shift 2;; --threads|--main-threads) RUN_THREADS="${2:?}"; shift 2;; --jobs|--main-jobs) JOBS="${2:?}"; shift 2;;
    --copy-fastq) COPY_FASTQ=1; shift;; --clean-incomplete) CLEAN_INCOMPLETE=1; shift;; --cleanup-heavy) CLEANUP_HEAVY=1; shift;; --keep-heavy) CLEANUP_HEAVY=0; shift;;
    *) echo "ERROR: unknown option: $1" >&2; exit 1;;
  esac
done
[[ "$SAMPLES" = /* ]] || SAMPLES="${PROJECT_DIR}/${SAMPLES}"
[[ -s "$SAMPLES" ]] || { echo "ERROR: samples file missing: $SAMPLES" >&2; exit 1; }
[[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -ge 1 ]] || { echo "ERROR: jobs must be positive" >&2; exit 1; }
RUN_ID="$(date +%Y%m%d_%H%M%S)"; RUN_DIR="${LOGS_DIR}/_runs/${RUN_NAME}_${RUN_ID}"; mkdir -p "$RUN_DIR"
NORMALIZED="${RUN_DIR}/samples.normalized.tsv"
python3 "${PROJECT_DIR}/4.Scripts/common/validate_samples.py" --samples "$SAMPLES" --format tsv > "$NORMALIZED"
printf '%s\n' "$RUN_DIR" > "${LOGS_DIR}/_runs/latest_run_dir.txt"
cp "$SAMPLES" "${RUN_DIR}/samples.input.csv"

run_row(){
  local sample="$1" type="$2" sra="$3" fq1="$4" fq2="$5"; shift 5
  cmd=(bash "${PROJECT_DIR}/4.Scripts/pipeline/run_one_sample.sh" --sample "$sample" --input-type "$type" --threads "$RUN_THREADS")
  if [[ "$type" == sra ]]; then cmd+=(--sra "$sra"); else cmd+=(--r1 "$fq1" --r2 "$fq2"); fi
  [[ "$COPY_FASTQ" == 1 ]] && cmd+=(--copy-fastq)
  [[ "$CLEAN_INCOMPLETE" == 1 ]] && cmd+=(--clean-incomplete)
  [[ "$CLEANUP_HEAVY" == 1 ]] && cmd+=(--cleanup-heavy) || cmd+=(--keep-heavy)
  "${cmd[@]}" > "${RUN_DIR}/${sample}.batch.log" 2>&1
}

pids=(); names=(); failures=0
reap_one(){
  local i pid name status
  while true; do
    for i in "${!pids[@]}"; do
      pid="${pids[$i]}"; name="${names[$i]}"
      if ! kill -0 "$pid" 2>/dev/null; then
        set +e; wait "$pid"; status=$?; set -e
        [[ "$status" -ne 0 ]] && { echo "[FAILED] $name (exit=$status)"; failures=$((failures+1)); } || echo "[DONE] $name"
        unset 'pids[i]' 'names[i]'; pids=("${pids[@]}"); names=("${names[@]}"); return
      fi
    done
    sleep 2
  done
}

while IFS=$'\t' read -r sample type sra fq1 fq2; do
  [[ "$sample" == sample ]] && continue
  while [[ "${#pids[@]}" -ge "$JOBS" ]]; do reap_one; done
  echo "[START] $sample"
  run_row "$sample" "$type" "$sra" "$fq1" "$fq2" & pids+=("$!"); names+=("$sample")
done < "$NORMALIZED"
while [[ "${#pids[@]}" -gt 0 ]]; do reap_one; done

FEATURE_OUT="${RESULTS_DIR}/Feature_tables/${RUN_NAME}"
set +e
python3 "${PROJECT_DIR}/4.Scripts/pipeline/features/13_build_run_feature_tables.py" --samples-normalized "$NORMALIZED" --results-dir "$RESULTS_DIR" --run-name "$RUN_NAME" --out-dir "$FEATURE_OUT" 2>&1 | tee "${RUN_DIR}/build_feature_tables.log"
build_status=${PIPESTATUS[0]}
set -e
printf 'run_name\trequested_samples\tsample_failures\tfeature_build_exit\tfeature_output\n%s\t%s\t%s\t%s\t%s\n' "$RUN_NAME" "$(( $(wc -l < "$NORMALIZED") - 1 ))" "$failures" "$build_status" "$FEATURE_OUT" > "${RUN_DIR}/run_status.tsv"
if [[ "$failures" -ne 0 || "$build_status" -ne 0 ]]; then exit 2; fi
echo "[COMPLETE] Feature tables: $FEATURE_OUT"
