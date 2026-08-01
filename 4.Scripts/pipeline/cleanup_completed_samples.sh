#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

SAMPLES=""; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --samples) SAMPLES="${2:?}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) echo "Usage: $0 --samples samples.csv [--dry-run]"; exit 0;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2;;
  esac
done
[[ -n "$SAMPLES" ]] || { echo "ERROR: --samples is required" >&2; exit 2; }
[[ "$SAMPLES" = /* ]] || SAMPLES="${PROJECT_DIR}/${SAMPLES}"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
python3 "${PROJECT_DIR}/4.Scripts/common/validate_samples.py" --samples "$SAMPLES" --format tsv > "$TMP"

REPORT_DIR="${LOGS_DIR}/cleanup"; mkdir -p "$REPORT_DIR"
REPORT="${REPORT_DIR}/cleanup_completed_$(date +%Y%m%d_%H%M%S).tsv"
printf 'sample_id\teligible\taction\texit_code\n' > "$REPORT"
failed=0
while IFS=$'\t' read -r sample input_type sra fq1 fq2; do
  [[ "$sample" == sample ]] && continue
  marker="${RESULTS_DIR}/${sample}/${sample}.features_complete.json"
  eligible=0
  if [[ -s "$marker" ]] && python3 - "$marker" <<'PY_MARKER'
import json,sys
raise SystemExit(0 if json.load(open(sys.argv[1])).get('strict_validation_passed') is True else 1)
PY_MARKER
  then eligible=1; fi
  if [[ "$eligible" != 1 ]]; then
    printf '%s\t0\tskipped_no_strict_marker\t0\n' "$sample" >> "$REPORT"
    continue
  fi
  cmd=(bash "${PROJECT_DIR}/4.Scripts/pipeline/cleanup_sample_heavy_outputs.sh" "$sample")
  [[ "$DRY_RUN" == 1 ]] && cmd+=(--dry-run)
  set +e; "${cmd[@]}"; rc=$?; set -e
  action="deleted"; [[ "$DRY_RUN" == 1 ]] && action="dry_run"
  [[ "$rc" != 0 ]] && { action="failed"; failed=$((failed+1)); }
  printf '%s\t1\t%s\t%s\n' "$sample" "$action" "$rc" >> "$REPORT"
done < "$TMP"
echo "Cleanup table: $REPORT"
[[ "$failed" == 0 ]] || exit 2
