#!/usr/bin/env python3

from __future__ import print_function

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]

SUMMARIZER = (
    ROOT
    / "4.Scripts"
    / "pipeline"
    / "te"
    / "11_summarize_telescope.py"
)

RPM_UTILS = (
    ROOT
    / "4.Scripts"
    / "pipeline"
    / "te"
    / "repeat_utils.py"
)

VALIDATOR = (
    ROOT
    / "4.Scripts"
    / "pipeline"
    / "features"
    / "12_validate_sample_features.py"
)

SAMPLE = "regression_telescope"
READ_PAIRS = 3.0


def fail(message):
    raise RuntimeError(message)


def assert_true(condition, message):
    if not condition:
        fail(message)


def assert_close(
    observed,
    expected,
    label,
    rel_tol=1e-12,
    abs_tol=1e-10,
):
    observed_value = float(observed)
    expected_value = float(expected)

    if not math.isclose(
        observed_value,
        expected_value,
        rel_tol=rel_tol,
        abs_tol=abs_tol,
    ):
        fail(
            "{} mismatch: observed={}, expected={}".format(
                label,
                observed_value,
                expected_value,
            )
        )


def run_command(
    command,
    expected_exit=0,
    environment=None,
):
    print()
    print(
        "command={}".format(
            " ".join(
                str(value)
                for value in command
            )
        )
    )

    process = subprocess.run(
        [
            str(value)
            for value in command
        ],
        cwd=str(ROOT),
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )

    print(
        "command_exit={}".format(
            process.returncode
        )
    )

    if process.stdout:
        print(
            "----- command stdout -----"
        )
        print(
            process.stdout.rstrip()
        )

    if process.stderr:
        print(
            "----- command stderr -----"
        )
        print(
            process.stderr.rstrip()
        )

    if process.returncode != expected_exit:
        fail(
            "unexpected command exit: {} != {}".format(
                process.returncode,
                expected_exit,
            )
        )

    return process


def write_input_tables(test_root):
    report = (
        test_root
        / "telescope_report.tsv"
    )

    metadata = (
        test_root
        / "te_metadata.tsv"
    )

    sample_dir = (
        test_root
        / "positive"
    )

    telescope_dir = (
        sample_dir
        / "11_telescope"
    )

    qc_dir = (
        sample_dir
        / "qc"
    )

    telescope_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    qc_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    report_lines = [
        (
            "## RunInfo"
            "\tversion:1.2.3"
            "\tannotated_features:3"
            "\ttotal_fragments:22"
            "\tpair_mapped:20"
            "\tpair_mixed:1"
            "\tsingle_mapped:1"
            "\tunmapped:0"
            "\tunique:5"
            "\tambig:6"
            "\toverlap_unique:7"
            "\toverlap_ambig:8"
        ),
        "\t".join(
            [
                "transcript",
                "transcript_length",
                "final_count",
                "final_conf",
                "final_prop",
                "init_aligned",
                "unique_count",
                "init_best",
                "init_best_random",
                "init_best_avg",
                "init_prop",
            ]
        ),
        "\t".join(
            [
                "TE_A",
                "1000",
                "7",
                "7.0",
                "0.7",
                "100",
                "10",
                "7",
                "7",
                "7.0",
                "0.7",
            ]
        ),
        "\t".join(
            [
                "TE_B",
                "500",
                "4",
                "4.0",
                "0.4",
                "80",
                "8",
                "4",
                "4",
                "4.0",
                "0.4",
            ]
        ),
        "\t".join(
            [
                "__no_feature",
                "0",
                "11",
                "11.0",
                "0",
                "0",
                "0",
                "0",
                "0",
                "0",
                "0",
            ]
        ),
    ]

    report.write_text(
        "\n".join(report_lines)
        + "\n",
        encoding="utf-8",
    )

    pd.DataFrame(
        [
            {
                "locus_id": "TE_A",
                "repeat_name": "L1PA6",
                "repeat_class": "LINE",
                "te_class_group": "LINE",
                "repeat_family": "L1",
                "is_herv_ltr_erv_like": False,
            },
            {
                "locus_id": "TE_B",
                "repeat_name": "LTR7",
                "repeat_class": "LTR",
                "te_class_group": "LTR",
                "repeat_family": "ERV1",
                "is_herv_ltr_erv_like": True,
            },
        ]
    ).to_csv(
        metadata,
        sep="\t",
        index=False,
    )

    library_path = (
        qc_dir
        / "{}.library_size.tsv".format(
            SAMPLE
        )
    )

    pd.DataFrame(
        [
            {
                "library_read_pairs_after_qc": (
                    READ_PAIRS
                )
            }
        ]
    ).to_csv(
        library_path,
        sep="\t",
        index=False,
    )

    pd.DataFrame(
        [
            {
                "sample_id": SAMPLE,
            }
        ]
    ).to_csv(
        sample_dir
        / "{}.technical_features.tsv".format(
            SAMPLE
        ),
        sep="\t",
        index=False,
    )

    pd.DataFrame(
        [
            {
                "sample_id": SAMPLE,
            }
        ]
    ).to_csv(
        sample_dir
        / "{}.sample_features.tsv".format(
            SAMPLE
        ),
        sep="\t",
        index=False,
    )

    return {
        "report": report,
        "metadata": metadata,
        "sample_dir": sample_dir,
        "telescope_dir": telescope_dir,
        "library": library_path,
    }


