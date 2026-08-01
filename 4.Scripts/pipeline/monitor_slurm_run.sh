#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

RUN_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:?}"; shift 2;;
    -h|--help) echo "Usage: $0 [--run-dir _Logs/_slurm/RUN]"; exit 0;;
    *) [[ -z "$RUN_DIR" ]] && { RUN_DIR="$1"; shift; } || { echo "ERROR: unknown option $1" >&2; exit 2; };;
  esac
done
if [[ -z "$RUN_DIR" && -s "${LOGS_DIR}/_slurm/latest_run_dir.txt" ]]; then RUN_DIR="$(cat "${LOGS_DIR}/_slurm/latest_run_dir.txt")"; fi
[[ -n "$RUN_DIR" ]] || { echo "ERROR: no Slurm run directory supplied or recorded" >&2; exit 2; }
[[ "$RUN_DIR" = /* ]] || RUN_DIR="${PROJECT_DIR}/${RUN_DIR}"
NORMALIZED="${RUN_DIR}/samples.normalized.tsv"; SUBMISSION="${RUN_DIR}/submission.tsv"
[[ -s "$NORMALIZED" && -s "$SUBMISSION" ]] || { echo "ERROR: incomplete Slurm run metadata in $RUN_DIR" >&2; exit 2; }
read -r ARRAY_ID FINAL_ID < <(awk -F'\t' 'NR==2{print $1,$2}' "$SUBMISSION")

echo "Endo-exo Slurm feature run | $(date -Is)"
echo "run_dir=$RUN_DIR"
echo "array_job_id=$ARRAY_ID finalizer_job_id=$FINAL_ID"
if command -v squeue >/dev/null 2>&1; then squeue -j "${ARRAY_ID},${FINAL_ID}" || true; fi
echo
printf '%-5s %-34s %-14s %-26s\n' 'idx' 'sample' 'pipeline' 'last_step'
printf '%-5s %-34s %-14s %-26s\n' '-----' '----------------------------------' '--------------' '--------------------------'
i=0
while IFS=$'\t' read -r sample type sra fq1 fq2; do
  [[ "$sample" == sample ]] && continue; i=$((i+1))
  marker="${RESULTS_DIR}/${sample}/${sample}.features_complete.json"
  sample_status="NOT_STARTED"; step="-"
  if [[ -s "$marker" ]]; then
    if python3 - "$marker" <<'PY'
import json,sys
raise SystemExit(0 if json.load(open(sys.argv[1])).get('strict_validation_passed') is True else 1)
PY
    then sample_status="COMPLETE"; step="strict feature validation"; else sample_status="FAILED_VALIDATION"; fi
  elif [[ -s "${RESULTS_DIR}/${sample}/.status/sample.status" ]]; then
    sample_status="$(cut -f1 "${RESULTS_DIR}/${sample}/.status/sample.status")"
    last="$(find "${RESULTS_DIR}/${sample}/.status" -name '*.status' -type f -printf '%T@ %f\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)"
    step="${last%.status}"
  elif [[ -d "${LOGS_DIR}/${sample}" ]]; then sample_status="STARTED"; fi
  printf '%-5s %-34s %-14s %-26s\n' "$i" "$sample" "$sample_status" "$step"
done < "$NORMALIZED"
