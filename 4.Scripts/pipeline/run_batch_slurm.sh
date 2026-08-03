#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
[[ -s "$SLURM_CONFIG" ]] && source "$SLURM_CONFIG"
SAMPLES="${1:?Usage: $0 samples.csv [options]}"; shift
RUN_NAME="run_$(date +%Y%m%d_%H%M%S)"; RUN_THREADS="$THREADS"; MAX_TASKS="${SLURM_MAX_ARRAY_TASKS:-2}"; COPY_FASTQ=0; CLEAN_INCOMPLETE=0; CLEANUP_HEAVY=0
[[ "$HEAVY_FILES_POLICY" == delete ]] && CLEANUP_HEAVY=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-name) RUN_NAME="${2:?}"; shift 2;; --threads|--main-threads) RUN_THREADS="${2:?}"; shift 2;; --jobs|--main-jobs) MAX_TASKS="${2:?}"; shift 2;;
    --copy-fastq) COPY_FASTQ=1; shift;; --clean-incomplete) CLEAN_INCOMPLETE=1; shift;; --cleanup-heavy) CLEANUP_HEAVY=1; shift;; --keep-heavy) CLEANUP_HEAVY=0; shift;;
    *) echo "ERROR: unknown option: $1" >&2; exit 1;;
  esac
