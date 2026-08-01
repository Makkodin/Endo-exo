#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

usage() {
  cat <<HELP
Endo-exo ${ENDO_EXO_VERSION}

Usage:
  bash 4.Scripts/endo-exo.sh COMMAND [options]

Main commands:
  version
  validate-input --samples samples.csv
  doctor [--samples samples.csv]
  run --samples samples.csv [--executor auto|local|slurm] [run options]
  run-local --samples samples.csv [run options]
  run-slurm --samples samples.csv [run options]
  build-tables --samples samples.csv --run-name NAME
  cleanup-sample --sample SAMPLE [--dry-run]
  cleanup-completed --samples samples.csv [--dry-run]
  monitor [--run-dir PATH]
  setup
  prepare-grch38 --fasta /abs/GRCh38.fa --gtf /abs/gencode.gtf [--mode link|copy]
  prepare-references --email EMAIL [--threads N]

Run options:
  --run-name NAME       Output name under 2.Results/Feature_tables/
  --threads N           CPU threads per sample
  --jobs N              Local parallel samples or Slurm array concurrency
  --copy-fastq          Copy local FASTQ into project instead of symlinking
  --clean-incomplete    Remove an incomplete previous sample directory first
  --cleanup-heavy       Delete heavy intermediates only after strict validation
  --keep-heavy          Preserve heavy intermediates (default)

Input CSV must contain exactly: sample,Fq1,Fq2
For SRA, put sra:SRR123456 (or SRR/ERR/DRR accession) in Fq1 and leave Fq2 empty.
HELP
}

