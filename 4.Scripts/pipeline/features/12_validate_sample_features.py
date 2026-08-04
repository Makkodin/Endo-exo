#!/usr/bin/env python3

import argparse
import hashlib
import json
import math
import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


def parse():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--sample",
        required=True,
    )
    parser.add_argument(
        "--sample-dir",
        required=True,
    )
    parser.add_argument(
        "--enable-human",
        type=int,
        default=1,
    )
    parser.add_argument(
        "--enable-hpv",
        type=int,
        default=1,
    )
    parser.add_argument(
        "--enable-herv",
        type=int,
        default=1,
    )
    parser.add_argument(
        "--enable-te",
        type=int,
        default=1,
    )
    parser.add_argument(
        "--enable-telescope",
        type=int,
        default=1,
    )
    parser.add_argument(
        "--out",
        required=True,
    )
    parser.add_argument(
        "--marker",
        required=True,
    )

    return parser.parse_args()


def sha(path):
    digest = hashlib.sha256()

    with open(path, "rb") as handle:
        for block in iter(
            lambda: handle.read(4 * 1024 * 1024),
            b"",
        ):
            digest.update(block)

    return digest.hexdigest()


def check_table(
    path,
    key=None,
    required_columns=(),
    nonnegative=(),
    allow_empty=False,
    forbidden_key_prefixes=(),
    required_key_prefixes=(),
):
    table_path = Path(path)

    if (
        not table_path.is_file()
        or table_path.stat().st_size == 0
    ):
        return False, "missing_or_empty", 0

    try:
        frame = pd.read_csv(
            table_path,
            sep="\t",
            low_memory=False,
        )
    except Exception as error:
        return (
            False,
            "parse_error:{}".format(error),
            0,
        )

    required = set(required_columns)
    required.update(nonnegative)

    if key:
        required.add(key)

    missing = sorted(
        required - set(frame.columns)
    )

    if missing:
        return (
            False,
            "missing_columns:{}".format(
                ",".join(missing)
            ),
            len(frame),
        )

    if frame.empty:
        if allow_empty:
            return True, "ok_empty", 0

        return False, "no_data_rows", 0

    if key:
        key_values = (
            frame[key]
            .fillna("")
            .astype(str)
            .str.strip()
        )

        invalid_key = (
            key_values.eq("")
            | key_values.str.lower().isin(
                {
                    "nan",
                    "none",
                    "null",
                    "na",
                }
            )
        )

        if invalid_key.any():
            return (
                False,
                "empty_or_invalid_{}".format(key),
                len(frame),
            )

        if key_values.duplicated().any():
            return (
                False,
                "duplicate_{}".format(key),
                len(frame),
            )

        if (
            forbidden_key_prefixes
            and key_values.str.startswith(
                tuple(forbidden_key_prefixes)
            ).any()
        ):
            return (
                False,
                "forbidden_{}_prefix".format(key),
                len(frame),
            )

        if (
            required_key_prefixes
            and not key_values.str.startswith(
                tuple(required_key_prefixes)
            ).all()
        ):
            return (
                False,
                "invalid_{}_prefix".format(key),
                len(frame),
            )

    for column in nonnegative:
        numeric = pd.to_numeric(
            frame[column],
            errors="coerce",
        )

        if numeric.isna().any():
            return (
                False,
                "invalid_numeric_values:{}".format(
                    column
                ),
                len(frame),
            )

        finite = numeric.map(math.isfinite)

        if not finite.all():
            return (
                False,
                "non_finite_values:{}".format(
                    column
                ),
                len(frame),
            )

        if (numeric < 0).any():
            return (
                False,
                "negative_values:{}".format(
                    column
                ),
                len(frame),
            )

    return True, "ok", len(frame)


