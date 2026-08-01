#!/usr/bin/env python3

"""Extract human–HPV junction candidates from STAR chimeric junction output."""

import argparse
from pathlib import Path

import pandas as pd

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample", required=True)
    parser.add_argument("--junction", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--hpv-prefix", default="HPV")
    return parser.parse_args()

def is_hpv_contig(chrom: str, hpv_prefix: str) -> bool:
    return str(chrom).startswith(hpv_prefix)

def is_human_contig(chrom: str, hpv_prefix: str) -> bool:
    chrom = str(chrom)

    if chrom in {"", "*", "NA", "nan"}:
        return False

    if is_hpv_contig(chrom, hpv_prefix):
        return False

    return True

def write_empty_output(path: str):
    cols = [
        "sample_id",
        "hpv_type",
        "hpv_pos",
        "hpv_strand",
        "human_chr",
        "human_pos",
        "human_strand",
        "junction_type",
        "repeat_left_len",
        "repeat_right_len",
        "read_name",
        "first_segment_cigar",
        "second_segment_cigar",
    ]

    Path(path).parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(columns=cols).to_csv(path, sep="\t", index=False)

def main():
    args = parse_args()

    junction_path = Path(args.junction)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not junction_path.exists() or junction_path.stat().st_size == 0:
        write_empty_output(str(out_path))
        return

    rows = []

    with open(junction_path, "r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue

            parts = line.rstrip("\n").split("\t")

            if len(parts) < 12:
                continue

            chr_donor = parts[0]
            pos_donor = parts[1]
            strand_donor = parts[2]

            chr_acceptor = parts[3]
            pos_acceptor = parts[4]
            strand_acceptor = parts[5]

            junction_type = parts[6]
            repeat_left_len = parts[7]
            repeat_right_len = parts[8]
            read_name = parts[9]
            first_segment_cigar = parts[10]
            second_segment_cigar = parts[11]

            donor_is_hpv = is_hpv_contig(chr_donor, args.hpv_prefix)
            acceptor_is_hpv = is_hpv_contig(chr_acceptor, args.hpv_prefix)

            donor_is_human = is_human_contig(chr_donor, args.hpv_prefix)
            acceptor_is_human = is_human_contig(chr_acceptor, args.hpv_prefix)

            if donor_is_hpv and acceptor_is_human:
                hpv_type = chr_donor
                hpv_pos = int(pos_donor)
                hpv_strand = strand_donor

                human_chr = chr_acceptor
                human_pos = int(pos_acceptor)
                human_strand = strand_acceptor

            elif acceptor_is_hpv and donor_is_human:
                hpv_type = chr_acceptor
                hpv_pos = int(pos_acceptor)
                hpv_strand = strand_acceptor

                human_chr = chr_donor
                human_pos = int(pos_donor)
                human_strand = strand_donor

            else:
                continue

            rows.append(
                {
                    "sample_id": args.sample,
                    "hpv_type": hpv_type,
                    "hpv_pos": hpv_pos,
                    "hpv_strand": hpv_strand,
                    "human_chr": human_chr,
                    "human_pos": human_pos,
                    "human_strand": human_strand,
                    "junction_type": junction_type,
                    "repeat_left_len": repeat_left_len,
                    "repeat_right_len": repeat_right_len,
                    "read_name": read_name,
                    "first_segment_cigar": first_segment_cigar,
                    "second_segment_cigar": second_segment_cigar,
                }
            )

    if not rows:
        write_empty_output(str(out_path))
        return

    out = pd.DataFrame(rows)
    out = out.sort_values(
        ["hpv_type", "human_chr", "human_pos", "hpv_pos", "read_name"]
    )

    out.to_csv(out_path, sep="\t", index=False)

if __name__ == "__main__":
    main()
