#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
SAMPLE_ID="${1:?Usage: $0 SAMPLE [--dry-run]}"; shift || true
DRY_RUN=0
while [[ $# -gt 0 ]]; do case "$1" in --dry-run) DRY_RUN=1; shift;; *) echo "ERROR: unknown option $1" >&2; exit 1;; esac; done
SAMPLE_DIR="${RESULTS_DIR}/${SAMPLE_ID}"; MARKER="${SAMPLE_DIR}/${SAMPLE_ID}.features_complete.json"
for f in "$MARKER" "${SAMPLE_DIR}/${SAMPLE_ID}.feature_validation.tsv" "${SAMPLE_DIR}/${SAMPLE_ID}.technical_features.tsv" "${SAMPLE_DIR}/${SAMPLE_ID}.file_inventory_before_cleanup.tsv"; do
  [[ -s "$f" ]] || { echo "ERROR: cleanup refused; required output missing: $f" >&2; exit 2; }
done
python3 - "$MARKER" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
if d.get('status')!='complete' or d.get('strict_validation_passed') is not True:
    raise SystemExit('ERROR: cleanup refused; strict validation marker is not PASS')
PY
mapfile -d '' result_files < <(find "$SAMPLE_DIR" -type f \( -name '*.bam' -o -name '*.bai' -o -name '*.sam' -o -name '*.cram' -o -name '*.crai' -o -name '*.fastq' -o -name '*.fq' -o -name '*.fastq.gz' -o -name '*.fq.gz' -o -name '*Unmapped.out.mate1' -o -name '*Unmapped.out.mate2' \) -print0)
mapfile -d '' tmp_dirs < <(find "$SAMPLE_DIR" -type d -name '*._STARtmp' -print0)
managed_dirs=("${DATA_DIR}/fastq_raw/${SAMPLE_ID}" "${DATA_DIR}/fastq_trimmed/${SAMPLE_ID}")
bytes=0
for f in "${result_files[@]:-}"; do bytes=$((bytes+$(stat -c '%s' "$f" 2>/dev/null || echo 0))); done
for d in "${managed_dirs[@]}"; do [[ -d "$d" ]] && bytes=$((bytes+$(du -sb "$d" 2>/dev/null | awk '{print $1}' || echo 0))); done
printf 'sample_id\tresult_files\tmanaged_input_dirs\tbytes_to_delete\tdry_run\n%s\t%s\t%s\t%s\t%s\n' "$SAMPLE_ID" "${#result_files[@]}" "${#managed_dirs[@]}" "$bytes" "$DRY_RUN"
if [[ "$DRY_RUN" == 0 ]]; then
  for f in "${result_files[@]:-}"; do rm -f -- "$f"; done
  for d in "${tmp_dirs[@]:-}"; do rm -rf -- "$d"; done
  for d in "${managed_dirs[@]}"; do rm -rf -- "$d"; done
  python3 - "$SAMPLE_ID" "$bytes" "${#result_files[@]}" "${SAMPLE_DIR}/${SAMPLE_ID}.heavy_cleanup.json" <<'PY'
import json,sys
from datetime import datetime,timezone
sample,bytes_,n,out=sys.argv[1:]
json.dump({'sample':sample,'cleanup_status':'complete','deleted_result_files':int(n),'deleted_bytes_estimate':int(bytes_),'completed_at_utc':datetime.now(timezone.utc).isoformat(),'external_fastq_deleted':False},open(out,'w'),indent=2)
PY
fi
