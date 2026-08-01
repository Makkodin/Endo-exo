#!/usr/bin/env python3

"""Build HERV/LTR/ERV locus annotation from the UCSC hg38 RepeatMasker table."""

import argparse
from pathlib import Path

import pandas as pd

RMSK_COLUMNS = [
    "bin",
    "swScore",
    "milliDiv",
    "milliDel",
    "milliIns",
    "genoName",
    "genoStart",
    "genoEnd",
    "genoLeft",
    "strand",
    "repName",
    "repClass",
    "repFamily",
    "repStart",
    "repEnd",
    "repLeft",
    "id",
]

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rmsk", required=True, help="UCSC hg38 rmsk.txt.gz")
    parser.add_argument("--fai", required=True, help="Target FASTA .fai")
    parser.add_argument("--chr-style", required=True, choices=["ucsc", "ensembl"])
    parser.add_argument("--out-dir", required=True)
    return parser.parse_args()

def normalize_chrom(chrom: str, chr_style: str) -> str:
    chrom = str(chrom)

    if chr_style == "ucsc":
        if chrom.startswith("chr"):
            return chrom
        if chrom == "MT":
            return "chrM"
        return "chr" + chrom

    if chrom == "chrM":
        return "MT"
    if chrom.startswith("chr"):
        return chrom[3:]
    return chrom

def is_herv_like(row) -> bool:
    """Return True for LTR records with ERV- or HERV-associated family or repeat names."""
    rep_class = str(row["repClass"])
    rep_family = str(row["repFamily"])
    rep_name = str(row["repName"])

    rep_class_u = rep_class.upper()
    rep_family_u = rep_family.upper()
    rep_name_u = rep_name.upper()

    if rep_class_u == "LTR":
        if (
            "ERV" in rep_family_u
            or "HERV" in rep_family_u
            or rep_family_u in {"ERV1", "ERVK", "ERVL", "ERVL-MALR"}
        ):
            return True

        if (
            "ERV" in rep_name_u
            or "HERV" in rep_name_u
            or rep_name_u.startswith("LTR")
            or rep_name_u.startswith("MER")
        ):
            return True

    return False

def safe_attr(text: str) -> str:
    text = str(text)
    text = text.replace('"', "")
    text = text.replace(";", "_")
    return text

def make_locus_id(row, idx: int) -> str:
    return (
        f'HERV_{idx:09d}_'
        f'{row["chrom"]}_{int(row["start"])}_{int(row["end"])}_'
        f'{safe_attr(row["repName"])}'
    )

def load_fai_contigs(fai_path: str) -> set:
    contigs = set()
    with open(fai_path, "r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                contigs.add(line.split("\t")[0])
    return contigs

def main():
    args = parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    target_contigs = load_fai_contigs(args.fai)

    print(f"[HERV] Reading rmsk: {args.rmsk}")

    df = pd.read_csv(
        args.rmsk,
        sep="\t",
        header=None,
        names=RMSK_COLUMNS,
        compression="gzip",
        low_memory=False,
    )

    print(f"[HERV] Total rmsk rows: {len(df):,}")

    df["chrom"] = df["genoName"].map(lambda x: normalize_chrom(x, args.chr_style))
    df["start"] = df["genoStart"].astype(int)
    df["end"] = df["genoEnd"].astype(int)

    df = df[df["chrom"].isin(target_contigs)].copy()
    print(f"[HERV] Rows on target FASTA contigs: {len(df):,}")

    df["is_herv_like"] = df.apply(is_herv_like, axis=1)
    herv = df[df["is_herv_like"]].copy()

    herv = herv.sort_values(["chrom", "start", "end", "repName"]).reset_index(drop=True)

    print(f"[HERV] HERV/LTR/ERV-like rows: {len(herv):,}")

    if herv.empty:
        raise SystemExit("ERROR: no HERV-like loci found. Check rmsk input/filter.")

    herv["locus_id"] = [
        make_locus_id(row, idx + 1)
        for idx, row in herv.iterrows()
    ]

    herv["length_bp"] = herv["end"] - herv["start"]

    herv["repeat_name"] = herv["repName"].astype(str)
    herv["repeat_class"] = herv["repClass"].astype(str)
    herv["repeat_family"] = herv["repFamily"].astype(str)

    metadata_cols = [
        "locus_id",
        "chrom",
        "start",
        "end",
        "length_bp",
        "strand",
        "repeat_name",
        "repeat_class",
        "repeat_family",
        "swScore",
        "milliDiv",
        "milliDel",
        "milliIns",
        "genoName",
        "genoStart",
        "genoEnd",
        "repStart",
        "repEnd",
        "repLeft",
        "id",
    ]

    metadata_path = out_dir / "herv_loci.metadata.tsv"
    herv[metadata_cols].to_csv(metadata_path, sep="\t", index=False)

    bed_path = out_dir / "herv_loci.bed"
    bed = herv[
        [
            "chrom",
            "start",
            "end",
            "locus_id",
            "swScore",
            "strand",
            "repeat_name",
            "repeat_class",
            "repeat_family",
        ]
    ].copy()
    bed.to_csv(bed_path, sep="\t", index=False, header=False)

    gtf_path = out_dir / "herv_loci.gtf"
    with open(gtf_path, "w", encoding="utf-8") as out:
        for _, row in herv.iterrows():
            chrom = row["chrom"]
            start_1based = int(row["start"]) + 1
            end_1based = int(row["end"])
            strand = row["strand"]
            if strand not in {"+", "-"}:
                strand = "."

            locus_id = safe_attr(row["locus_id"])
            rep_name = safe_attr(row["repeat_name"])
            rep_class = safe_attr(row["repeat_class"])
            rep_family = safe_attr(row["repeat_family"])

            attrs = (
                f'gene_id "{locus_id}"; '
                f'transcript_id "{locus_id}_tx1"; '
                f'gene_name "{rep_name}"; '
                f'repeat_name "{rep_name}"; '
                f'repeat_class "{rep_class}"; '
                f'repeat_family "{rep_family}"; '
                f'locus_id "{locus_id}";'
            )

            out.write(
                "\t".join(
                    [
                        str(chrom),
                        "UCSC_rmsk",
                        "exon",
                        str(start_1based),
                        str(end_1based),
                        ".",
                        strand,
                        ".",
                        attrs,
                    ]
                )
                + "\n"
            )

    summary = (
        herv.groupby(["repeat_class", "repeat_family", "repeat_name"])
        .agg(
            n_loci=("locus_id", "count"),
            total_bp=("length_bp", "sum"),
            median_length_bp=("length_bp", "median"),
        )
        .reset_index()
        .sort_values(["n_loci", "total_bp"], ascending=[False, False])
    )

    summary_path = out_dir / "herv_family_summary.tsv"
    summary.to_csv(summary_path, sep="\t", index=False)

    print("[HERV] Written:")
    print(f"  {metadata_path}")
    print(f"  {bed_path}")
    print(f"  {gtf_path}")
    print(f"  {summary_path}")

    print("[HERV] Top families:")
    print(summary.head(20).to_string(index=False))

if __name__ == "__main__":
    main()