need_value(){ [[ $# -ge 2 && -n "$2" ]] || { echo "ERROR: $1 requires a value" >&2; exit 2; }; }
inside_core(){ [[ "${ENDO_EXO_IN_CORE:-0}" == 1 ]]; }


parse_samples_only() {
  SAMPLES=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --samples) need_value "$@"; SAMPLES="$2"; shift 2;;
      *) echo "ERROR: unknown option: $1" >&2; exit 2;;
    esac
  done
  [[ -n "$SAMPLES" ]] || { echo "ERROR: --samples is required" >&2; exit 2; }
}

validate_input() {
  parse_samples_only "$@"
  local path="$SAMPLES"; [[ "$path" = /* ]] || path="${PROJECT_DIR}/${path}"
  python3 "${PROJECT_DIR}/4.Scripts/common/validate_samples.py" --samples "$path" --format summary
}

required_reference_paths() {
  cat <<EOF_PATHS
${REFS_DIR}/GRCh38/STAR_index/Genome
${REFS_DIR}/GRCh38/gencode.gtf
${REFS_DIR}/HPV/bowtie2_index/hpv_curated.1.bt2
${REFS_DIR}/HPV/hpv_genes.gtf
${REFS_DIR}/GRCh38_HPV/STAR_index/Genome
${REFS_DIR}/HERV/herv_loci.gtf
${REFS_DIR}/HERV/herv_loci.metadata.tsv
${REFS_DIR}/TE/te_loci.gtf
${REFS_DIR}/TE/te_loci.metadata.tsv
EOF_PATHS
}

doctor() {
  local samples=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --samples) need_value "$@"; samples="$2"; shift 2;;
      *) echo "ERROR: unknown doctor option: $1" >&2; exit 2;;
    esac
  done
  local failed=0
  echo "version=${ENDO_EXO_VERSION}"
  echo "project_dir=${PROJECT_DIR}"
  echo "data_dir=${DATA_DIR}"
  echo "results_dir=${RESULTS_DIR}"
  echo "refs_dir=${REFS_DIR}"
  echo "logs_dir=${LOGS_DIR}"
  if command -v docker >/dev/null 2>&1; then
    echo "docker=available"
    docker info >/dev/null 2>&1 || { echo "docker_daemon=unavailable"; failed=1; }
  else echo "docker=missing"; failed=1; fi
  if command -v sbatch >/dev/null 2>&1; then echo "slurm=available"; else echo "slurm=not_detected"; fi
  while IFS= read -r f; do
    if [[ -s "$f" ]]; then echo "reference_ok=$f"; else echo "reference_missing=$f"; failed=1; fi
  done < <(required_reference_paths)
  if [[ -n "$samples" ]]; then validate_input --samples "$samples" || failed=1; fi
  [[ "$failed" == 0 ]] || return 2
}

choose_executor() {
  local requested="$1"
  if [[ "$requested" != auto ]]; then printf '%s\n' "$requested"; return; fi
  local enabled="auto"
  [[ -s "$SLURM_CONFIG" ]] && { # shellcheck disable=SC1090
    source "$SLURM_CONFIG"; enabled="${SLURM_ENABLED:-auto}";
  }
  if [[ "$enabled" != 0 ]] && command -v sbatch >/dev/null 2>&1 && command -v squeue >/dev/null 2>&1; then
    printf 'slurm\n'
  else
    printf 'local\n'
  fi
}

run_pipeline() {
  local executor="${DEFAULT_EXECUTOR:-auto}" samples=""; local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --samples) need_value "$@"; samples="$2"; shift 2;;
      --executor) need_value "$@"; executor="$2"; shift 2;;
      --run-name|--threads|--main-threads|--jobs|--main-jobs) need_value "$@"; args+=("$1" "$2"); shift 2;;
      --copy-fastq|--clean-incomplete|--cleanup-heavy|--keep-heavy) args+=("$1"); shift;;
      *) echo "ERROR: unknown run option: $1" >&2; exit 2;;
    esac
  done
  [[ -n "$samples" ]] || { echo "ERROR: --samples is required" >&2; exit 2; }
  executor="$(choose_executor "$executor")"
  case "$executor" in
    local)
      if inside_core; then
        bash "${PROJECT_DIR}/4.Scripts/pipeline/run_batch_samples.sh" "$samples" "${args[@]}"
      else
        bash "${PROJECT_DIR}/4.Scripts/docker/run_in_core.sh" bash 4.Scripts/pipeline/run_batch_samples.sh "$samples" "${args[@]}"
      fi
      ;;
    slurm)
      inside_core && { echo "ERROR: Slurm submission must be started on the host, not inside the core container" >&2; exit 2; }
      bash "${PROJECT_DIR}/4.Scripts/pipeline/run_batch_slurm.sh" "$samples" "${args[@]}"
      ;;
    *) echo "ERROR: executor must be auto, local, or slurm" >&2; exit 2;;
  esac
}

build_tables() {
  local samples="" run_name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --samples) need_value "$@"; samples="$2"; shift 2;;
      --run-name) need_value "$@"; run_name="$2"; shift 2;;
      *) echo "ERROR: unknown build-tables option: $1" >&2; exit 2;;
    esac
  done
  [[ -n "$samples" && -n "$run_name" ]] || { echo "ERROR: --samples and --run-name are required" >&2; exit 2; }
  local host_samples="$samples"; [[ "$host_samples" = /* ]] || host_samples="${PROJECT_DIR}/${host_samples}"
  local tmp="${LOGS_DIR}/_manual_build/${run_name}_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$tmp"
  python3 "${PROJECT_DIR}/4.Scripts/common/validate_samples.py" --samples "$host_samples" --format tsv > "$tmp/samples.normalized.tsv"
  if inside_core; then
    python3 "${PROJECT_DIR}/4.Scripts/pipeline/features/13_build_run_feature_tables.py" --samples-normalized "$tmp/samples.normalized.tsv" --results-dir "$RESULTS_DIR" --run-name "$run_name" --out-dir "${RESULTS_DIR}/Feature_tables/${run_name}"
  else
    local rel_norm="${tmp#${LOGS_DIR}/}"
    bash "${PROJECT_DIR}/4.Scripts/docker/run_in_core.sh" python3 4.Scripts/pipeline/features/13_build_run_feature_tables.py --samples-normalized "/project/_Logs/${rel_norm}/samples.normalized.tsv" --results-dir /project/2.Results --run-name "$run_name" --out-dir "/project/2.Results/Feature_tables/${run_name}"
  fi
}

cleanup_sample() {
  local sample="" dry=0
  while [[ $# -gt 0 ]]; do
    case "$1" in --sample) need_value "$@"; sample="$2"; shift 2;; --dry-run) dry=1; shift;; *) echo "ERROR: unknown cleanup option: $1" >&2; exit 2;; esac
  done
  [[ -n "$sample" ]] || { echo "ERROR: --sample is required" >&2; exit 2; }
  local cmd=(bash "${PROJECT_DIR}/4.Scripts/pipeline/cleanup_sample_heavy_outputs.sh" "$sample")
  [[ "$dry" == 1 ]] && cmd+=(--dry-run)
  "${cmd[@]}"
}

prepare_grch38() {
  local fasta="" gtf="" mode="link"
  while [[ $# -gt 0 ]]; do
    case "$1" in --fasta) need_value "$@"; fasta="$2"; shift 2;; --gtf) need_value "$@"; gtf="$2"; shift 2;; --mode) need_value "$@"; mode="$2"; shift 2;; *) echo "ERROR: unknown option: $1" >&2; exit 2;; esac
  done
  [[ -n "$fasta" && -n "$gtf" ]] || { echo "ERROR: --fasta and --gtf are required" >&2; exit 2; }
  bash "${PROJECT_DIR}/4.Scripts/reference_setup/scripts/00_prepare_grch38_inputs.sh" "$fasta" "$gtf" "$mode"
}

prepare_references() {
  local email="" threads="${THREADS}"
  while [[ $# -gt 0 ]]; do
    case "$1" in --email) need_value "$@"; email="$2"; shift 2;; --threads) need_value "$@"; threads="$2"; shift 2;; *) echo "ERROR: unknown option: $1" >&2; exit 2;; esac
  done
  [[ -n "$email" ]] || { echo "ERROR: --email is required by NCBI Entrez" >&2; exit 2; }
  if inside_core; then bash "${PROJECT_DIR}/4.Scripts/reference_setup/setup_references.sh" "$email" "$threads"; else bash "${PROJECT_DIR}/4.Scripts/docker/run_in_core.sh" bash 4.Scripts/reference_setup/setup_references.sh "$email" "$threads"; fi
}

cmd="${1:-help}"; [[ $# -gt 0 ]] && shift || true
case "$cmd" in
  help|-h|--help) usage;;
  version|--version) echo "Endo-exo ${ENDO_EXO_VERSION}";;
  validate-input) validate_input "$@";;
  doctor) doctor "$@";;
  run) run_pipeline "$@";;
  run-local) run_pipeline --executor local "$@";;
  run-slurm) run_pipeline --executor slurm "$@";;
  build-tables) build_tables "$@";;
  cleanup-sample) cleanup_sample "$@";;
  cleanup-completed) bash "${PROJECT_DIR}/4.Scripts/pipeline/cleanup_completed_samples.sh" "$@";;
  monitor) bash "${PROJECT_DIR}/4.Scripts/pipeline/monitor_slurm_run.sh" "$@";;
  setup) bash "${PROJECT_DIR}/4.Scripts/docker/build_images.sh";;
  prepare-grch38) prepare_grch38 "$@";;
  prepare-references) prepare_references "$@";;
  *) echo "ERROR: unknown command: $cmd" >&2; usage >&2; exit 2;;
esac