def summarizer_command(paths):
    return [
        sys.executable,
        SUMMARIZER,
        "--sample",
        SAMPLE,
        "--report",
        paths["report"],
        "--metadata",
        paths["metadata"],
        "--library-size",
        paths["library"],
        "--out-dir",
        paths["telescope_dir"],
    ]


def validator_command(
    sample_dir,
    output_prefix,
):
    return [
        sys.executable,
        VALIDATOR,
        "--sample",
        SAMPLE,
        "--sample-dir",
        sample_dir,
        "--enable-human",
        "0",
        "--enable-hpv",
        "0",
        "--enable-herv",
        "0",
        "--enable-te",
        "0",
        "--enable-telescope",
        "1",
        "--out",
        sample_dir
        / (
            output_prefix
            + ".feature_validation.tsv"
        ),
        "--marker",
        sample_dir
        / (
            output_prefix
            + ".features_complete.json"
        ),
    ]


def read_telescope_table(
    sample_dir,
    suffix,
):
    path = (
        sample_dir
        / "11_telescope"
        / "{}.{}".format(
            SAMPLE,
            suffix,
        )
    )

    assert_true(
        path.is_file(),
        "missing Telescope output: {}".format(
            path
        ),
    )

    return pd.read_csv(
        path,
        sep="\t",
        low_memory=False,
    )


