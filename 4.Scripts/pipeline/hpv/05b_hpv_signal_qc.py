#!/usr/bin/env python3

"""Calculate HPV alignment, coverage, and pile-up quality metrics."""

import argparse
from collections import defaultdict
from pathlib import Path

import pandas as pd
import pysam

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample", required=True)
    parser.add_argument("--bam", required=True)
    parser.add_argument("--depth", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--mapq-threshold", type=int, default=20)
    return parser.parse_args()

def merge_positions_to_blocks(positions):
    positions = sorted(set(int(x) for x in positions))

    if not positions:
        return []

    blocks = []
    start = positions[0]
    prev = positions[0]

    for pos in positions[1:]:
        if pos == prev + 1:
            prev = pos
        else:
            blocks.append((start, prev))
            start = pos
            prev = pos

    blocks.append((start, prev))
    return blocks

def main():
    args = parse_args()

    bam_path = Path(args.bam)
    depth_path = Path(args.depth)

    if not bam_path.exists():
        raise FileNotFoundError(f"BAM not found: {bam_path}")

    if not depth_path.exists():
        raise FileNotFoundError(f"Depth file not found: {depth_path}")

    mapped_reads = defaultdict(int)
    mapq_reads = defaultdict(int)
    unique_starts = defaultdict(set)

    bam = pysam.AlignmentFile(str(bam_path), "rb")

    for read in bam.fetch(until_eof=True):
        if read.is_unmapped:
            continue

        virus = read.reference_name
        mapped_reads[virus] += 1

        if read.mapping_quality >= args.mapq_threshold:
            mapq_reads[virus] += 1

        unique_starts[virus].add(
            (
                read.reference_name,
                read.reference_start,
                read.is_reverse,
            )
        )

    bam.close()

    if depth_path.stat().st_size == 0:
        depth = pd.DataFrame(columns=["virus", "position", "depth"])
    else:
        depth = pd.read_csv(
            depth_path,
            sep="\t",
            header=None,
            names=["virus", "position", "depth"],
        )

    viruses = sorted(
        set(mapped_reads.keys())
        | set(depth["virus"].unique().tolist() if not depth.empty else [])
    )

    rows = []

    for virus in viruses:
        sub = depth[(depth["virus"] == virus) & (depth["depth"] > 0)]

        positions = sub["position"].astype(int).tolist()
        blocks = merge_positions_to_blocks(positions)

        covered_bases = len(set(positions))
        covered_blocks = len(blocks)

        largest_block_bp = max(
            (end - start + 1 for start, end in blocks),
            default=0,
        )

        if not sub.empty:
            min_covered_pos = int(sub["position"].min())
            max_covered_pos = int(sub["position"].max())
            max_depth = int(sub["depth"].max())
            max_depth_pos = int(sub.loc[sub["depth"].idxmax(), "position"])
            mean_depth_over_covered = float(sub["depth"].mean())
        else:
            min_covered_pos = 0
            max_covered_pos = 0
            max_depth = 0
            max_depth_pos = 0
            mean_depth_over_covered = 0.0

        n_mapped = int(mapped_reads.get(virus, 0))
        n_mapq = int(mapq_reads.get(virus, 0))
        n_unique_starts = len(unique_starts.get(virus, set()))

        mapq_fraction = n_mapq / n_mapped if n_mapped else 0.0

        suspicious_pileup = False

        if n_mapped >= 50:
            if n_unique_starts < 10:
                suspicious_pileup = True

            if covered_blocks <= 1 and largest_block_bp < 150 and max_depth >= 100:
                suspicious_pileup = True

        rnaseq_candidate = (
            n_mapped >= 50
            and n_mapq >= 20
            and mapq_fraction >= 0.5
            and n_unique_starts >= 10
            and covered_bases >= 100
            and not suspicious_pileup
        )

        rows.append(
            {
                "sample_id": args.sample,
                "virus": virus,
                "mapped_reads_bam": n_mapped,
                f"mapq{args.mapq_threshold}_reads": n_mapq,
                "mapq_fraction": round(mapq_fraction, 4),
                "unique_start_sites": n_unique_starts,
                "covered_bases": covered_bases,
                "covered_blocks": covered_blocks,
                "largest_block_bp": largest_block_bp,
                "min_covered_pos": min_covered_pos,
                "max_covered_pos": max_covered_pos,
                "mean_depth_over_covered": round(mean_depth_over_covered, 4),
                "max_depth": max_depth,
                "max_depth_pos": max_depth_pos,
                "suspicious_pileup": suspicious_pileup,
                "rnaseq_candidate": rnaseq_candidate,
            }
        )

    if rows:
        out = pd.DataFrame(rows)
        out = out.sort_values(
            ["rnaseq_candidate", "mapped_reads_bam", f"mapq{args.mapq_threshold}_reads"],
            ascending=[False, False, False],
        )
    else:
        out = pd.DataFrame(
            [
                {
                    "sample_id": args.sample,
                    "virus": "NA",
                    "mapped_reads_bam": 0,
                    f"mapq{args.mapq_threshold}_reads": 0,
                    "mapq_fraction": 0.0,
                    "unique_start_sites": 0,
                    "covered_bases": 0,
                    "covered_blocks": 0,
                    "largest_block_bp": 0,
                    "min_covered_pos": 0,
                    "max_covered_pos": 0,
                    "mean_depth_over_covered": 0.0,
                    "max_depth": 0,
                    "max_depth_pos": 0,
                    "suspicious_pileup": False,
                    "rnaseq_candidate": False,
                }
            ]
        )

    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.out, sep="\t", index=False)

if __name__ == "__main__":
    main()
