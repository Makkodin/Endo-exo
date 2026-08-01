#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/image_common.sh"

if [[ -s "$SLURM_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$SLURM_CONFIG"
fi

usage() {
  cat <<'USAGE'
Usage:
  bash 4.Scripts/docker/distribute_images_slurm.sh \
    --archive FILE \
    (--nodes NODE1,NODE2 | --available-nodes) \
    [options]

Required:
  --archive FILE        Shared .tar.gz Docker image archive.

Node selection:
  --nodes LIST          Comma-separated Slurm node list.
  --available-nodes     Examine all nodes in the selected partition.

Options:
  --partition NAME      Slurm partition.
  --max-parallel N      Concurrent node installations. Default: 1.
  --time TIME           Time limit per node. Default: 00:30:00.
  --mem MEMORY          Memory per node task. Default: 2G.
  --ids-only            Skip full runtime tests after loading.
  --replace-tags        Permit replacement of mismatching local image tags.
  --log-dir DIR         Directory for logs and summary.
  -h, --help            Show this help message.

Exit status:
  0  All eligible selected nodes succeeded.
  1  At least one eligible node failed.
  3  No failures, but at least one selected node was skipped.
USAGE
}

ARCHIVE=""
NODE_LIST="${SLURM_NODELIST:-}"
AVAILABLE_NODES=0
NODE_LIST_FROM_CLI=0
PARTITION="${SLURM_PARTITION:-}"
MAX_PARALLEL=1
TASK_TIME="00:30:00"
TASK_MEM="2G"
IDS_ONLY=0
REPLACE_TAGS=0
LOG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] ||
        image_die "--archive requires a value"

      ARCHIVE="$2"
      shift 2
      ;;

    --nodes)
      [[ $# -ge 2 ]] ||
        image_die "--nodes requires a value"

      if [[ "$AVAILABLE_NODES" -eq 1 ]]; then
        image_die "Use either --nodes or --available-nodes, not both"
      fi

      NODE_LIST="$2"
      NODE_LIST_FROM_CLI=1
      shift 2
      ;;

    --available-nodes)
      if [[ "$NODE_LIST_FROM_CLI" -eq 1 ]]; then
        image_die "Use either --nodes or --available-nodes, not both"
      fi

      AVAILABLE_NODES=1
      NODE_LIST=""
      shift
      ;;

    --partition)
      [[ $# -ge 2 ]] ||
        image_die "--partition requires a value"

      PARTITION="$2"
      shift 2
      ;;

    --max-parallel)
      [[ $# -ge 2 ]] ||
        image_die "--max-parallel requires a value"

      MAX_PARALLEL="$2"
      shift 2
      ;;

    --time)
      [[ $# -ge 2 ]] ||
        image_die "--time requires a value"

      TASK_TIME="$2"
      shift 2
      ;;

    --mem)
      [[ $# -ge 2 ]] ||
        image_die "--mem requires a value"

      TASK_MEM="$2"
      shift 2
      ;;

    --ids-only)
      IDS_ONLY=1
      shift
      ;;

    --replace-tags)
      REPLACE_TAGS=1
      shift
      ;;

    --log-dir)
      [[ $# -ge 2 ]] ||
        image_die "--log-dir requires a value"

      LOG_DIR="$2"
      shift 2
      ;;

    -h|--help)
      usage
      exit 0
      ;;

    *)
      image_die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$ARCHIVE" ]] ||
  image_die "--archive is required"

[[ -f "$ARCHIVE" ]] ||
  image_die "Archive is unavailable on the submission host: $ARCHIVE"

ARCHIVE="$(readlink -f "$ARCHIVE")"
MANIFEST="${ARCHIVE%.tar.gz}.manifest.env"
CHECKSUM="${ARCHIVE}.sha256"

[[ -f "$MANIFEST" ]] ||
  image_die "Manifest is unavailable: $MANIFEST"

[[ -f "$CHECKSUM" ]] ||
  image_die "Checksum is unavailable: $CHECKSUM"

if [[ "$AVAILABLE_NODES" -eq 0 &&
      -z "$NODE_LIST" ]]; then
  image_die "Specify --nodes or --available-nodes"
fi

image_is_positive_integer "$MAX_PARALLEL" ||
  image_die "--max-parallel must be a positive integer"

image_require_command sinfo
image_require_command srun
image_require_command awk
image_require_command grep
image_require_command sed
image_require_command date
image_require_command hostname
image_require_command readlink

if [[ -z "$LOG_DIR" ]]; then
  LOG_DIR="${LOGS_DIR}/image_distribution/$(date +%Y%m%d_%H%M%S)"
fi

mkdir -p "$LOG_DIR"
LOG_DIR="$(readlink -f "$LOG_DIR")"

SUMMARY="${LOG_DIR}/summary.tsv"
SELECTED="${LOG_DIR}/selected_nodes.tsv"

declare -a NODES=()
declare -a ELIGIBLE_NODES=()
declare -a SKIPPED_NODES=()
declare -a PIDS=()
declare -a BATCH_NODES=()

declare -A NODE_STATE=()
declare -A NODE_REASON=()
declare -A NODE_RESULT=()
declare -A NODE_RC=()

add_unique_node() {
  local candidate="$1"
  local existing

  [[ -n "$candidate" ]] ||
    return 0

  for existing in "${NODES[@]:-}"; do
    [[ "$existing" == "$candidate" ]] &&
      return 0
  done

  NODES+=("$candidate")
}

if [[ "$AVAILABLE_NODES" -eq 1 ]]; then
  SINFO_ARGS=(
    -h
    -N
    -o "%N|%T|%E"
  )

  if [[ -n "$PARTITION" ]]; then
    SINFO_ARGS+=(-p "$PARTITION")
  fi

  while IFS='|' read -r node state reason; do
    add_unique_node "$node"
    NODE_STATE["$node"]="$state"
    NODE_REASON["$node"]="$reason"
  done < <(
    sinfo "${SINFO_ARGS[@]}"
  )
else
  OLD_IFS="$IFS"
  IFS=','
  read -r -a REQUESTED_NODES <<< "$NODE_LIST"
  IFS="$OLD_IFS"

  for node in "${REQUESTED_NODES[@]}"; do
    node="$(
      printf '%s' "$node" |
      sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    )"

    add_unique_node "$node"
  done
fi

[[ "${#NODES[@]}" -gt 0 ]] ||
  image_die "No Slurm nodes were selected"

query_node_state() {
  local node="$1"
  local line

  SINFO_NODE_ARGS=(
    -h
    -N
    -n "$node"
    -o "%N|%T|%E"
  )

  if [[ -n "$PARTITION" ]]; then
    SINFO_NODE_ARGS+=(-p "$PARTITION")
  fi

  line="$(
    sinfo "${SINFO_NODE_ARGS[@]}" |
    sed -n '1p'
  )"

  if [[ -z "$line" ]]; then
    NODE_STATE["$node"]="unknown"
    NODE_REASON["$node"]="node not returned by sinfo"
    return
  fi

  IFS='|' read -r _node _state _reason <<< "$line"

  NODE_STATE["$node"]="$_state"
  NODE_REASON["$node"]="$_reason"
}

