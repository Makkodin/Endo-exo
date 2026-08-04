#!/usr/bin/env python3

import pandas as pd

CLASS_ORDER = [
    "LTR",
    "LINE",
    "SINE",
    "DNA",
    "Simple_repeat",
    "Satellite",
    "Low_complexity",
    "RNA",
    "RC",
    "Unknown",
    "Other",
]

def to_float(value: object, default: float = 0.0) -> float:
    try:
        if pd.isna(value):
            return default
        text = str(value).strip()
        return float(text) if text else default
    except (TypeError, ValueError):
        return default

def rpm(value: object, read_pairs: object) -> float:
    denominator = to_float(read_pairs)
    if denominator <= 0:
        return 0.0
    # Preserve full numerical precision for downstream analyses.
    # Apply rounding only when presenting or formatting results.
    return to_float(value) * 1_000_000.0 / denominator

def normalize_class(value: object) -> str:
    raw = str(value).strip()
    return raw if raw in CLASS_ORDER else "Other"

def add_class_columns(frame: pd.DataFrame) -> pd.DataFrame:
    if frame.empty:
        return frame.copy()
    output = frame.copy()
    if "te_class_group" not in output.columns:
        output["te_class_group"] = output["repeat_class"] if "repeat_class" in output.columns else "Other"
    output["te_class_group"] = output["te_class_group"].map(normalize_class)
    return output

def top_by_class(
    frame: pd.DataFrame,
    count_column: str,
    top_n: int = 3,
    read_pairs: float = 0.0,
) -> pd.DataFrame:
    if frame.empty or count_column not in frame.columns:
        return pd.DataFrame()

    output = add_class_columns(frame)
    output[count_column] = pd.to_numeric(output[count_column], errors="coerce").fillna(0.0)
    for column in ("repeat_family", "repeat_name", "locus_id"):
        if column not in output.columns:
            output[column] = ""

    rows = []
    for repeat_class in CLASS_ORDER:
        subset = output[output["te_class_group"] == repeat_class]
        subset = subset.sort_values(count_column, ascending=False).head(top_n)
        for rank, (_, row) in enumerate(subset.iterrows(), start=1):
            rows.append(
                {
                    "class": repeat_class,
                    "rank": rank,
                    "repeat_family": row.get("repeat_family", ""),
                    "repeat_name": row.get("repeat_name", ""),
                    "locus_id": row.get("locus_id", ""),
                    "count": row.get(count_column, 0.0),
                    "rpm": rpm(row.get(count_column, 0.0), read_pairs),
                }
            )
    return pd.DataFrame(rows)