def validate_producer_outputs(
    sample_dir,
):
    locus = read_telescope_table(
        sample_dir,
        "telescope_counts.normalized.tsv",
    )

    special = read_telescope_table(
        sample_dir,
        "telescope_special_counts.tsv",
    )

    class_summary = read_telescope_table(
        sample_dir,
        "telescope_class_summary.tsv",
    )

    family_summary = read_telescope_table(
        sample_dir,
        "telescope_family_summary.tsv",
    )

    repeat_summary = read_telescope_table(
        sample_dir,
        "telescope_repeat_name_summary.tsv",
    )

    overview = read_telescope_table(
        sample_dir,
        "telescope_overview.tsv",
    )

    assert_true(
        len(locus) == 2,
        "biological locus table must contain 2 rows",
    )

    assert_true(
        set(
            locus["locus_id"].astype(str)
        )
        == {
            "TE_A",
            "TE_B",
        },
        "unexpected biological locus IDs",
    )

    assert_true(
        not locus[
            "locus_id"
        ].astype(str).str.startswith(
            "__"
        ).any(),
        "special IDs remain in biological table",
    )

    observed_counts = dict(
        zip(
            locus[
                "locus_id"
            ].astype(str),
            pd.to_numeric(
                locus[
                    "telescope_count"
                ],
                errors="raise",
            ),
        )
    )

    assert_close(
        observed_counts["TE_A"],
        7.0,
        "TE_A final count",
    )

    assert_close(
        observed_counts["TE_B"],
        4.0,
        "TE_B final count",
    )

    final_count = pd.to_numeric(
        locus["final_count"],
        errors="raise",
    )

    telescope_count = pd.to_numeric(
        locus["telescope_count"],
        errors="raise",
    )

    assert_true(
        (
            final_count
            == telescope_count
        ).all(),
        "final_count and telescope_count differ",
    )

    assert_true(
        len(special) == 1,
        "special table must contain one row",
    )

    assert_true(
        str(
            special.iloc[0]["locus_id"]
        )
        == "__no_feature",
        "special locus ID mismatch",
    )

    assert_close(
        special.iloc[0][
            "final_count"
        ],
        11.0,
        "special final_count",
    )

    assert_close(
        special.iloc[0][
            "telescope_count"
        ],
        11.0,
        "special telescope_count",
    )

    for _, row in locus.iterrows():
        expected_rpm = (
            float(
                row["telescope_count"]
            )
            * 1_000_000.0
            / READ_PAIRS
        )

        assert_close(
            row["telescope_rpm"],
            expected_rpm,
            "locus RPM {}".format(
                row["locus_id"]
            ),
        )

    expected_te_a_rpm = (
        7.0
        * 1_000_000.0
        / READ_PAIRS
    )

    observed_te_a_rpm = float(
        locus.loc[
            locus["locus_id"]
            == "TE_A",
            "telescope_rpm",
        ].iloc[0]
    )

    six_decimal_value = round(
        expected_te_a_rpm,
        6,
    )

    assert_true(
        abs(
            observed_te_a_rpm
            - six_decimal_value
        )
        > 1e-10,
        "RPM was rounded to six decimal places",
    )

    biological_total = float(
        telescope_count.sum()
    )

    assert_close(
        biological_total,
        11.0,
        "biological total",
    )

    summary_tables = [
        (
            "class",
            class_summary,
        ),
        (
            "family",
            family_summary,
        ),
        (
            "repeat_name",
            repeat_summary,
        ),
    ]

    for label, frame in summary_tables:
        assert_true(
            "sample_id"
            in frame.columns,
            "{} summary lacks sample_id".format(
                label
            ),
        )

        assert_true(
            set(
                frame[
                    "sample_id"
                ].astype(str)
            )
            == {
                SAMPLE,
            },
            "{} summary sample_id mismatch".format(
                label
            ),
        )

        counts = pd.to_numeric(
            frame[
                "total_telescope_count"
            ],
            errors="raise",
        )

        rpms = pd.to_numeric(
            frame[
                "telescope_rpm"
            ],
            errors="raise",
        )

        assert_close(
            counts.sum(),
            biological_total,
            "{} summary count additivity".format(
                label
            ),
        )

        expected_rpms = (
            counts
            * 1_000_000.0
            / READ_PAIRS
        )

        for row_number, (
            observed_rpm,
            expected_rpm,
        ) in enumerate(
            zip(
                rpms,
                expected_rpms,
            ),
            start=1,
        ):
            assert_close(
                observed_rpm,
                expected_rpm,
                "{} summary RPM row {}".format(
                    label,
                    row_number,
                ),
            )

    assert_true(
        len(overview) == 1,
        "overview must contain one row",
    )

    overview_row = overview.iloc[0]

    assert_true(
        str(
            overview_row[
                "sample_id"
            ]
        )
        == SAMPLE,
        "overview sample_id mismatch",
    )

    assert_close(
        overview_row[
            "telescope_total_assigned_count"
        ],
        11.0,
        "overview biological count",
    )

    assert_close(
        overview_row[
            "telescope_special_row_count"
        ],
        1.0,
        "overview special row count",
    )

    assert_close(
        overview_row[
            "telescope_special_total_count"
        ],
        11.0,
        "overview special total",
    )

    assert_close(
        overview_row[
            "telescope_no_feature_count"
        ],
        11.0,
        "overview no-feature count",
    )

    assert_true(
        str(
            overview_row[
                "telescope_runinfo_version"
            ]
        )
        == "1.2.3",
        "RunInfo version was not preserved",
    )

    assert_close(
        overview_row[
            "telescope_runinfo_total_fragments"
        ],
        22.0,
        "RunInfo total_fragments",
    )

    print(
        "telescope_producer_contract=OK"
    )


def validation_record(
    validation_path,
    check_name,
):
    frame = pd.read_csv(
        validation_path,
        sep="\t",
        low_memory=False,
    )

    selected = frame.loc[
        frame["check"].astype(str)
        == check_name
    ]

    assert_true(
        len(selected) == 1,
        "validation check {} is missing or duplicated".format(
            check_name
        ),
    )

    return selected.iloc[0]


def validation_passed(value):
    return str(value).strip().lower() in {
        "true",
        "1",
    }