node_is_blocked() {
  local raw_state="$1"
  local normalized

  normalized="$(
    printf '%s' "$raw_state" |
    tr '[:upper:]' '[:lower:]' |
    tr -d '*+~#'
  )"

  case "$normalized" in
    *down*|*drain*|*fail*|*maint*|*reboot*|*power*|*unknown*)
      return 0
      ;;

    *)
      return 1
      ;;
  esac
}

printf 'node\tstate\treason\tselection\n' > "$SELECTED"

for node in "${NODES[@]}"; do
  query_node_state "$node"

  state="${NODE_STATE[$node]}"
  reason="${NODE_REASON[$node]}"

  if node_is_blocked "$state"; then
    SKIPPED_NODES+=("$node")
    NODE_RESULT["$node"]="SKIPPED_STATE"
    NODE_RC["$node"]="N/A"

    printf '%s\t%s\t%s\tSKIPPED\n' \
      "$node" \
      "$state" \
      "$reason" \
      >> "$SELECTED"
  else
    ELIGIBLE_NODES+=("$node")
    NODE_RESULT["$node"]="PENDING"
    NODE_RC["$node"]=""

    printf '%s\t%s\t%s\tELIGIBLE\n' \
      "$node" \
      "$state" \
      "$reason" \
      >> "$SELECTED"
  fi
