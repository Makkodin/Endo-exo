#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: neither python3 nor python found in PATH" >&2
    exit 1
  fi
fi
export PYTHON_BIN

EMAIL="${1:?Usage: $0 email threads}"
THREADS="${2:-16}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
export PROJECT_DIR

HPV_ACCESSIONS="${SCRIPT_DIR}/configs/hpv_accessions.tsv"
HPV_DIR="${REFS_DIR}/HPV"
GRCH38_FA="${REFS_DIR}/GRCh38/GRCh38.fa"
GRCH38_GTF="${REFS_DIR}/GRCh38/gencode.gtf"

mkdir -p "${HPV_DIR}" "${REFS_DIR}/GRCh38" "${REFS_DIR}/GRCh38_HPV"

for cmd in "$PYTHON_BIN" bowtie2-build samtools STAR wget featureCounts; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: command not found: $cmd" >&2; exit 1; }
done

if [[ ! -s "$GRCH38_FA" || ! -s "$GRCH38_GTF" ]]; then
  echo "ERROR: missing GRCh38 inputs:" >&2
  echo "  $GRCH38_FA" >&2
  echo "  $GRCH38_GTF" >&2
  echo "Run 00_prepare_grch38_inputs.sh first." >&2
  exit 1
fi

echo "[1/7] Download/build HPV FASTA+GTF"
"${PYTHON_BIN}" "${SCRIPT_DIR}/scripts/01_fetch_hpv_reference_from_ncbi.py" \
  --accessions "$HPV_ACCESSIONS" \
  --out-dir "$HPV_DIR" \
  --email "$EMAIL"

echo "[2/7] Build HPV bowtie2 index"
rm -rf "${HPV_DIR}/bowtie2_index"
mkdir -p "${HPV_DIR}/bowtie2_index"
bowtie2-build "${HPV_DIR}/hpv_curated.fa" "${HPV_DIR}/bowtie2_index/hpv_curated"
samtools faidx "${HPV_DIR}/hpv_curated.fa"

echo "[3/7] Build STAR GRCh38 index if missing"
if [[ ! -s "${REFS_DIR}/GRCh38/STAR_index/Genome" || "${FORCE:-0}" == "1" ]]; then
  rm -rf "${REFS_DIR}/GRCh38/STAR_index"
  mkdir -p "${REFS_DIR}/GRCh38/STAR_index"
  STAR \
    --runThreadN "$THREADS" \
    --runMode genomeGenerate \
    --genomeDir "${REFS_DIR}/GRCh38/STAR_index" \
    --genomeFastaFiles "$GRCH38_FA" \
    --sjdbGTFfile "$GRCH38_GTF" \
    --sjdbOverhang 100
else
  echo "[SKIP] GRCh38 STAR index already exists"
fi

echo "[4/7] Build combined GRCh38+HPV FASTA/GTF"
cat "$GRCH38_FA" "${HPV_DIR}/hpv_curated.fa" > "${REFS_DIR}/GRCh38_HPV/GRCh38_plus_HPV.fa"
cat "$GRCH38_GTF" "${HPV_DIR}/hpv_genes.gtf" > "${REFS_DIR}/GRCh38_HPV/GRCh38_plus_HPV.gtf"

echo "[5/7] Build STAR GRCh38+HPV index"
rm -rf "${REFS_DIR}/GRCh38_HPV/STAR_index"
mkdir -p "${REFS_DIR}/GRCh38_HPV/STAR_index"
STAR \
  --runThreadN "$THREADS" \
  --runMode genomeGenerate \
  --genomeDir "${REFS_DIR}/GRCh38_HPV/STAR_index" \
  --genomeFastaFiles "${REFS_DIR}/GRCh38_HPV/GRCh38_plus_HPV.fa" \
  --sjdbGTFfile "${REFS_DIR}/GRCh38_HPV/GRCh38_plus_HPV.gtf" \
  --sjdbOverhang 100

echo "[6/7] Build HERV/LTR/ERV annotation"
bash "${SCRIPT_DIR}/scripts/02_prepare_herv_annotation.sh"

echo "[7/7] Build broad TE/repeat annotation"
bash "${SCRIPT_DIR}/scripts/03_prepare_te_annotation.sh"

echo "[OK] Reference setup completed"
