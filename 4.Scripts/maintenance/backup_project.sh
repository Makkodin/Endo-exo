#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
OUTPUT="${1:-${PROJECT_DIR}/Endo-exo_code_$(date +%Y%m%d_%H%M%S).tar.gz}"

case "$OUTPUT" in
  /*) ;;
  *) OUTPUT="${PWD}/${OUTPUT}" ;;
esac

mkdir -p "$(dirname "$OUTPUT")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_ROOT="${TMP_DIR}/Endo-exo"
mkdir -p "$ARCHIVE_ROOT"

tar -C "$PROJECT_DIR" -cf -   --exclude='.git'   --exclude='1.Data/*'   --exclude='2.Results/*'   --exclude='3.Refs/*'   --exclude='_Logs/*'   --exclude='*.zip'   --exclude='*.tar'   --exclude='*.tar.gz'   . | tar -C "$ARCHIVE_ROOT" -xf -

find "$ARCHIVE_ROOT" -type d -empty -exec touch '{}/.gitkeep' \;
tar -C "$TMP_DIR" -czf "$OUTPUT" Endo-exo
tar -tzf "$OUTPUT" >/dev/null
sha256sum "$OUTPUT" > "${OUTPUT}.sha256"

printf 'Archive: %s\n' "$OUTPUT"
printf 'SHA256: %s\n' "${OUTPUT}.sha256"
