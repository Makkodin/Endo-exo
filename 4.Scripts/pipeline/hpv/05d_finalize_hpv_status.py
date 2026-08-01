#!/usr/bin/env python3

"""Combine HPV mapping, coverage, oncogene, and expression metrics into a numerical status table."""

import argparse
import re
from pathlib import Path

import pandas as pd

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample", required=True)
    parser.add_argument("--hpv-call", required=True)
    parser.add_argument("--signal-qc", required=True)
    parser.add_argument("--depth", required=True)
    parser.add_argument("--gtf", required=True)
    parser.add_argument("--gene-counts", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--strong-min-reads",
        type=int,
        default=1000,
        help="Minimum HPV mapped reads for strong_positive [default: 1000]",
    )
    parser.add_argument(
        "--strong-min-oncogene-count",
        type=float,
        default=50.0,
        help="Minimum E6+E7 count for strong_positive [default: 50]",
    )
    parser.add_argument(
        "--moderate-min-reads",
        type=int,
        default=100,
        help="Minimum HPV mapped reads for moderate_positive [default: 100]",
    )
    parser.add_argument(
        "--moderate-min-oncogene-count",
        type=float,
        default=5.0,
        help="Minimum E6+E7 count for moderate_positive [default: 5]",
    )
    return parser.parse_args()

def str_to_bool(x):
    return str(x).strip().lower() in {"true", "1", "yes", "y", "t"}

def parse_gtf_attrs(attr_text):
    attrs = {}
    for key, value in re.findall(r'(\S+)\s+"([^"]*)"', attr_text):
        attrs[key] = value
    return attrs

