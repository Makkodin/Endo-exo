#!/usr/bin/env python3

"""Cluster nearby human–HPV junction candidates into integration loci."""

import argparse
from pathlib import Path

import pandas as pd

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--window", type=int, default=50000)
    parser.add_argument("--min-support", type=int, default=2)
    return parser.parse_args()

def confidence_from_support(n):
    if n >= 20:
        return "high"
    if n >= 5:
        return "medium"
    if n >= 2:
        return "low_medium"
    if n == 1:
        return "low"
    return "none"

def main():
    args = parse_args()

    summary_path = Path(args.summary)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    out_cols = [
        "sample_id",
        "hpv_type",
        "human_chr",
        "human_cluster_start",
        "human_cluster_end",
        "hpv_cluster_start",
        "hpv_cluster_end",
        "n_breakpoints",
        "total_supporting_reads",
        "integration_locus_confidence",
        "breakpoints",
    ]

    if not summary_path.exists() or summary_path.stat().st_size == 0:
        pd.DataFrame(columns=out_cols).to_csv(out_path, sep="\t", index=False)
        return

    df = pd.read_csv(summary_path, sep="\t")

    if df.empty:
        pd.DataFrame(columns=out_cols).to_csv(out_path, sep="\t", index=False)
        return

    df = df[df["supporting_reads"] >= args.min_support].copy()

    if df.empty:
        pd.DataFrame(columns=out_cols).to_csv(out_path, sep="\t", index=False)
        return

    rows = []

    for (sample_id, hpv_type, human_chr), sub in df.groupby(
        ["sample_id", "hpv_type", "human_chr"]
    ):
        sub = sub.sort_values("human_pos").reset_index(drop=True)

        current = []

        for _, row in sub.iterrows():
            if not current:
                current = [row]
                continue

            prev_pos = int(current[-1]["human_pos"])
            cur_pos = int(row["human_pos"])

            if abs(cur_pos - prev_pos) <= args.window:
                current.append(row)
            else:
                rows.append(build_cluster(sample_id, hpv_type, human_chr, current))
                current = [row]

        if current:
            rows.append(build_cluster(sample_id, hpv_type, human_chr, current))

    out = pd.DataFrame(rows)

    if not out.empty:
        out = out.sort_values(
            ["total_supporting_reads", "n_breakpoints"],
            ascending=[False, False],
        )

    out.to_csv(out_path, sep="\t", index=False)

def build_cluster(sample_id, hpv_type, human_chr, records):
    human_positions = [int(r["human_pos"]) for r in records]
    hpv_positions = [int(r["hpv_pos"]) for r in records]
    supports = [int(r["supporting_reads"]) for r in records]

    breakpoints = []

    for r in records:
        breakpoints.append(
            f'{r["hpv_type"]}:{int(r["hpv_pos"])}--{r["human_chr"]}:{int(r["human_pos"])}'
            f'({int(r["supporting_reads"])} reads)'
        )

    total_support = sum(supports)

    return {
        "sample_id": sample_id,
        "hpv_type": hpv_type,
        "human_chr": human_chr,
        "human_cluster_start": min(human_positions),
        "human_cluster_end": max(human_positions),
        "hpv_cluster_start": min(hpv_positions),
        "hpv_cluster_end": max(hpv_positions),
        "n_breakpoints": len(records),
        "total_supporting_reads": total_support,
        "integration_locus_confidence": confidence_from_support(total_support),
        "breakpoints": "; ".join(breakpoints),
    }

if __name__ == "__main__":
    main()