done
command -v sbatch >/dev/null 2>&1 || { echo "ERROR: sbatch not found" >&2; exit 1; }
[[ "$SAMPLES" = /* ]] || SAMPLES="${PROJECT_DIR}/${SAMPLES}"
[[ -s "$SAMPLES" ]] || { echo "ERROR: samples file missing: $SAMPLES" >&2; exit 1; }
RUN_ID="$(date +%Y%m%d_%H%M%S)"; RUN_REL="_slurm/${RUN_NAME}_${RUN_ID}"; RUN_DIR="${LOGS_DIR}/${RUN_REL}"; mkdir -p "$RUN_DIR/slurm_logs"
NORMALIZED="${RUN_DIR}/samples.normalized.tsv"
python3 "${PROJECT_DIR}/4.Scripts/common/validate_samples.py" --samples "$SAMPLES" --format tsv > "$NORMALIZED"
N=$(( $(wc -l < "$NORMALIZED") - 1 )); [[ "$N" -gt 0 ]] || { echo "ERROR: no samples" >&2; exit 1; }
printf '%s\n' "$RUN_DIR" > "${LOGS_DIR}/_slurm/latest_run_dir.txt"
cp "$SAMPLES" "${RUN_DIR}/samples.input.csv"

WORKER="${RUN_DIR}/worker.sh"
cat > "$WORKER" <<EOF_WORKER
#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR=$(printf '%q' "$PROJECT_DIR")
NORMALIZED=$(printf '%q' "$NORMALIZED")
RUN_THREADS=$(printf '%q' "$RUN_THREADS")
COPY_FASTQ=$(printf '%q' "$COPY_FASTQ")
CLEAN_INCOMPLETE=$(printf '%q' "$CLEAN_INCOMPLETE")
CLEANUP_HEAVY=$(printf '%q' "$CLEANUP_HEAVY")
line=\$(awk -v n="\${SLURM_ARRAY_TASK_ID}" 'BEGIN{FS="\\t"} NR==n+1{printf "%s\\034%s\\034%s\\034%s\\034%s\\n", \$1, \$2, \$3, \$4, \$5; exit}' "\$NORMALIZED")
IFS=\$'\\034' read -r sample type sra fq1 fq2 <<< "\$line"
[[ -n "\$sample" ]] || { echo "ERROR: no row for task \${SLURM_ARRAY_TASK_ID}" >&2; exit 2; }
node="\${SLURMD_NODENAME:-\$(hostname)}"; export STAR_LOCK_FILE="/project/_Logs/.star_memory.lock.\${node}"
cmd=(bash "\${PROJECT_DIR}/4.Scripts/docker/run_in_core.sh" bash 4.Scripts/pipeline/run_one_sample.sh --sample "\$sample" --input-type "\$type" --threads "\$RUN_THREADS")
if [[ "\$type" == sra ]]; then cmd+=(--sra "\$sra"); else cmd+=(--r1 "\$fq1" --r2 "\$fq2"); fi
[[ "\$COPY_FASTQ" == 1 ]] && cmd+=(--copy-fastq)
[[ "\$CLEAN_INCOMPLETE" == 1 ]] && cmd+=(--clean-incomplete)
[[ "\$CLEANUP_HEAVY" == 1 ]] && cmd+=(--cleanup-heavy) || cmd+=(--keep-heavy)
echo "[WORKER] sample=\$sample node=\$node command=\${cmd[*]}"
"\${cmd[@]}"
EOF_WORKER
chmod +x "$WORKER"

COMMON=(--parsable)
[[ -n "${SLURM_PARTITION:-}" ]] && COMMON+=(--partition="$SLURM_PARTITION")
[[ -n "${SLURM_ACCOUNT:-}" ]] && COMMON+=(--account="$SLURM_ACCOUNT")
[[ -n "${SLURM_QOS:-}" ]] && COMMON+=(--qos="$SLURM_QOS")
[[ -n "${SLURM_NODELIST:-}" ]] && COMMON+=(--nodelist="$SLURM_NODELIST")
[[ -n "${SLURM_EXCLUDE:-}" ]] && COMMON+=(--exclude="$SLURM_EXCLUDE")
[[ "${SLURM_EXCLUSIVE:-0}" == 1 ]] && COMMON+=(--exclusive)
if [[ -n "${SLURM_EXTRA_ARGS:-}" ]]; then read -r -a extra <<< "$SLURM_EXTRA_ARGS"; COMMON+=("${extra[@]}"); fi

ARRAY_ID=$(sbatch "${COMMON[@]}" --job-name="endo_${RUN_NAME}" --array="1-${N}%${MAX_TASKS}" \
  --cpus-per-task="${SLURM_CPUS_PER_SAMPLE:-$RUN_THREADS}" --mem="${SLURM_MEM_PER_SAMPLE:-76G}" --time="${SLURM_TIME:-72:00:00}" \
  --output="${RUN_DIR}/slurm_logs/%A_%a.out" --error="${RUN_DIR}/slurm_logs/%A_%a.err" "$WORKER")

FINALIZER="${RUN_DIR}/finalize.sh"
NORMALIZED_CONTAINER="/project/_Logs/${RUN_REL}/samples.normalized.tsv"
FEATURE_OUT_CONTAINER="/project/2.Results/Feature_tables/${RUN_NAME}"
cat > "$FINALIZER" <<EOF_FINAL
#!/usr/bin/env bash
set -euo pipefail
cd $(printf '%q' "$PROJECT_DIR")
bash 4.Scripts/docker/run_in_core.sh python3 4.Scripts/pipeline/features/13_build_run_feature_tables.py \\
  --samples-normalized $(printf '%q' "$NORMALIZED_CONTAINER") \\
  --results-dir /project/2.Results --run-name $(printf '%q' "$RUN_NAME") --out-dir $(printf '%q' "$FEATURE_OUT_CONTAINER")
EOF_FINAL
chmod +x "$FINALIZER"
FINAL_ID=$(sbatch "${COMMON[@]}" --dependency="afterany:${ARRAY_ID}" --job-name="endo_finalize_${RUN_NAME}" \
  --cpus-per-task="${SLURM_FINALIZE_CPUS:-4}" --mem="${SLURM_FINALIZE_MEM:-32G}" --time="${SLURM_FINALIZE_TIME:-12:00:00}" \
  --output="${RUN_DIR}/slurm_logs/finalize_%j.out" --error="${RUN_DIR}/slurm_logs/finalize_%j.err" "$FINALIZER")
printf 'array_job_id\tfinalizer_job_id\trun_dir\tfeature_output\n%s\t%s\t%s\t%s\n' "$ARRAY_ID" "$FINAL_ID" "$RUN_DIR" "${RESULTS_DIR}/Feature_tables/${RUN_NAME}" | tee "${RUN_DIR}/submission.tsv"
echo "Monitor: squeue -j ${ARRAY_ID},${FINAL_ID}"