def main():
    version = os.getenv(
        "ENDO_EXO_VERSION",
        "unknown",
    )
    git_commit = os.getenv(
        "ENDO_EXO_GIT_COMMIT",
        "unknown",
    )
    git_describe = os.getenv(
        "ENDO_EXO_GIT_DESCRIBE",
        "unknown",
    )

    args = parse()
    sample_dir = Path(args.sample_dir)
    checks = []

    def add(
        name,
        path,
        required=True,
        key=None,
        required_columns=(),
        nonnegative=(),
        allow_empty=False,
        forbidden_key_prefixes=(),
        required_key_prefixes=(),
    ):
        ok, status, rows = check_table(
            path=path,
            key=key,
            required_columns=required_columns,
            nonnegative=nonnegative,
            allow_empty=allow_empty,
            forbidden_key_prefixes=(
                forbidden_key_prefixes
            ),
            required_key_prefixes=(
                required_key_prefixes
            ),
        )

        checks.append(
            {
                "check": name,
                "required": required,
                "passed": ok or not required,
                "status": status,
                "rows": rows,
                "path": str(path),
            }
        )

    add(
        "library_size",
        sample_dir
        / "qc"
        / "{}.library_size.tsv".format(
            args.sample
        ),
        required=True,
        required_columns=(
            "library_read_pairs_after_qc",
        ),
        nonnegative=(
            "library_read_pairs_after_qc",
        ),
    )

    add(
        "technical_features",
        sample_dir
        / "{}.technical_features.tsv".format(
            args.sample
        ),
        required=True,
        required_columns=("sample_id",),
    )

    add(
        "sample_features",
        sample_dir
        / "{}.sample_features.tsv".format(
            args.sample
        ),
        required=True,
        required_columns=("sample_id",),
    )

    add(
        "human_gene_locus",
        sample_dir
        / "08_human_gene_expression"
        / "{}.human_gene_counts.normalized.tsv".format(
            args.sample
        ),
        required=bool(args.enable_human),
        key="gene_id",
        required_columns=(
            "gene_id",
            "count",
            "cpm",
            "tpm",
            "rpkm",
        ),
        nonnegative=(
            "count",
            "cpm",
            "tpm",
            "rpkm",
        ),
    )

    add(
        "hpv_final",
        sample_dir
        / "05_hpv_calling"
        / "{}.hpv_final_status.tsv".format(
            args.sample
        ),
        required=bool(args.enable_hpv),
        required_columns=(
            "mapped_reads",
            "E6_count",
            "E7_count",
            "E1_count",
        ),
        nonnegative=(
            "mapped_reads",
            "E6_count",
            "E7_count",
            "E1_count",
        ),
    )

    add(
        "integration_loci",
        sample_dir
        / "07_hpv_integration"
        / "{}.hpv_integration_loci.annotated.tsv".format(
            args.sample
        ),
        required=False,
        allow_empty=True,
    )

    add(
        "herv_locus",
        sample_dir
        / "09_herv_expression"
        / "{}.herv_locus_counts.normalized.tsv".format(
            args.sample
        ),
        required=bool(args.enable_herv),
        key="locus_id",
        required_columns=(
            "locus_id",
            "count",
            "cpm",
            "tpm_herv_space",
            "rpkm_herv_space",
            "rpm_library",
        ),
        nonnegative=(
            "count",
            "cpm",
            "tpm_herv_space",
            "rpkm_herv_space",
            "rpm_library",
        ),
    )

    add(
        "herv_repeat_name",
        sample_dir
        / "09_herv_expression"
        / "{}.herv_repeat_name_summary.tsv".format(
            args.sample
        ),
        required=bool(args.enable_herv),
        required_columns=(
            "repeat_class",
            "repeat_family",
            "repeat_name",
            "total_count",
            "total_cpm",
            "total_rpm_library",
        ),
        nonnegative=(
            "total_count",
            "total_cpm",
            "total_rpm_library",
        ),
    )

    add(
        "te_locus",
        sample_dir
        / "10_te_expression"
        / "{}.te_locus_counts.normalized.tsv".format(
            args.sample
        ),
        required=bool(args.enable_te),
        key="locus_id",
        required_columns=(
            "locus_id",
            "count",
            "cpm_te_space",
            "tpm_te_space",
            "rpkm_te_space",
            "rpm_library",
        ),
        nonnegative=(
            "count",
            "cpm_te_space",
            "tpm_te_space",
            "rpkm_te_space",
            "rpm_library",
        ),
    )

    add(
        "te_repeat_name",
        sample_dir
        / "10_te_expression"
        / "{}.te_repeat_name_summary.tsv".format(
            args.sample
        ),
        required=bool(args.enable_te),
        required_columns=(
            "te_class_group",
            "repeat_family",
            "repeat_name",
            "total_count",
            "total_cpm",
            "total_rpm_library",
        ),
        nonnegative=(
            "total_count",
            "total_cpm",
            "total_rpm_library",
        ),
    )

    add(
        "telescope_locus",
        sample_dir
        / "11_telescope"
        / "{}.telescope_counts.normalized.tsv".format(
            args.sample
        ),
        required=bool(args.enable_telescope),
        key="locus_id",
        required_columns=(
            "transcript",
            "transcript_length",
            "final_count",
            "locus_id",
            "telescope_count",
            "telescope_rpm",
            "repeat_name",
            "repeat_class",
            "te_class_group",
            "repeat_family",
            "is_herv_ltr_erv_like",
        ),
        nonnegative=(
            "transcript_length",
            "final_count",
            "telescope_count",
            "telescope_rpm",
        ),
        forbidden_key_prefixes=("__",),
    )

    add(
        "telescope_special",
        sample_dir
        / "11_telescope"
        / "{}.telescope_special_counts.tsv".format(
            args.sample
        ),
        required=bool(args.enable_telescope),
        key="locus_id",
        required_columns=(
            "transcript",
            "transcript_length",
            "final_count",
            "locus_id",
            "telescope_count",
        ),
        nonnegative=(
            "transcript_length",
            "final_count",
            "telescope_count",
        ),
        allow_empty=True,
        required_key_prefixes=("__",),
    )

    add(
        "telescope_class",
        sample_dir
        / "11_telescope"
        / "{}.telescope_class_summary.tsv".format(
            args.sample
        ),
        required=bool(args.enable_telescope),
        required_columns=(
            "sample_id",
            "te_class_group",
            "total_telescope_count",
            "telescope_rpm",
        ),
        nonnegative=(
            "total_telescope_count",
            "telescope_rpm",
        ),
    )

    add(
        "telescope_family",
        sample_dir
        / "11_telescope"
        / "{}.telescope_family_summary.tsv".format(
            args.sample
        ),
        required=bool(args.enable_telescope),
        required_columns=(
            "sample_id",
            "te_class_group",
            "repeat_family",
            "total_telescope_count",
            "telescope_rpm",
        ),
        nonnegative=(
            "total_telescope_count",
            "telescope_rpm",
        ),
    )

    add(
        "telescope_repeat_name",
        sample_dir
        / "11_telescope"
        / "{}.telescope_repeat_name_summary.tsv".format(
            args.sample
        ),
        required=bool(args.enable_telescope),
        required_columns=(
            "sample_id",
            "te_class_group",
            "repeat_family",
            "repeat_name",
            "total_telescope_count",
            "telescope_rpm",
        ),
        nonnegative=(
            "total_telescope_count",
            "telescope_rpm",
        ),
    )

    add(
        "telescope_overview",
        sample_dir
        / "11_telescope"
        / "{}.telescope_overview.tsv".format(
            args.sample
        ),
        required=bool(args.enable_telescope),
        required_columns=(
            "sample_id",
            "telescope_total_assigned_count",
            "telescope_special_row_count",
            "telescope_special_total_count",
            "telescope_no_feature_count",
        ),
        nonnegative=(
            "telescope_total_assigned_count",
            "telescope_special_row_count",
            "telescope_special_total_count",
            "telescope_no_feature_count",
        ),
    )

    output = pd.DataFrame(checks)

    output_path = Path(args.out)
    output_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )
    output.to_csv(
        output_path,
        sep="\t",
        index=False,
    )

    passed = bool(
        output["passed"].all()
    )

    validated_files = {}

    for path in sample_dir.rglob("*.tsv"):
        if (
            path.is_file()
            and path.stat().st_size > 0
            and (
                "normalized" in path.name
                or "summary" in path.name
                or path.name.endswith(
                    "features.tsv"
                )
                or path.name.endswith(
                    "overview.tsv"
                )
                or path.name.endswith(
                    "special_counts.tsv"
                )
            )
        ):
            validated_files[
                str(path.relative_to(sample_dir))
            ] = {
                "size_bytes": path.stat().st_size,
                "sha256": sha(path),
            }

    marker = {
        "sample": args.sample,
        "status": (
            "complete"
            if passed
            else "failed_validation"
        ),
        "strict_validation_passed": passed,
        "validated_at_utc": datetime.now(
            timezone.utc
        ).isoformat(),
        "pipeline_version": version,
        "pipeline_git_commit": git_commit,
        "pipeline_git_describe": git_describe,
        "validated_feature_files": validated_files,
    }

    marker_path = Path(args.marker)
    marker_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )
    marker_path.write_text(
        json.dumps(
            marker,
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    if not passed:
        print(
            output[
                ~output["passed"]
            ].to_string(index=False)
        )
        raise SystemExit(2)


if __name__ == "__main__":
    main()
