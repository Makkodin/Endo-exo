#!/usr/bin/env python3
"""Build deterministic HPV FASTA, GenBank, GTF, and accession tables from fixed NCBI accessions."""

import argparse
import csv
import time
from pathlib import Path
from typing import Iterable

from Bio import Entrez, SeqIO

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--accessions', required=True, help='TSV: hpv_type, accession')
    parser.add_argument('--out-dir', required=True, help='Output directory, usually 3.Refs/HPV')
    parser.add_argument('--email', required=True, help='Email for NCBI Entrez')
    parser.add_argument('--sleep', type=float, default=0.35, help='Delay between NCBI requests')
    return parser.parse_args()

def clean_attr(value: str) -> str:
    if not value:
        return 'unknown'
    value = str(value).replace('"', '')
    value = value.replace(';', '_').replace('\t', '_').replace('\n', '_')
    value = value.replace(' ', '_')
    return value

def get_qualifier(feature, keys: Iterable[str], default='unknown') -> str:
    for key in keys:
        if key in feature.qualifiers and feature.qualifiers[key]:
            return feature.qualifiers[key][0]
    return default

def feature_location_parts(feature):
    """Return 1-based inclusive intervals from a Biopython feature location."""
    parts = getattr(feature.location, 'parts', None)
    if parts is None:
        parts = [feature.location]

    intervals = []
    for part in parts:
        start = int(part.start) + 1
        end = int(part.end)
        strand = int(part.strand) if part.strand else 0
        intervals.append((start, end, strand))
    return intervals

def write_gtf(records, out_gtf: Path):
    with out_gtf.open('w', encoding='utf-8') as out:
        for record in records:
            contig = record.id
            for feature in record.features:
                if feature.type not in {'gene', 'CDS', 'misc_feature'}:
                    continue

                gene = get_qualifier(feature, ['gene', 'locus_tag', 'product', 'note'], default='unknown')
                product = get_qualifier(feature, ['product', 'gene', 'note'], default=gene)
                gene = clean_attr(gene)
                product = clean_attr(product)

                gene_id = f'{contig}_{gene}'
                transcript_id = f'{gene_id}_tx1'

                for start, end, strand_num in feature_location_parts(feature):
                    strand = '+' if strand_num >= 0 else '-'
                    attrs = (
                        f'gene_id "{gene_id}"; '
                        f'transcript_id "{transcript_id}"; '
                        f'gene_name "{gene}"; '
                        f'product "{product}"; '
                        f'feature_type "{feature.type}";'
                    )
                    out.write('\t'.join([
                        contig, 'NCBI_GenBank', feature.type,
                        str(start), str(end), '.', strand, '.', attrs
                    ]) + '\n')

def fetch_genbank(accession: str):
    handle = Entrez.efetch(db='nuccore', id=accession, rettype='gbwithparts', retmode='text')
    record = SeqIO.read(handle, 'genbank')
    handle.close()
    return record

def main():
    args = parse_args()
    Entrez.email = args.email

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    records = []
    rows = []

    with open(args.accessions, newline='', encoding='utf-8') as handle:
        reader = csv.DictReader(handle, delimiter='\t')
        for rec in reader:
            hpv_type = rec['hpv_type'].strip()
            accession = rec['accession'].strip()
            if not hpv_type or not accession:
                continue

            print(f'[INFO] Fetching {hpv_type}: {accession}')
            record = fetch_genbank(accession)
            old_id = record.id
            record.id = hpv_type
            record.name = hpv_type
            record.description = hpv_type
            records.append(record)
            rows.append((hpv_type, old_id, accession, len(record.seq)))
            time.sleep(args.sleep)

    fasta_path = out_dir / 'hpv_curated.fa'
    gbff_path = out_dir / 'hpv_curated.gbff'
    gtf_path = out_dir / 'hpv_genes.gtf'
    meta_path = out_dir / 'hpv_accessions.tsv'

    SeqIO.write(records, fasta_path, 'fasta')
    SeqIO.write(records, gbff_path, 'genbank')
    write_gtf(records, gtf_path)

    with meta_path.open('w', encoding='utf-8') as out:
        out.write('hpv_type\trecord_id\trequested_accession\tlength\n')
        for row in rows:
            out.write('\t'.join(map(str, row)) + '\n')

    print(f'[OK] FASTA: {fasta_path}')
    print(f'[OK] GBFF:  {gbff_path}')
    print(f'[OK] GTF:   {gtf_path}')
    print(f'[OK] META:  {meta_path}')

if __name__ == '__main__':
    main()
