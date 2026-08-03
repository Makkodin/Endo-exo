#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo '[1/7] Bash syntax'
while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find 4.Scripts -type f -name '*.sh' -print0)
bash -n 4.Scripts/runtime_bin/STAR

echo '[2/7] Python syntax'
python3 -m compileall -q 4.Scripts

echo '[3/7] CLI version'
[[ "$(bash 4.Scripts/endo-exo.sh version)" == 'Endo-exo 3.0.0' ]]

echo '[4/7] SRA input parser'
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf 'sample,Fq1,Fq2\nsmoke_sra,sra:SRR123456,\n' > "$tmp"
python3 4.Scripts/common/validate_samples.py \
  --samples "$tmp" \
  --no-check-files \
  --format summary |
  grep -q 'sra=1'

echo '[5/7] Public repository layout'
[[ -s README.md ]]
[[ -s docs/README_EN.md ]]
[[ -s docs/ru/README.md ]]
[[ -s docs/ru/installation-local.md ]]
[[ -s docs/ru/installation-slurm.md ]]
[[ -s docs/ru/docker-images.md ]]
[[ -s docs/ru/verification.md ]]
[[ -s docs/ru/troubleshooting.md ]]
[[ -s docs/en/README.md ]]
[[ -s docs/en/installation-local.md ]]
[[ -s docs/en/installation-slurm.md ]]
[[ -s docs/en/docker-images.md ]]
[[ -s docs/en/verification.md ]]
[[ -s docs/en/troubleshooting.md ]]
[[ -s config/samples.example.csv ]]
[[ -x 4.Scripts/endo-exo.sh ]]
[[ -x 4.Scripts/maintenance/backup_project.sh ]]
[[ -x 4.Scripts/docker/image_common.sh ]]
[[ -x 4.Scripts/docker/export_images.sh ]]
[[ -x 4.Scripts/docker/load_images.sh ]]
[[ -x 4.Scripts/docker/verify_images.sh ]]
[[ -x 4.Scripts/docker/distribute_images_slurm.sh ]]

echo '[6/7] Runtime regression guards'
bash tests/regression_runtime_fixes.sh

echo '[7/7] Sanitized tracked content'
if git grep -n -I -E \
  '/var/ssd/|/mnt/raid|/mnt/ceph|[A-Za-z]:\\Users\\|OneDrive' \
  -- . |
  grep -v '^tests/smoke_test\.sh:'; then
  echo 'ERROR: internal path detected in tracked content' >&2
  exit 2
fi

echo 'SMOKE TEST PASSED'
