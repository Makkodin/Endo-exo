#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

SRA_RE = re.compile(r"^(?:sra:)?([SED]RR\d+)$", re.I)
SAFE_SAMPLE_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
FASTQ_RE = re.compile(r"\.(?:fastq|fq)(?:\.gz)?$", re.I)

def sniff_delimiter(path: Path) -> str:
    text = path.read_text(encoding="utf-8-sig", errors="replace")[:8192]
    try:
        return csv.Sniffer().sniff(text, delimiters=",\t;").delimiter
    except csv.Error:
        return ","

def load_samples(path: Path, check_files: bool = True) -> list[dict[str, str]]:
    delimiter = sniff_delimiter(path)
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        if reader.fieldnames != ["sample", "Fq1", "Fq2"]:
            raise ValueError(
                "Input table must contain exactly three columns in this order: sample,Fq1,Fq2; "
                f"got {reader.fieldnames!r}"
            )
        for line_no, raw in enumerate(reader, start=2):
            sample = (raw.get("sample") or "").strip()
            fq1 = (raw.get("Fq1") or "").strip()
            fq2 = (raw.get("Fq2") or "").strip()
            if not sample and not fq1 and not fq2:
                continue
            if not sample or not SAFE_SAMPLE_RE.fullmatch(sample):
                raise ValueError(f"line {line_no}: unsafe or empty sample name: {sample!r}")
            if sample in seen:
                raise ValueError(f"line {line_no}: duplicate sample: {sample}")
            seen.add(sample)
            sra_match = SRA_RE.fullmatch(fq1)
            if sra_match and not fq2:
                rows.append({"sample": sample, "input_type": "sra", "sra": sra_match.group(1).upper(), "Fq1": fq1, "Fq2": ""})
                continue
            if not fq1 or not fq2:
                raise ValueError(
                    f"line {line_no}, sample {sample}: FASTQ rows require both Fq1 and Fq2; "
                    "for SRA use Fq1=sra:SRR... and leave Fq2 empty"
                )
            p1, p2 = Path(fq1), Path(fq2)
            if not p1.is_absolute() or not p2.is_absolute():
                raise ValueError(f"line {line_no}, sample {sample}: Fq1 and Fq2 must be absolute paths")
            if p1 == p2:
                raise ValueError(f"line {line_no}, sample {sample}: Fq1 and Fq2 are the same file")
            if not FASTQ_RE.search(p1.name) or not FASTQ_RE.search(p2.name):
                raise ValueError(f"line {line_no}, sample {sample}: unsupported FASTQ extension")
            if check_files:
                for label, p in (("Fq1", p1), ("Fq2", p2)):
                    if not p.is_file() or p.stat().st_size == 0:
                        raise ValueError(f"line {line_no}, sample {sample}: {label} missing or empty: {p}")
            rows.append({"sample": sample, "input_type": "fastq", "sra": "", "Fq1": str(p1), "Fq2": str(p2)})
    if not rows:
        raise ValueError("Input table contains no samples")
    return rows

def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--samples", required=True)
    p.add_argument("--no-check-files", action="store_true")
    p.add_argument("--format", choices=["json", "tsv", "mounts", "count", "summary"], default="tsv")
    args = p.parse_args()
    path = Path(args.samples).expanduser().resolve()
    if not path.is_file():
        raise SystemExit(f"ERROR: samples file not found: {path}")
    try:
        rows = load_samples(path, check_files=not args.no_check_files)
    except ValueError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
    if args.format == "json":
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    elif args.format == "count":
        print(len(rows))
    elif args.format == "summary":
        n_fastq = sum(r["input_type"] == "fastq" for r in rows)
        n_sra = sum(r["input_type"] == "sra" for r in rows)
        print(f"VALID: samples={len(rows)} fastq={n_fastq} sra={n_sra} file={path}")
    elif args.format == "mounts":
        parents = sorted({str(Path(r[key]).parent) for r in rows if r["input_type"] == "fastq" for key in ("Fq1", "Fq2")})
        for item in parents:
            print(item)
    else:
        writer = csv.DictWriter(sys.stdout, fieldnames=["sample", "input_type", "sra", "Fq1", "Fq2"], delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

if __name__ == "__main__":
    main()
