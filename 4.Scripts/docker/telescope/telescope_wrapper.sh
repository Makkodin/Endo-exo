#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/tmp}"
if [[ "$HOME" == "/" || ! -w "$HOME" ]]; then
  export HOME="/tmp"
fi

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/.cache}"
mkdir -p "$XDG_CACHE_HOME" 2>/dev/null || true

exec /opt/conda/bin/python -m telescope "$@"
