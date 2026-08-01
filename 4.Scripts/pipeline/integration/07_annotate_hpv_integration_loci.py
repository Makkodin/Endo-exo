#!/usr/bin/env python3

import argparse
import re
from pathlib import Path

import pandas as pd

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--loci", required=True)
    parser.add_argument("--gtf", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--window", type=int, default=100000)
    return parser.parse_args()

def parse_attrs(attr_text):
    attrs = {}
    for key, value in re.findall(r'(\S+)\s+"([^"]*)"', attr_text):
        attrs[key] = value
    return attrs

def load_genes(gtf_path):
    rows = []

    with open(gtf_path, "r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue

            parts = line.rstrip("\n").split("\t")
            if len(parts) != 9:
                continue

            chrom, source, feature, start, end, score, strand, frame, attrs = parts

            if feature != "gene":
                continue

            attr = parse_attrs(attrs)

            gene_id = attr.get("gene_id", "")
            gene_name = attr.get("gene_name", gene_id)
            gene_type = attr.get("gene_type", attr.get("gene_biotype", ""))

            rows.append(
                {
                    "chrom": chrom,
                    "start": int(start),
                    "end": int(end),
                    "strand": strand,
                    "gene_id": gene_id,
                    "gene_name": gene_name,
                    "gene_type": gene_type,
                }
            )

    return pd.DataFrame(rows)

def interval_distance(a_start, a_end, b_start, b_end):
    if a_end < b_start:
        return b_start - a_end
    if b_end < a_start:
        return a_start - b_end
    return 0

def fmt_gene(g):
    return (
        f'{g["gene_name"]}'
        f'({g["gene_type"]};{g["chrom"]}:{g["start"]}-{g["end"]};{g["strand"]})'
    )

def annotate_one(row, genes, window):
    chrom = str(row["human_chr"])
    start = int(row["human_cluster_start"])
    end = int(row["human_cluster_end"])

    sub = genes[genes["chrom"].astype(str) == chrom].copy()

    if sub.empty:
        return {
            "overlapping_genes": "",
            "nearest_gene": "",
            "nearest_gene_distance": "",
            "genes_within_window": "",
        }

    sub["distance"] = sub.apply(
        lambda g: interval_distance(start, end, int(g["start"]), int(g["end"])),
        axis=1,
    )

    overlapping = sub[sub["distance"] == 0].copy()
    nearby = sub[sub["distance"] <= window].copy().sort_values("distance")
    nearest = sub.sort_values("distance").iloc[0]

    overlapping_genes = ";".join(fmt_gene(g) for _, g in overlapping.iterrows())
    genes_within_window = ";".join(fmt_gene(g) for _, g in nearby.iterrows())

    return {
        "overlapping_genes": overlapping_genes,
        "nearest_gene": fmt_gene(nearest),
        "nearest_gene_distance": int(nearest["distance"]),
        "genes_within_window": genes_within_window,
    }

def main():
    args = parse_args()

    loci_path = Path(args.loci)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not loci_path.exists() or loci_path.stat().st_size == 0:
        pd.DataFrame().to_csv(out_path, sep="\t", index=False)
        return

    loci = pd.read_csv(loci_path, sep="\t")
    genes = load_genes(args.gtf)

    if loci.empty:
        loci.to_csv(out_path, sep="\t", index=False)
        return

    annotations = [annotate_one(row, genes, args.window) for _, row in loci.iterrows()]
    annot = pd.DataFrame(annotations)

    out = pd.concat([loci.reset_index(drop=True), annot], axis=1)
    out.to_csv(out_path, sep="\t", index=False)

if __name__ == "__main__":
    main()