done

echo "archive=$ARCHIVE"
echo "manifest=$MANIFEST"
echo "partition=${PARTITION:-default}"
echo "max_parallel=$MAX_PARALLEL"
echo "log_dir=$LOG_DIR"
echo "selected_nodes=${#NODES[@]}"
echo "eligible_nodes=${#ELIGIBLE_NODES[@]}"
echo "skipped_nodes=${#SKIPPED_NODES[@]}"

echo
echo "===== NODE SELECTION ====="
column -t -s $'\t' "$SELECTED" 2>/dev/null ||
  cat "$SELECTED"

CHILD_PIDS=()

stop_children() {
  local pid

  for pid in "${CHILD_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}

trap stop_children INT TERM HUP

launch_node() {
  local node="$1"
  local safe_node out_log err_log rc_file

  safe_node="$(
    printf '%s' "$node" |
    tr -c 'A-Za-z0-9._-' '_'
  )"

  out_log="${LOG_DIR}/${safe_node}.out"
  err_log="${LOG_DIR}/${safe_node}.err"
  rc_file="${LOG_DIR}/${safe_node}.rc"

  (
    SRUN_ARGS=(
      --nodes=1
      --ntasks=1
      --cpus-per-task=1
      --mem="$TASK_MEM"
      --time="$TASK_TIME"
      --nodelist="$node"
      --job-name="endo_exo_images_${safe_node}"
    )

    if [[ -n "$PARTITION" ]]; then
      SRUN_ARGS+=(--partition="$PARTITION")
    fi

    WORKER_ARGS=(
      "$SCRIPT_DIR"
      "$MANIFEST"
      "$ARCHIVE"
      "$IDS_ONLY"
      "$REPLACE_TAGS"
    )

    srun "${SRUN_ARGS[@]}" \
      bash -c '
        set -u

        script_dir="$1"
        manifest="$2"
        archive="$3"
        ids_only="$4"
        replace_tags="$5"

        echo "hostname=$(hostname)"
        echo "started_at=$(date -Is)"
        echo "archive=$archive"

        if bash "$script_dir/verify_images.sh" \
          --manifest "$manifest" \
          --ids-only
        then
          echo "distribution_node_action=SKIP_ALREADY_MATCHING"
          echo "distribution_node_status=OK"
          echo "finished_at=$(date -Is)"
          exit 0
        fi

        load_args=(
          --archive "$archive"
        )

        if [[ "$ids_only" == "1" ]]; then
          load_args+=(--ids-only)
        fi

        if [[ "$replace_tags" == "1" ]]; then
          load_args+=(--replace-tags)
        fi

        bash "$script_dir/load_images.sh" \
          "${load_args[@]}"

        rc=$?

        if [[ "$rc" -eq 0 ]]; then
          echo "distribution_node_action=LOAD_AND_VERIFY"
          echo "distribution_node_status=OK"
        else
          echo "distribution_node_action=LOAD_AND_VERIFY"
          echo "distribution_node_status=FAILED"
        fi

        echo "finished_at=$(date -Is)"
        exit "$rc"
      ' bash "${WORKER_ARGS[@]}" \
      > "$out_log" \
      2> "$err_log"

    rc=$?
    printf '%s\n' "$rc" > "$rc_file"
  ) &

  pid=$!

  PIDS+=("$pid")
  BATCH_NODES+=("$node")
  CHILD_PIDS+=("$pid")

  echo "started_node=$node pid=$pid"
}

