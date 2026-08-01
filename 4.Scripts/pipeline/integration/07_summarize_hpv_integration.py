#!/usr/bin/env python3

"""Aggregate human–HPV junction candidates and calculate read support."""

import argparse
from pathlib import Path

import pandas as pd

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--out", required=True)
    return parser.parse_args()

def confidence_from_support(n: int) -> str:
    if n >= 5:
        return "high"
    if n >= 2:
        return "medium"
    if n == 1:
        return "low"
    return "none"

def main():
    args = parse_args()

    candidates_path = Path(args.candidates)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    out_cols = [
        "sample_id",
        "hpv_type",
        "hpv_pos",
        "human_chr",
        "human_pos",
        "supporting_reads",
        "integration_confidence",
        "read_names",
    ]

    if not candidates_path.exists() or candidates_path.stat().st_size == 0:
        pd.DataFrame(columns=out_cols).to_csv(out_path, sep="\t", index=False)
        return

    df = pd.read_csv(candidates_path, sep="\t")

    if df.empty:
        pd.DataFrame(columns=out_cols).to_csv(out_path, sep="\t", index=False)
        return

    group_cols = [
        "sample_id",
        "hpv_type",
        "hpv_pos",
        "human_chr",
        "human_pos",
    ]

    summary = (
        df.groupby(group_cols)
        .agg(
            supporting_reads=("read_name", "nunique"),
            read_names=("read_name", lambda x: ",".join(sorted(set(map(str, x))))),
        )
        .reset_index()
    )

    summary["integration_confidence"] = summary["supporting_reads"].apply(
        confidence_from_support
    )

    summary = summary[
        [
            "sample_id",
            "hpv_type",
            "hpv_pos",
            "human_chr",
            "human_pos",
            "supporting_reads",
            "integration_confidence",
            "read_names",
        ]
    ].sort_values(
        ["supporting_reads", "hpv_type", "human_chr", "human_pos"],
        ascending=[False, True, True, True],
    )

    summary.to_csv(out_path, sep="\t", index=False)

if __name__ == "__main__":
    main()
