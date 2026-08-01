#!/usr/bin/env python3

"""Summarize HPV mapping and coverage and assign per-reference detection calls."""

import argparse
import json
from pathlib import Path

import pandas as pd

def parse_args():
    parser = argparse.ArgumentParser(
        description="Parse HPV alignment statistics and produce HPV call table."
    )

    parser.add_argument("--sample", required=True, help="Sample ID")
    parser.add_argument("--idxstats", required=True, help="samtools idxstats TSV")
    parser.add_argument("--depth", required=True, help="samtools depth TSV")
    parser.add_argument("--out-tsv", required=True, help="Output HPV call TSV")
    parser.add_argument("--out-json", required=True, help="Output HPV call JSON")

    parser.add_argument("--min-reads", type=int, default=10)
    parser.add_argument("--min-covered-bases", type=int, default=500)
    parser.add_argument("--min-coverage-breadth", type=float, default=0.05)

    return parser.parse_args()

def load_depth(depth_path: str) -> pd.DataFrame:
    """Read samtools depth output or return an empty coverage table."""
    path = Path(depth_path)

    if not path.exists() or path.stat().st_size == 0:
        return pd.DataFrame(columns=["virus", "position", "depth"])

    return pd.read_csv(
        path,
        sep="\t",
        header=None,
        names=["virus", "position", "depth"],
    )

def main():
    args = parse_args()

    idx = pd.read_csv(
        args.idxstats,
        sep="\t",
        header=None,
        names=["virus", "length", "mapped_reads", "unmapped_reads"],
    )

    depth = load_depth(args.depth)

    rows = []

    for _, rec in idx.iterrows():
        virus = str(rec["virus"])
        length = int(rec["length"])
        mapped_reads = int(rec["mapped_reads"])

        if virus == "*" or length <= 0:
            continue

        sub = depth[depth["virus"] == virus]

        if sub.empty:
            covered_bases = 0
            mean_depth = 0.0
            max_depth = 0
        else:
            covered_bases = int((sub["depth"] > 0).sum())
            mean_depth = float(sub["depth"].mean())
            max_depth = int(sub["depth"].max())

        coverage_breadth = covered_bases / length if length > 0 else 0.0

        detected = (
            mapped_reads >= args.min_reads
            and covered_bases >= args.min_covered_bases
            and coverage_breadth >= args.min_coverage_breadth
        )

        if detected and mapped_reads >= 100 and coverage_breadth >= 0.20:
            confidence = "high"
        elif detected:
            confidence = "medium"
        elif mapped_reads > 0:
            confidence = "low"
        else:
            confidence = "not_detected"

        rows.append(
            {
                "sample_id": args.sample,
                "virus": virus,
                "virus_length": length,
                "mapped_reads": mapped_reads,
                "covered_bases": covered_bases,
                "coverage_breadth": round(coverage_breadth, 6),
                "mean_depth": round(mean_depth, 4),
                "max_depth": max_depth,
                "detected": bool(detected),
                "confidence": confidence,
            }
        )

    out = pd.DataFrame(rows)

    if out.empty:
        out = pd.DataFrame(
            [
                {
                    "sample_id": args.sample,
                    "virus": "NA",
                    "virus_length": 0,
                    "mapped_reads": 0,
                    "covered_bases": 0,
                    "coverage_breadth": 0.0,
                    "mean_depth": 0.0,
                    "max_depth": 0,
                    "detected": False,
                    "confidence": "not_detected",
                }
            ]
        )

    out = out.sort_values(
        ["detected", "mapped_reads", "coverage_breadth"],
        ascending=[False, False, False],
    )

    Path(args.out_tsv).parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.out_tsv, sep="\t", index=False)

    summary = {
        "sample_id": args.sample,
        "top_call": out.iloc[0].to_dict(),
        "all_calls": out.to_dict(orient="records"),
        "thresholds": {
            "min_reads": args.min_reads,
            "min_covered_bases": args.min_covered_bases,
            "min_coverage_breadth": args.min_coverage_breadth,
        },
    }

    with open(args.out_json, "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)

if __name__ == "__main__":
    main()
