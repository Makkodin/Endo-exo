#!/usr/bin/env python3

"""Build broad repeat-element locus annotation from the UCSC hg38 RepeatMasker table."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import pandas as pd

RMSK_COLUMNS = [
    "bin", "swScore", "milliDiv", "milliDel", "milliIns", "genoName",
    "genoStart", "genoEnd", "genoLeft", "strand", "repName", "repClass",
    "repFamily", "repStart", "repEnd", "repLeft", "id",
]

TARGET_CLASSES = [
    "LTR", "LINE", "SINE", "DNA", "Simple_repeat", "Satellite",
    "Low_complexity", "RNA", "RC", "Unknown", "Other",
]

CLASS_ALIASES = {
    "ltr": "LTR",
    "line": "LINE",
    "sine": "SINE",
    "dna": "DNA",
    "simple_repeat": "Simple_repeat",
    "simplerepeat": "Simple_repeat",
    "satellite": "Satellite",
    "low_complexity": "Low_complexity",
    "lowcomplexity": "Low_complexity",
    "rna": "RNA",
    "rc": "RC",
    "unknown": "Unknown",
    "other": "Other",
}

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--rmsk", required=True, help="UCSC hg38 rmsk.txt.gz")
    p.add_argument("--fai", required=True, help="Target FASTA .fai")
    p.add_argument("--chr-style", required=True, choices=["ucsc", "ensembl"])
    p.add_argument("--out-dir", required=True)
    p.add_argument(
        "--classes",
        default=",".join(TARGET_CLASSES),
        help="Comma-separated RepeatMasker classes to keep. Use 'all' to keep every class.",
    )
    return p.parse_args()

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

def load_fai_contigs(fai_path: str) -> set[str]:
    contigs = set()
    with open(fai_path, "r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                contigs.add(line.split("\t")[0])
    return contigs

def safe_attr(text: object) -> str:
    text = str(text)
    text = text.replace('"', "")
    text = text.replace(";", "_")
    text = re.sub(r"\s+", "_", text)
    return text

def normalize_repeat_class(value: object) -> str:
    raw = str(value).strip()
    key = raw.lower().replace("-", "_").replace("/", "_")
    return CLASS_ALIASES.get(key, raw or "Other")

def make_locus_id(row: pd.Series, idx: int) -> str:
    cls = safe_attr(row["repeat_class"])
    return (
        f'TE_{idx:09d}_{cls}_{row["chrom"]}_{int(row["start"])}_{int(row["end"])}_'
        f'{safe_attr(row["repName"])}'
    )

def is_herv_ltr_erv_like(row: pd.Series) -> bool:
    rep_class = str(row.get("repeat_class", "")).upper()
    rep_family = str(row.get("repeat_family", "")).upper()
    rep_name = str(row.get("repeat_name", "")).upper()
    if rep_class != "LTR":
        return False
    return (
        "ERV" in rep_family
        or "HERV" in rep_family
        or rep_family in {"ERV1", "ERVK", "ERVL", "ERVL-MALR"}
        or "ERV" in rep_name
        or "HERV" in rep_name
        or rep_name.startswith("LTR")
        or rep_name.startswith("MER")
    )

def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    keep_all = args.classes.strip().lower() == "all"
    keep_classes = {normalize_repeat_class(x.strip()) for x in args.classes.split(",") if x.strip()}

    target_contigs = load_fai_contigs(args.fai)
    print(f"[TE] Reading rmsk: {args.rmsk}")
    df = pd.read_csv(
        args.rmsk,
        sep="\t",
        header=None,
        names=RMSK_COLUMNS,
        compression="gzip",
        low_memory=False,
    )
    print(f"[TE] Total rmsk rows: {len(df):,}")

    df["chrom"] = df["genoName"].map(lambda x: normalize_chrom(x, args.chr_style))
    df["start"] = df["genoStart"].astype(int)
    df["end"] = df["genoEnd"].astype(int)
    df = df[df["chrom"].isin(target_contigs)].copy()
    print(f"[TE] Rows on target FASTA contigs: {len(df):,}")

    df["repeat_name"] = df["repName"].astype(str)
    df["repeat_class_raw"] = df["repClass"].astype(str)
    df["repeat_class"] = df["repClass"].map(normalize_repeat_class)
    df["repeat_family"] = df["repFamily"].astype(str)
    df["te_class_group"] = df["repeat_class"].where(df["repeat_class"].isin(TARGET_CLASSES), "Other")

    if not keep_all:
        df = df[df["te_class_group"].isin(keep_classes)].copy()

    df = df.sort_values(["chrom", "start", "end", "repeat_class", "repName"]).reset_index(drop=True)
    print(f"[TE] Selected TE/repeat loci: {len(df):,}")
    if df.empty:
        raise SystemExit("ERROR: no TE/repeat loci selected. Check rmsk input/filter.")

    df["locus_id"] = [make_locus_id(row, i + 1) for i, row in df.iterrows()]
    df["length_bp"] = df["end"] - df["start"]
    df["is_herv_ltr_erv_like"] = df.apply(is_herv_ltr_erv_like, axis=1)

    metadata_cols = [
        "locus_id", "chrom", "start", "end", "length_bp", "strand",
        "repeat_name", "repeat_class", "te_class_group", "repeat_family",
        "is_herv_ltr_erv_like", "swScore", "milliDiv", "milliDel", "milliIns",
        "genoName", "genoStart", "genoEnd", "repStart", "repEnd", "repLeft", "id",
    ]
    metadata_path = out_dir / "te_loci.metadata.tsv"
    df[metadata_cols].to_csv(metadata_path, sep="\t", index=False)

    bed_path = out_dir / "te_loci.bed"
    bed = df[["chrom", "start", "end", "locus_id", "swScore", "strand", "repeat_name", "repeat_class", "te_class_group", "repeat_family"]]
    bed.to_csv(bed_path, sep="\t", index=False, header=False)

    gtf_path = out_dir / "te_loci.gtf"
    with open(gtf_path, "w", encoding="utf-8") as out:
        for _, row in df.iterrows():
            chrom = row["chrom"]
            start_1based = int(row["start"]) + 1
            end_1based = int(row["end"])
            strand = row["strand"] if row["strand"] in {"+", "-"} else "."
            locus_id = safe_attr(row["locus_id"])
            rep_name = safe_attr(row["repeat_name"])
            rep_class = safe_attr(row["repeat_class"])
            class_group = safe_attr(row["te_class_group"])
            rep_family = safe_attr(row["repeat_family"])
            is_herv = "true" if bool(row["is_herv_ltr_erv_like"]) else "false"
            attrs = (
                f'gene_id "{locus_id}"; transcript_id "{locus_id}_tx1"; '
                f'gene_name "{rep_name}"; repeat_name "{rep_name}"; '
                f'repeat_class "{rep_class}"; te_class_group "{class_group}"; '
                f'repeat_family "{rep_family}"; is_herv_ltr_erv_like "{is_herv}"; '
                f'locus_id "{locus_id}";'
            )
            out.write("\t".join([str(chrom), "UCSC_rmsk", "exon", str(start_1based), str(end_1based), ".", strand, ".", attrs]) + "\n")

    summary = (
        df.groupby(["te_class_group", "repeat_class", "repeat_family", "repeat_name"], dropna=False)
        .agg(n_loci=("locus_id", "count"), total_bp=("length_bp", "sum"), median_length_bp=("length_bp", "median"))
        .reset_index()
        .sort_values(["te_class_group", "n_loci", "total_bp"], ascending=[True, False, False])
    )
    summary_path = out_dir / "te_class_summary.tsv"
    summary.to_csv(summary_path, sep="\t", index=False)

    print("[TE] Written:")
    print(f"  {metadata_path}")
    print(f"  {bed_path}")
    print(f"  {gtf_path}")
    print(f"  {summary_path}")
    print("[TE] Class counts:")
    print(df["te_class_group"].value_counts().to_string())

if __name__ == "__main__":
    main()