def validate_positive_contract(
    sample_dir,
):
    validation_path = (
        sample_dir
        / "positive.feature_validation.tsv"
    )

    marker_path = (
        sample_dir
        / "positive.features_complete.json"
    )

    validation = pd.read_csv(
        validation_path,
        sep="\t",
        low_memory=False,
    )

    assert_true(
        validation[
            "passed"
        ].map(
            validation_passed
        ).all(),
        "positive validation contains failed checks",
    )

    required_telescope_checks = [
        "telescope_locus",
        "telescope_special",
        "telescope_class",
        "telescope_family",
        "telescope_repeat_name",
        "telescope_overview",
    ]

    for check_name in required_telescope_checks:
        record = validation_record(
            validation_path,
            check_name,
        )

        assert_true(
            validation_passed(
                record["passed"]
            ),
            "{} did not pass".format(
                check_name
            ),
        )

        assert_true(
            str(
                record["status"]
            )
            in {
                "ok",
                "ok_empty",
            },
            "{} unexpected status: {}".format(
                check_name,
                record["status"],
            ),
        )

    marker = json.loads(
        marker_path.read_text(
            encoding="utf-8"
        )
    )

    assert_true(
        marker.get(
            "status"
        )
        == "complete",
        "positive marker status mismatch",
    )

    assert_true(
        marker.get(
            "strict_validation_passed"
        )
        is True,
        "positive marker is not strict",
    )

    validated_files = marker.get(
        "validated_feature_files",
        {}
    )

    required_marker_files = [
        (
            "11_telescope/"
            + SAMPLE
            + ".telescope_counts.normalized.tsv"
        ),
        (
            "11_telescope/"
            + SAMPLE
            + ".telescope_special_counts.tsv"
        ),
        (
            "11_telescope/"
            + SAMPLE
            + ".telescope_overview.tsv"
        ),
    ]

    for relative_path in required_marker_files:
        assert_true(
            relative_path
            in validated_files,
            "marker lacks {}".format(
                relative_path
            ),
        )

    print(
        "telescope_positive_validator_contract=OK"
    )


def validate_missing_count_negative(
    positive_dir,
    test_root,
    environment,
):
    negative_dir = (
        test_root
        / "negative_missing_count"
    )

    shutil.copytree(
        str(positive_dir),
        str(negative_dir),
    )

    locus_path = (
        negative_dir
        / "11_telescope"
        / (
            SAMPLE
            + ".telescope_counts.normalized.tsv"
        )
    )

    locus = pd.read_csv(
        locus_path,
        sep="\t",
        low_memory=False,
    )

    locus = locus.drop(
        columns=[
            "telescope_count",
        ]
    )

    locus.to_csv(
        locus_path,
        sep="\t",
        index=False,
    )

    run_command(
        validator_command(
            negative_dir,
            "negative_missing_count",
        ),
        expected_exit=2,
        environment=environment,
    )

    validation_path = (
        negative_dir
        / "negative_missing_count.feature_validation.tsv"
    )

    record = validation_record(
        validation_path,
        "telescope_locus",
    )

    assert_true(
        not validation_passed(
            record["passed"]
        ),
        "missing telescope_count was accepted",
    )

    assert_true(
        str(
            record["status"]
        )
        == "missing_columns:telescope_count",
        "unexpected missing-column status: {}".format(
            record["status"]
        ),
    )

    marker = json.loads(
        (
            negative_dir
            / "negative_missing_count.features_complete.json"
        ).read_text(
            encoding="utf-8"
        )
    )

    assert_true(
        marker.get(
            "strict_validation_passed"
        )
        is False,
        "missing-column marker incorrectly passed",
    )

    print(
        "telescope_missing_count_negative_contract=OK"
    )


