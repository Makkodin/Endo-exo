#!/usr/bin/env python3


import argparse
from pathlib import Path
from typing import Optional, Union

import pandas as pd

from repeat_utils import CLASS_ORDER, add_class_columns, rpm, top_by_class, to_float

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Суммировать Telescope output")
    parser.add_argument("--sample", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--metadata", default="")
    parser.add_argument("--library-size", default="")
    parser.add_argument("--out-dir", required=True)
    return parser.parse_args()

def read_tsv_or_empty(path: Union[str, Path]) -> pd.DataFrame:
    if not path:
        return pd.DataFrame()
    p = Path(path)
    if not p.exists() or p.stat().st_size == 0:
        return pd.DataFrame()
    return pd.read_csv(p, sep="\t", low_memory=False).fillna("")


def read_telescope_report(
    path: Union[str, Path],
) -> tuple:
    """Read Telescope report while preserving the leading RunInfo record."""

    if not path:
        return pd.DataFrame(), {}

    report_path = Path(path)

    if (
        not report_path.exists()
        or report_path.stat().st_size == 0
    ):
        return pd.DataFrame(), {}

    run_info = {}

    with report_path.open(
        "r",
        encoding="utf-8",
        errors="replace",
    ) as handle:
        for line in handle:
            if not line.startswith("## RunInfo"):
                continue

            fields = line.rstrip("\r\n").split("\t")

            for field in fields[1:]:
                if ":" not in field:
                    continue

                key, value = field.split(":", 1)
                key = key.strip()
                value = value.strip()

                if key:
                    run_info[key] = value

            break

    frame = pd.read_csv(
        report_path,
        sep="\t",
        comment="#",
        low_memory=False,
    ).fillna("")

    required = {
        "transcript",
        "transcript_length",
        "final_count",
    }

    missing = sorted(required - set(frame.columns))

    if missing:
        raise ValueError(
            "Telescope report is missing required columns: {}".format(
                ",".join(missing)
            )
        )

    return frame, run_info

def read_library_pairs(path: Union[str, Path]) -> float:
    df = read_tsv_or_empty(path)
    if df.empty:
        return 0.0
    row = df.iloc[0].to_dict()
    for col in ["library_read_pairs_after_qc", "read_pairs_after_qc", "read_pairs", "n_read_pairs"]:
        if col in row:
            return to_float(row.get(col, 0))
    return 0.0

def choose_count_col(df: pd.DataFrame) -> Optional[str]:
    candidates = ["est_counts", "est_count", "estimated_count", "expected_count", "count", "assigned_counts", "final_count", "telescope_count"]
    for col in candidates:
        if col in df.columns:
            return col
    numeric = []
    for col in df.columns:
        vals = pd.to_numeric(df[col], errors="coerce")
        if vals.notna().sum() > 0:
            numeric.append((col, vals.fillna(0).sum()))
    if not numeric:
        return None
    return sorted(numeric, key=lambda x: x[1], reverse=True)[0][0]

def choose_locus_col(df: pd.DataFrame) -> Optional[str]:
    for col in ["transcript", "transcript_id", "gene_id", "locus_id", "ID", "feature"]:
        if col in df.columns:
            return col
    return df.columns[0] if len(df.columns) else None

def write_failed(sample: str, out_dir: Path, status: str) -> None:
    pd.DataFrame([{"sample_id": sample, "telescope_status": status, "telescope_total_assigned_count": 0}]).to_csv(out_dir / f"{sample}.telescope_overview.tsv", sep="\t", index=False)

def summarize_class(out: pd.DataFrame, sample: str, read_pairs: float) -> pd.DataFrame:
    rows = []
    for cls in CLASS_ORDER:
        part = out[out["te_class_group"] == cls].copy()
        total = float(part["telescope_count"].sum()) if not part.empty else 0.0
        top = part.sort_values("telescope_count", ascending=False).iloc[0].to_dict() if not part.empty else {}
        rows.append({
            "sample_id": sample,
            "te_class_group": cls,
            "n_loci": int(len(part)),
            "n_loci_count_gt0": int((part["telescope_count"] > 0).sum()) if not part.empty else 0,
            "total_telescope_count": total,
            "telescope_rpm": rpm(total, read_pairs),
            "top_locus": top.get("locus_id", ""),
            "top_locus_count": top.get("telescope_count", 0),
            "top_locus_rpm": rpm(top.get("telescope_count", 0), read_pairs),
            "top_family": top.get("repeat_family", ""),
            "top_repeat_name": top.get("repeat_name", ""),
        })
    return pd.DataFrame(rows)

def summarize_family(out: pd.DataFrame, sample: str, read_pairs: float) -> pd.DataFrame:
    if out.empty:
        return pd.DataFrame()
    fam = out.groupby(["te_class_group", "repeat_family"], dropna=False).agg(n_loci=("locus_id", "count"), n_loci_count_gt0=("telescope_count", lambda x: int((x > 0).sum())), total_telescope_count=("telescope_count", "sum"), max_locus_count=("telescope_count", "max")).reset_index()
    fam.insert(0, "sample_id", sample)
    fam["telescope_rpm"] = fam["total_telescope_count"].map(lambda x: rpm(x, read_pairs))
    return fam.sort_values(["te_class_group", "total_telescope_count"], ascending=[True, False])

def summarize_repeat_name(out: pd.DataFrame, sample: str, read_pairs: float) -> pd.DataFrame:
    if out.empty:
        return pd.DataFrame()
    names = out.groupby(["te_class_group", "repeat_class", "repeat_family", "repeat_name"], dropna=False).agg(
        n_loci=("locus_id", "count"),
        n_loci_count_gt0=("telescope_count", lambda x: int((x > 0).sum())),
        total_telescope_count=("telescope_count", "sum"),
        max_locus_count=("telescope_count", "max"),
    ).reset_index()
    names.insert(0, "sample_id", sample)
    names["telescope_rpm"] = names["total_telescope_count"].map(lambda x: rpm(x, read_pairs))
    return names.sort_values(["te_class_group", "total_telescope_count"], ascending=[True, False])

def build_overview(
    sample: str,
    out: pd.DataFrame,
    class_summary: pd.DataFrame,
    run_info: dict,
    special: pd.DataFrame,
) -> dict:
    top = (
        out.sort_values(
            "telescope_count",
            ascending=False,
        ).iloc[0].to_dict()
        if not out.empty
        else {}
    )

    special_lookup = {}

    if (
        not special.empty
        and "locus_id" in special.columns
        and "telescope_count" in special.columns
    ):
        for _, item in special[
            ["locus_id", "telescope_count"]
        ].iterrows():
            special_lookup[str(item["locus_id"])] = to_float(
                item["telescope_count"]
            )

    special_total = sum(special_lookup.values())

    row = {
        "sample_id": sample,
        "telescope_status": "completed",
        "telescope_total_assigned_count": (
            float(out["telescope_count"].sum())
            if not out.empty
            else 0.0
        ),
        "telescope_special_row_count": int(len(special)),
        "telescope_special_total_count": float(
            special_total
        ),
        "telescope_no_feature_count": float(
            special_lookup.get("__no_feature", 0.0)
        ),
        "telescope_top_locus": top.get(
            "locus_id",
            "",
        ),
        "telescope_top_count": top.get(
            "telescope_count",
            0,
        ),
        "telescope_top_class": top.get(
            "te_class_group",
            "",
        ),
        "telescope_top_family": top.get(
            "repeat_family",
            "",
        ),
        "telescope_top_repeat_name": top.get(
            "repeat_name",
            "",
        ),
    }

    run_info_fields = [
        "annotated_features",
        "total_fragments",
        "pair_mapped",
        "pair_mixed",
        "single_mapped",
        "unmapped",
        "unique",
        "ambig",
        "overlap_unique",
        "overlap_ambig",
    ]

    for field in run_info_fields:
        row[
            "telescope_runinfo_{}".format(field)
        ] = to_float(run_info.get(field, 0))

    row["telescope_runinfo_version"] = str(
        run_info.get("version", "")
    )

    for cls in CLASS_ORDER:
        key = cls.lower().replace(
            "simple_repeat",
            "simple_repeat",
        ).replace(
            "low_complexity",
            "low_complexity",
        )

        if cls == "LTR":
            prefix = "telescope_herv_erv_ltr"
        else:
            prefix = f"telescope_{key}"

        part = class_summary[
            class_summary["te_class_group"] == cls
        ]

        item = (
            part.iloc[0].to_dict()
            if not part.empty
            else {}
        )

        row[
            f"{prefix}_assigned_count"
        ] = item.get(
            "total_telescope_count",
            0,
        )
        row[f"{prefix}_rpm"] = item.get(
            "telescope_rpm",
            0,
        )
        row[
            f"{prefix}_top_family"
        ] = item.get(
            "top_family",
            "",
        )
        row[
            f"{prefix}_top_repeat_name"
        ] = item.get(
            "top_repeat_name",
            "",
        )
        row[
            f"{prefix}_top_locus"
        ] = item.get(
            "top_locus",
            "",
        )
        row[
            f"{prefix}_top_count"
        ] = item.get(
            "top_locus_count",
            0,
        )

    return row

def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    df, run_info = read_telescope_report(
        args.report
    )
    meta = read_tsv_or_empty(args.metadata)
    read_pairs = read_library_pairs(args.library_size)
    if df.empty:
        write_failed(args.sample, out_dir, "failed_or_empty")
        return
    count_col = choose_count_col(df)
    locus_col = choose_locus_col(df)
    if count_col is None or locus_col is None:
        raise SystemExit("ERROR: cannot identify locus/count columns in Telescope report")
    out = df.copy()
    out["telescope_count"] = pd.to_numeric(out[count_col], errors="coerce").fillna(0.0)
    out["locus_id"] = out[locus_col].astype(str)

    special_mask = out["locus_id"].str.startswith(
        "__"
    )

    special = out.loc[special_mask].copy()
    out = out.loc[~special_mask].copy()

    if out["locus_id"].duplicated().any():
        duplicates = (
            out.loc[
                out["locus_id"].duplicated(
                    keep=False
                ),
                "locus_id",
            ]
            .astype(str)
            .head(20)
            .tolist()
        )

        raise SystemExit(
            "ERROR: duplicate biological Telescope loci: {}".format(
                ",".join(duplicates)
            )
        )
    if not meta.empty and "locus_id" in meta.columns:
        cols = [c for c in ["locus_id", "repeat_name", "repeat_class", "te_class_group", "repeat_family", "is_herv_ltr_erv_like"] if c in meta.columns]
        out = out.merge(meta[cols].drop_duplicates("locus_id"), on="locus_id", how="left")
    for col in ["repeat_name", "repeat_class", "te_class_group", "repeat_family"]:
        if col not in out.columns:
            out[col] = ""
    out = add_class_columns(out).sort_values("telescope_count", ascending=False)
    out["telescope_rpm"] = out["telescope_count"].map(lambda x: rpm(x, read_pairs))
    out.to_csv(
        out_dir
        / f"{args.sample}.telescope_counts.normalized.tsv",
        sep="\t",
        index=False,
    )

    special.to_csv(
        out_dir
        / f"{args.sample}.telescope_special_counts.tsv",
        sep="\t",
        index=False,
    )
    class_summary = summarize_class(out, args.sample, read_pairs)
    family_summary = summarize_family(out, args.sample, read_pairs)
    repeat_name_summary = summarize_repeat_name(out, args.sample, read_pairs)
    top = top_by_class(out, "telescope_count", top_n=10, read_pairs=read_pairs)
    top.insert(0, "sample_id", args.sample) if not top.empty else None
    class_summary.to_csv(out_dir / f"{args.sample}.telescope_class_summary.tsv", sep="\t", index=False)
    family_summary.to_csv(out_dir / f"{args.sample}.telescope_family_summary.tsv", sep="\t", index=False)
    repeat_name_summary.to_csv(out_dir / f"{args.sample}.telescope_repeat_name_summary.tsv", sep="\t", index=False)
    top.to_csv(out_dir / f"{args.sample}.telescope_top_by_class.tsv", sep="\t", index=False)
    pd.DataFrame(
        [
            build_overview(
                args.sample,
                out,
                class_summary,
                run_info,
                special,
            )
        ]
    ).to_csv(
        out_dir
        / f"{args.sample}.telescope_overview.tsv",
        sep="\t",
        index=False,
    )

if __name__ == "__main__":
    main()