def load_gtf(gtf_path):
    rows = []

    with open(gtf_path, "r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue

            parts = line.rstrip("\n").split("\t")
            if len(parts) != 9:
                continue

            chrom, source, feature, start, end, score, strand, frame, attrs = parts
            attr = parse_gtf_attrs(attrs)

            rows.append(
                {
                    "virus": chrom,
                    "feature": feature,
                    "start": int(start),
                    "end": int(end),
                    "gene_name": attr.get("gene_name", ""),
                    "gene_id": attr.get("gene_id", ""),
                }
            )

    return pd.DataFrame(rows)

def load_gene_counts(path):
    """Read HPV featureCounts output and return normalized gene identifiers and counts."""
    df = pd.read_csv(path, sep="\t", comment="#")

    count_col = df.columns[-1]
    rows = []

    for _, row in df.iterrows():
        gene_id = str(row["Geneid"])
        count = float(row[count_col])

        if "_" in gene_id:
            virus, gene_name = gene_id.split("_", 1)
        else:
            virus = gene_id
            gene_name = ""

        rows.append(
            {
                "virus": virus,
                "gene_id": gene_id,
                "gene_name": gene_name,
                "count": count,
            }
        )

    return pd.DataFrame(rows)

def get_covered_span(depth, virus):
    sub = depth[(depth["virus"] == virus) & (depth["depth"] > 0)]

    if sub.empty:
        return 0, 0

    return int(sub["position"].min()), int(sub["position"].max())

def oncogene_overlap(gtf, virus, start, end):
    if start == 0 or end == 0:
        return False, ""

    oncogenes = gtf[
        (gtf["virus"] == virus)
        & (gtf["feature"].isin(["gene", "CDS"]))
        & (gtf["gene_name"].isin(["E6", "E7"]))
        & (gtf["end"] >= start)
        & (gtf["start"] <= end)
    ].copy()

    if oncogenes.empty:
        return False, ""

    genes = sorted(set(oncogenes["gene_name"].tolist()))
    return True, ",".join(genes)

def gene_count(gene_counts, virus, gene_name):
    sub = gene_counts[
        (gene_counts["virus"] == virus)
        & (gene_counts["gene_name"] == gene_name)
    ]

    if sub.empty:
        return 0.0

    return float(sub["count"].sum())

def top_gene_summary(gene_counts, virus):
    sub = gene_counts[gene_counts["virus"] == virus].copy()

    if sub.empty:
        return "", 0.0

    sub = sub[sub["count"] > 0].copy()

    if sub.empty:
        return "", 0.0

    sub = sub.sort_values("count", ascending=False)
    top = sub.iloc[0]
    return str(top["gene_name"]), float(top["count"])

def classify_hpv_signal(
    mapped_reads: int,
    genome_wide_detected: bool,
    rnaseq_candidate: bool,
    oncogene_expression_count: float,
    strong_min_reads: int,
    strong_min_oncogene_count: float,
    moderate_min_reads: int,
    moderate_min_oncogene_count: float,
):
    """Return the final HPV status, confidence, and numerical signal level."""
    if mapped_reads <= 0:
        return "not_detected", "not_detected", "not_detected"

    has_detection_context = genome_wide_detected or rnaseq_candidate

    if (
        has_detection_context
        and mapped_reads >= strong_min_reads
        and oncogene_expression_count >= strong_min_oncogene_count
    ):
        return "strong_positive", "high", "strong_positive"

    if (
        has_detection_context
        and mapped_reads >= moderate_min_reads
        and oncogene_expression_count >= moderate_min_oncogene_count
    ):
        return "moderate_positive", "medium", "moderate_positive"

    if genome_wide_detected or rnaseq_candidate or mapped_reads >= moderate_min_reads:
        return "weak_positive", "low_medium", "weak_positive"

    return "low_signal", "low", "low_signal"

def main():
    args = parse_args()

    hpv_call = pd.read_csv(args.hpv_call, sep="\t")
    signal_qc = pd.read_csv(args.signal_qc, sep="\t")

    depth = pd.read_csv(
        args.depth,
        sep="\t",
        header=None,
        names=["virus", "position", "depth"],
    )

    gtf = load_gtf(args.gtf)
    gene_counts = load_gene_counts(args.gene_counts)

    merged = hpv_call.merge(
        signal_qc,
        on=["sample_id", "virus"],
        how="left",
        suffixes=("", "_qc"),
    )

    rows = []

    for _, row in merged.iterrows():
        virus = row["virus"]

        genome_wide_detected = str_to_bool(row.get("detected", False))
        rnaseq_candidate = str_to_bool(row.get("rnaseq_candidate", False))

        covered_start, covered_end = get_covered_span(depth, virus)

        oncogene_region_signal, oncogene_genes = oncogene_overlap(
            gtf,
            virus,
            covered_start,
            covered_end,
        )

        e6_count = gene_count(gene_counts, virus, "E6")
        e7_count = gene_count(gene_counts, virus, "E7")
        e1_count = gene_count(gene_counts, virus, "E1")
        e2_count = gene_count(gene_counts, virus, "E2")
        l1_count = gene_count(gene_counts, virus, "L1")
        l2_count = gene_count(gene_counts, virus, "L2")

        top_gene, top_gene_count = top_gene_summary(gene_counts, virus)

        oncogene_expression_count = e6_count + e7_count
        oncogene_expression = oncogene_expression_count > 0

        mapped_reads = int(row.get("mapped_reads", 0))
        covered_bases = int(row.get("covered_bases", 0))
        coverage_breadth = float(row.get("coverage_breadth", 0.0))

        final_status, final_confidence, signal_level = classify_hpv_signal(
            mapped_reads=mapped_reads,
            genome_wide_detected=genome_wide_detected,
            rnaseq_candidate=rnaseq_candidate,
            oncogene_expression_count=oncogene_expression_count,
            strong_min_reads=args.strong_min_reads,
            strong_min_oncogene_count=args.strong_min_oncogene_count,
            moderate_min_reads=args.moderate_min_reads,
            moderate_min_oncogene_count=args.moderate_min_oncogene_count,
        )

        rows.append(
            {
                "sample_id": args.sample,
                "virus": virus,
                "mapped_reads": mapped_reads,
                "covered_bases": covered_bases,
                "coverage_breadth": coverage_breadth,
                "mean_depth": row.get("mean_depth", 0),
                "max_depth": row.get("max_depth", 0),
                "mapq20_reads": row.get("mapq20_reads", 0),
                "unique_start_sites": row.get("unique_start_sites", 0),
                "covered_blocks": row.get("covered_blocks", 0),
                "genome_wide_detected": genome_wide_detected,
                "rnaseq_candidate": rnaseq_candidate,
                "oncogene_region_signal": oncogene_region_signal,
                "oncogene_genes": oncogene_genes,
                "oncogene_expression": oncogene_expression,
                "oncogene_expression_count": oncogene_expression_count,
                "covered_start": covered_start,
                "covered_end": covered_end,
                "E6_count": e6_count,
                "E7_count": e7_count,
                "E1_count": e1_count,
                "E2_count": e2_count,
                "L1_count": l1_count,
                "L2_count": l2_count,
                "top_expressed_gene": top_gene,
                "top_expressed_gene_count": top_gene_count,
                "final_status": final_status,
                "final_confidence": final_confidence,
                "signal_level": signal_level,
            }
        )

    out = pd.DataFrame(rows)

    status_rank = {
        "strong_positive": 5,
        "moderate_positive": 4,
        "weak_positive": 3,
        "low_signal": 1,
        "not_detected": 0,
        "genome_wide_positive": 5,
        "rnaseq_oncogene_candidate_positive": 4,
        "rnaseq_candidate_positive": 3,
    }

    out["_rank"] = out["final_status"].map(status_rank).fillna(0)
    out = out.sort_values(
        ["_rank", "mapped_reads", "coverage_breadth"],
        ascending=[False, False, False],
    ).drop(columns=["_rank"])

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.out, sep="\t", index=False)

if __name__ == "__main__":
    main()