def validate_special_locus_negative(
    positive_dir,
    test_root,
    environment,
):
    negative_dir = (
        test_root
        / "negative_special_in_locus"
    )

    shutil.copytree(
        str(positive_dir),
        str(negative_dir),
    )

    locus_path = (
        negative_dir
        / "11_telescope"
        / (
            SAMPLE
            + ".telescope_counts.normalized.tsv"
        )
    )

    locus = pd.read_csv(
        locus_path,
        sep="\t",
        low_memory=False,
    )

    special_row = locus.iloc[0].copy()

    special_row[
        "transcript"
    ] = "__no_feature"

    special_row[
        "locus_id"
    ] = "__no_feature"

    special_row[
        "transcript_length"
    ] = 0

    special_row[
        "final_count"
    ] = 11

    special_row[
        "telescope_count"
    ] = 11

    special_row[
        "telescope_rpm"
    ] = (
        11.0
        * 1_000_000.0
        / READ_PAIRS
    )

    locus = pd.concat(
        [
            locus,
            pd.DataFrame(
                [
                    special_row,
                ]
            ),
        ],
        ignore_index=True,
    )

    locus.to_csv(
        locus_path,
        sep="\t",
        index=False,
    )

    run_command(
        validator_command(
            negative_dir,
            "negative_special_in_locus",
        ),
        expected_exit=2,
        environment=environment,
    )

    validation_path = (
        negative_dir
        / "negative_special_in_locus.feature_validation.tsv"
    )

    record = validation_record(
        validation_path,
        "telescope_locus",
    )

    assert_true(
        not validation_passed(
            record["passed"]
        ),
        "special biological locus was accepted",
    )

    assert_true(
        str(
            record["status"]
        )
        == "forbidden_locus_id_prefix",
        "unexpected forbidden-prefix status: {}".format(
            record["status"]
        ),
    )

    marker = json.loads(
        (
            negative_dir
            / "negative_special_in_locus.features_complete.json"
        ).read_text(
            encoding="utf-8"
        )
    )

    assert_true(
        marker.get(
            "strict_validation_passed"
        )
        is False,
        "forbidden-prefix marker incorrectly passed",
    )

    print(
        "telescope_special_locus_negative_contract=OK"
    )


def validate_source_guards():
    summarizer_source = SUMMARIZER.read_text(
        encoding="utf-8"
    )

    rpm_source = RPM_UTILS.read_text(
        encoding="utf-8"
    )

    validator_source = VALIDATOR.read_text(
        encoding="utf-8"
    )

    required_summarizer_fragments = [
        "def read_telescope_report",
        'comment="#"',
        '"final_count"',
        'str.startswith(\n        "__"',
        "telescope_special_counts.tsv",
        "telescope_runinfo_version",
    ]

    for fragment in required_summarizer_fragments:
        assert_true(
            fragment
            in summarizer_source,
            "summarizer source lacks {}".format(
                fragment
            ),
        )

    assert_true(
        "return round("
        not in rpm_source,
        "RPM utility still rounds producer values",
    )

    required_validator_fragments = [
        "missing_columns:",
        "forbidden_key_prefixes",
        "required_key_prefixes",
        "telescope_special",
        "telescope_overview",
    ]

    for fragment in required_validator_fragments:
        assert_true(
            fragment
            in validator_source,
            "validator source lacks {}".format(
                fragment
            ),
        )

    print(
        "telescope_static_source_guards=OK"
    )


def main():
    print(
        "===== TELESCOPE RUNTIME CONTRACT REGRESSION ====="
    )
    print(
        "project_root={}".format(
            ROOT
        )
    )

    validate_source_guards()

    environment = os.environ.copy()
    environment[
        "ENDO_EXO_VERSION"
    ] = "3.0.0-regression"
    environment[
        "ENDO_EXO_GIT_COMMIT"
    ] = "synthetic-regression"
    environment[
        "ENDO_EXO_GIT_DESCRIBE"
    ] = "synthetic-regression-dirty"

    with tempfile.TemporaryDirectory(
        prefix="endo_exo_telescope_regression_"
    ) as temporary:
        test_root = Path(temporary)

        print(
            "temporary_test_root={}".format(
                test_root
            )
        )

        paths = write_input_tables(
            test_root
        )

        run_command(
            summarizer_command(
                paths
            ),
            expected_exit=0,
            environment=environment,
        )

        validate_producer_outputs(
            paths["sample_dir"]
        )

        run_command(
            validator_command(
                paths["sample_dir"],
                "positive",
            ),
            expected_exit=0,
            environment=environment,
        )

        validate_positive_contract(
            paths["sample_dir"]
        )

        validate_missing_count_negative(
            paths["sample_dir"],
            test_root,
            environment,
        )

        validate_special_locus_negative(
            paths["sample_dir"],
            test_root,
            environment,
        )

    print()
    print(
        "telescope_runtime_contract_regression=OK"
    )


if __name__ == "__main__":
    main()