finish_batch() {
  local index pid node safe_node rc_file rc

  for index in "${!PIDS[@]}"; do
    pid="${PIDS[$index]}"
    node="${BATCH_NODES[$index]}"

    wait "$pid" || true

    safe_node="$(
      printf '%s' "$node" |
      tr -c 'A-Za-z0-9._-' '_'
    )"

    rc_file="${LOG_DIR}/${safe_node}.rc"

    if [[ -s "$rc_file" ]]; then
      rc="$(cat "$rc_file")"
    else
      rc=99
    fi

    NODE_RC["$node"]="$rc"

    if [[ "$rc" -eq 0 ]]; then
      NODE_RESULT["$node"]="OK"
    else
      NODE_RESULT["$node"]="FAILED"
    fi

    echo "finished_node=$node exit=$rc"
  done

  PIDS=()
  BATCH_NODES=()
  CHILD_PIDS=()
}

for node in "${ELIGIBLE_NODES[@]}"; do
  launch_node "$node"

  if [[ "${#PIDS[@]}" -ge "$MAX_PARALLEL" ]]; then
    finish_batch
  fi
done

if [[ "${#PIDS[@]}" -gt 0 ]]; then
  finish_batch
fi

trap - INT TERM HUP

printf 'node\tslurm_state\tresult\texit_code\taction\tcore_status\ttelescope_status\tstdout\tstderr\n' \
  > "$SUMMARY"

FAILED_COUNT=0
SKIPPED_COUNT=0
SUCCESS_COUNT=0

for node in "${NODES[@]}"; do
  state="${NODE_STATE[$node]}"
  result="${NODE_RESULT[$node]}"
  rc="${NODE_RC[$node]}"

  safe_node="$(
    printf '%s' "$node" |
    tr -c 'A-Za-z0-9._-' '_'
  )"

  out_log="${LOG_DIR}/${safe_node}.out"
  err_log="${LOG_DIR}/${safe_node}.err"

  action="N/A"
  core_status="N/A"
  telescope_status="N/A"

  if [[ -f "$out_log" ]]; then
    action="$(
      grep '^distribution_node_action=' "$out_log" |
      tail -n 1 |
      cut -d= -f2- ||
      true
    )"

    core_status="$(
      grep '^core_image_status=' "$out_log" |
      tail -n 1 |
      cut -d= -f2- ||
      true
    )"

    telescope_status="$(
      grep '^telescope_image_status=' "$out_log" |
      tail -n 1 |
      cut -d= -f2- ||
      true
    )"

    action="${action:-UNKNOWN}"
    core_status="${core_status:-UNKNOWN}"
    telescope_status="${telescope_status:-UNKNOWN}"
  fi

  case "$result" in
    OK)
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      ;;

    FAILED)
      FAILED_COUNT=$((FAILED_COUNT + 1))
      ;;

    SKIPPED_STATE)
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$node" \
    "$state" \
    "$result" \
    "$rc" \
    "$action" \
    "$core_status" \
    "$telescope_status" \
    "$out_log" \
    "$err_log" \
    >> "$SUMMARY"
done

echo
echo "===== DISTRIBUTION SUMMARY ====="

column -t -s $'\t' "$SUMMARY" 2>/dev/null ||
  cat "$SUMMARY"

echo
echo "success_count=$SUCCESS_COUNT"
echo "failed_count=$FAILED_COUNT"
echo "skipped_count=$SKIPPED_COUNT"
echo "summary=$SUMMARY"

if [[ "$FAILED_COUNT" -gt 0 ]]; then
  echo "distribution_final_status=FAILED"
  exit 1
fi

if [[ "$SKIPPED_COUNT" -gt 0 ]]; then
  echo "distribution_final_status=PARTIAL"
  exit 3
fi

echo "distribution_final_status=OK"
exit 0
