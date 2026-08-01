#!/usr/bin/env bash
set -euo pipefail
SAMPLE_ID="${1:?Usage: $0 SAMPLE THREADS}"; THREADS="${2:-16}"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/4.Scripts/common/load_config.sh"
BAM="${RESULTS_DIR}/${SAMPLE_ID}/03_star_grch38/${SAMPLE_ID}.Aligned.sortedByCoord.out.bam"
STAR_COUNTS="${RESULTS_DIR}/${SAMPLE_ID}/03_star_grch38/${SAMPLE_ID}.ReadsPerGene.out.tab"
GTF="${REFS_DIR}/GRCh38/gencode.gtf"
LIBRARY="${RESULTS_DIR}/${SAMPLE_ID}/qc/${SAMPLE_ID}.library_size.tsv"
OUT="${RESULTS_DIR}/${SAMPLE_ID}/08_human_gene_expression"
LOG="${LOGS_DIR}/${SAMPLE_ID}/04_human_gene_expression.log"
COUNTS="${OUT}/${SAMPLE_ID}.human_gene_featurecounts.tsv"
NORM="${OUT}/${SAMPLE_ID}.human_gene_counts.normalized.tsv"
mkdir -p "$OUT" "$(dirname "$LOG")"; : > "$LOG"
log(){ echo "[$(date -Is)] $*" | tee -a "$LOG"; }
for f in "$BAM" "$STAR_COUNTS" "$GTF" "$LIBRARY"; do [[ -s "$f" ]] || { log "ERROR: missing $f"; exit 1; }; done
if [[ "${FORCE:-0}" != 1 && -s "$COUNTS" && -s "$NORM" ]]; then log "SKIP: human gene outputs exist"; exit 0; fi
featureCounts -T "$THREADS" -p --countReadPairs -B -C -Q "${GENE_FEATURECOUNTS_MIN_MAPQ}" -s "${GENE_FEATURECOUNTS_STRAND}" \
  -t exon -g gene_id -a "$GTF" -o "$COUNTS" "$BAM" 2>&1 | tee -a "$LOG"
python3 "${PROJECT_DIR}/4.Scripts/pipeline/gene/04_summarize_human_gene_expression.py" \
  --sample "$SAMPLE_ID" --counts "$COUNTS" --star-gene-counts "$STAR_COUNTS" --gtf "$GTF" --library-size "$LIBRARY" --out-dir "$OUT" 2>&1 | tee -a "$LOG"
log "Human gene quantification complete"
