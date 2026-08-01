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

SAMPLE_ID="${1:?Usage: 10_te_expression.sh SAMPLE_ID THREADS}"
THREADS="${2:-8}"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"

BAM="${RESULTS_DIR}/${SAMPLE_ID}/03_star_grch38/${SAMPLE_ID}.Aligned.sortedByCoord.out.bam"
GTF="${REFS_DIR}/TE/te_loci.gtf"
BED="${REFS_DIR}/TE/te_loci.bed"
METADATA="${REFS_DIR}/TE/te_loci.metadata.tsv"
GENCODE_GTF="${REFS_DIR}/GRCh38/gencode.gtf"
GENE_BED="${REFS_DIR}/TE/gencode_gene_regions.bed"
GENE_OVERLAP="${REFS_DIR}/TE/te_loci.gene_overlap.tsv"

OUT_DIR="${RESULTS_DIR}/${SAMPLE_ID}/10_te_expression"
LOG_DIR="${LOGS_DIR}/${SAMPLE_ID}"
mkdir -p "$OUT_DIR" "$LOG_DIR"
LOG_FILE="${LOG_DIR}/10_te_expression.log"

COUNTS="${OUT_DIR}/${SAMPLE_ID}.te_locus_counts.tsv"
OVERVIEW="${OUT_DIR}/${SAMPLE_ID}.te_expression_overview.tsv"
CLASS_SUMMARY="${OUT_DIR}/${SAMPLE_ID}.te_repeat_class_summary.tsv"
FAMILY_SUMMARY="${OUT_DIR}/${SAMPLE_ID}.te_repeat_family_summary.tsv"

log() { echo "[$(date)] $*" | tee -a "$LOG_FILE"; }
: > "$LOG_FILE"

log "TE/repeat expression counting for ${SAMPLE_ID}"
log "PROJECT_DIR=${PROJECT_DIR}"
log "BAM=${BAM}"
log "GTF=${GTF}"

for f in "$BAM" "$GTF" "$METADATA"; do
  [[ -s "$f" ]] || { log "ERROR: missing required file: $f"; exit 1; }
done

if [[ ! -s "${BAM}.bai" ]]; then
  log "Indexing BAM"
  samtools index "$BAM"
fi

if [[ ! -s "$GENE_OVERLAP" && -s "$BED" && -s "$GENCODE_GTF" ]] && command -v bedtools >/dev/null 2>&1; then
  log "Building TE locus gene-overlap annotation flags"
  if [[ ! -s "$GENE_BED" ]]; then
    awk 'BEGIN{FS=OFS="\t"} $3=="gene" {gene=""; if (match($0, /gene_name "[^"]+"/)) {gene=substr($0, RSTART+11, RLENGTH-12)} else if (match($0, /gene_id "[^"]+"/)) {gene=substr($0, RSTART+9, RLENGTH-10)} else {gene="gene"} print $1, $4-1, $5, gene, ".", $7}' "$GENCODE_GTF" > "$GENE_BED"
  fi
  tmp="${GENE_OVERLAP}.tmp"
  bedtools intersect -a "$BED" -b "$GENE_BED" -wa -wb > "$tmp" || true
  "${PYTHON_BIN}" - "$BED" "$tmp" "$GENE_OVERLAP" <<'PY'
import csv, sys
from pathlib import Path
bed, inter, out = map(Path, sys.argv[1:4])
all_ids=[]
with bed.open() as fh:
    for line in fh:
        if line.strip():
            parts=line.rstrip('\n').split('\t')
            all_ids.append(parts[3])
map_genes={x:set() for x in all_ids}
if inter.exists() and inter.stat().st_size:
    with inter.open() as fh:
        for line in fh:
            p=line.rstrip('\n').split('\t')
            if len(p)>=14:
                locus=p[3]
                gene=p[12]
                map_genes.setdefault(locus,set()).add(gene)
with out.open('w', newline='') as fo:
    w=csv.writer(fo, delimiter='\t')
    w.writerow(['locus_id','overlaps_gene','n_overlapping_genes','overlapping_genes'])
    for locus in all_ids:
        genes=sorted(g for g in map_genes.get(locus,set()) if g)
        w.writerow([locus, 'true' if genes else 'false', len(genes), ','.join(genes[:20])])
PY
  rm -f "$tmp"
elif [[ ! -s "$GENE_OVERLAP" ]]; then
  log "WARN: gene-overlap flags were not created; bedtools or GENCODE GTF is missing"
fi

if [[ "${FORCE:-0}" != "1" && -s "$COUNTS" && -s "$OVERVIEW" && -s "$CLASS_SUMMARY" && -s "$FAMILY_SUMMARY" ]]; then
  log "SKIP TE expression: outputs already exist"
  ls -lh "$COUNTS" "$OVERVIEW" "$CLASS_SUMMARY" "$FAMILY_SUMMARY" | tee -a "$LOG_FILE"
  exit 0
fi

log "Running featureCounts for TE/repeat loci"
featureCounts \
  -T "$THREADS" \
  -p \
  --countReadPairs \
  -O \
  -M \
  --fraction \
  -t exon \
  -g gene_id \
  -a "$GTF" \
  -o "$COUNTS" \
  "$BAM" \
  2>&1 | tee -a "$LOG_FILE"

log "Summarizing TE/repeat expression"
"${PYTHON_BIN}" "${PROJECT_DIR}/4.Scripts/pipeline/te/10_summarize_te_expression.py" \
  --sample "$SAMPLE_ID" \
  --counts "$COUNTS" \
  --metadata "$METADATA" \
  --gene-overlap "$GENE_OVERLAP" \
  --library-size "${RESULTS_DIR}/${SAMPLE_ID}/qc/${SAMPLE_ID}.library_size.tsv" \
  --out-dir "$OUT_DIR" \
  2>&1 | tee -a "$LOG_FILE"

log "TE/repeat expression done"
head -20 "$CLASS_SUMMARY" | tee -a "$LOG_FILE" || true
