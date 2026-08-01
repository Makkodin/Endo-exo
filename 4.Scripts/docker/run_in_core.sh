#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker command not found" >&2; exit 1; }
[[ $# -gt 0 ]] || set -- bash 4.Scripts/endo-exo.sh --help

DOCKER_ARGS=(
  --rm --init --sig-proxy=true
  -u "$(id -u):$(id -g)"
  -v "${PROJECT_DIR}:/project"
  -w /project
  -e PROJECT_DIR=/project
  -e ENDO_EXO_IN_CORE=1
  -e ENDO_EXO_DATA_DIR=/project/1.Data
  -e ENDO_EXO_RESULTS_DIR=/project/2.Results
  -e ENDO_EXO_REFS_DIR=/project/3.Refs
  -e ENDO_EXO_LOGS_DIR=/project/_Logs
  -e HOST_PROJECT_DIR="${PROJECT_DIR}"
  -e HOST_DATA_DIR="${DATA_DIR}"
  -e HOST_RESULTS_DIR="${RESULTS_DIR}"
  -e HOST_REFS_DIR="${REFS_DIR}"
  -e HOST_LOGS_DIR="${LOGS_DIR}"
  -e HOME=/tmp
  -e XDG_CACHE_HOME=/tmp/.cache
  -e PYTHON_BIN=python3
  -e ENDO_EXO_CORE_IMAGE="${ENDO_EXO_CORE_IMAGE}"
  -e ENDO_EXO_TELESCOPE_IMAGE="${ENDO_EXO_TELESCOPE_IMAGE}"
  -e TELESCOPE_DOCKER_IMAGE="${ENDO_EXO_TELESCOPE_IMAGE}"
  -e DOCKER_API_VERSION="${DOCKER_API_VERSION:-1.41}"
)

add_root_mount() {
  local host="$1" container="$2" mode="$3"
  [[ -n "$host" ]] || return 0
  mkdir -p "$host"
  if [[ "$(readlink -f "$host")" != "$(readlink -f "${PROJECT_DIR}/${container#/project/}" 2>/dev/null || true)" ]]; then
    DOCKER_ARGS+=( -v "${host}:${container}:${mode}" )
  fi
}
add_root_mount "$DATA_DIR" /project/1.Data rw
add_root_mount "$RESULTS_DIR" /project/2.Results rw
add_root_mount "$REFS_DIR" /project/3.Refs ro
add_root_mount "$LOGS_DIR" /project/_Logs rw

SAMPLES_FILE=""
R1_FILE=""
R2_FILE=""
prev=""
for arg in "$@"; do
  case "$prev" in
    --samples) SAMPLES_FILE="$arg" ;;
    --r1) R1_FILE="$arg" ;;
    --r2) R2_FILE="$arg" ;;
  esac
  case "$arg" in --samples|--r1|--r2) prev="$arg" ;; *) prev="" ;; esac
done

mount_dirs=()
if [[ -n "$SAMPLES_FILE" ]]; then
  host_samples="$SAMPLES_FILE"
  [[ "$host_samples" = /* ]] || host_samples="${PROJECT_DIR}/${host_samples}"
  if [[ -s "$host_samples" ]]; then
    while IFS= read -r d; do [[ -n "$d" ]] && mount_dirs+=("$d"); done < <(
      python3 "${PROJECT_DIR}/4.Scripts/common/validate_samples.py" --samples "$host_samples" --format mounts
    )
  fi
fi
for f in "$R1_FILE" "$R2_FILE"; do
  [[ "$f" = /* ]] && mount_dirs+=("$(dirname "$f")")
done
if [[ -n "${ENDO_EXO_FASTQ_MOUNT:-}" ]]; then mount_dirs+=("${ENDO_EXO_FASTQ_MOUNT%%:*}"); fi

declare -A seen_mount=()
for d in "${mount_dirs[@]:-}"; do
  [[ -d "$d" ]] || continue
  real="$(readlink -f "$d")"
  [[ -n "${seen_mount[$real]:-}" ]] && continue
  seen_mount[$real]=1
  DOCKER_ARGS+=( -v "${real}:${real}:ro" )
done

if [[ -n "${ENDO_EXO_EXTRA_MOUNTS:-}" ]]; then
  IFS=',' read -r -a extra_mounts <<< "$ENDO_EXO_EXTRA_MOUNTS"
  for m in "${extra_mounts[@]}"; do [[ -n "$m" ]] && DOCKER_ARGS+=( -v "$m" ); done
fi

if [[ -S /var/run/docker.sock ]]; then
  sock_gid="$(stat -c '%g' /var/run/docker.sock)"
  DOCKER_ARGS+=( -v /var/run/docker.sock:/var/run/docker.sock --group-add "$sock_gid" )
fi

STAR_WRAPPER_HOST="${PROJECT_DIR}/4.Scripts/runtime_bin/STAR"
if [[ -s "$STAR_WRAPPER_HOST" ]]; then
  DOCKER_ARGS+=( -v "${STAR_WRAPPER_HOST}:/usr/local/bin/STAR:ro" )
fi
DOCKER_ARGS+=(
  -e REAL_STAR_BIN=/usr/lib/rna-star/bin/STAR-avx2
  -e STAR_MIN_MEM_KB="${STAR_MIN_MEM_KB}"
  -e STAR_WAIT_SEC="${STAR_WAIT_SEC}"
  -e PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
)
[[ -n "${STAR_LOCK_FILE:-}" ]] && DOCKER_ARGS+=( -e STAR_LOCK_FILE="$STAR_LOCK_FILE" )
[[ -t 0 && -t 1 ]] && DOCKER_ARGS+=( -it )

exec docker run --security-opt seccomp=unconfined "${DOCKER_ARGS[@]}" "$ENDO_EXO_CORE_IMAGE" "$@"
