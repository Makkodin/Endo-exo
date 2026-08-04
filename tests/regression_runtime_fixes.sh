#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo '[regression 1/5] Empty SRA field preserves FASTQ columns'

tmp_normalized="$(mktemp)"

cleanup() {
  rm -f "$tmp_normalized"
}

trap cleanup EXIT

printf '%s\n' \
  $'sample\tinput_type\tsra\tFq1\tFq2' \
  $'smoke_fastq\tfastq\t\t/tmp/R1.fastq.gz\t/tmp/R2.fastq.gz' \
  > "$tmp_normalized"

line="$(
  awk -v n=1 '
    BEGIN {
      FS="\t"
    }

    NR==n+1 {
      printf "%s\034%s\034%s\034%s\034%s\n",
        $1, $2, $3, $4, $5
      exit
    }
  ' "$tmp_normalized"
)"

IFS=$'\034' read -r \
  sample \
  input_type \
  sra \
  fq1 \
  fq2 \
  <<< "$line"

[[ "$sample" == "smoke_fastq" ]]
[[ "$input_type" == "fastq" ]]
[[ -z "$sra" ]]
[[ "$fq1" == "/tmp/R1.fastq.gz" ]]
[[ "$fq2" == "/tmp/R2.fastq.gz" ]]

python3 - <<'PY'
from pathlib import Path

path = Path(
    "4.Scripts/pipeline/run_batch_slurm.sh"
)

text = path.read_text(encoding="utf-8")

required = [
    "read -r sample type sra fq1 fq2",
    "\\034",
]

missing = [
    value
    for value in required
    if value not in text
]

if missing:
    raise SystemExit(
        "Missing empty-field parser guards: {}".format(
            ", ".join(missing)
        )
    )

print("empty_sra_parser_guard=OK")
PY

echo '[regression 2/5] HERV normalized-locus output is canonical'

python3 - <<'PY'
from pathlib import Path

path = Path(
    "4.Scripts/pipeline/herv/"
    "09_herv_expression.sh"
)

text = path.read_text(encoding="utf-8")

required = [
    "herv_locus_counts.normalized.tsv",
    '-s "$NORMALIZED"',
    'head -20 "$NORMALIZED"',
]

for value in required:
    if value not in text:
        raise SystemExit(
            "Missing HERV normalized-output guard: {}".format(
                value
            )
        )

forbidden = [
    "herv_top_loci.tsv",
]

for value in forbidden:
    if value in text:
        raise SystemExit(
            "Obsolete HERV output remains: {}".format(
                value
            )
        )

print("herv_normalized_output_guard=OK")
PY

echo '[regression 3/5] Readable feature names are stable and unique'

python3 - <<'PY'
from __future__ import print_function

import ast
import hashlib
import re
from pathlib import Path

path = Path(
    "4.Scripts/pipeline/features/"
    "13_build_run_feature_tables.py"
)

source = path.read_text(encoding="utf-8")
tree = ast.parse(source, filename=str(path))

wanted_functions = {
    "clean_feature_value",
    "compact_feature_parts",
    "format_repeat_name",
    "readable_feature_label",
    "unique_feature_columns",
    "include_in_analysis_ready",
    "analysis_exclusion_reason",
}

selected = []

for node in tree.body:
    if isinstance(node, ast.Assign):
        names = [
            target.id
            for target in node.targets
            if isinstance(target, ast.Name)
        ]

        if "READABLE_PREFIX" in names:
            selected.append(node)

    elif (
        isinstance(node, ast.FunctionDef)
        and node.name in wanted_functions
    ):
        selected.append(node)

found_functions = {
    node.name
    for node in selected
    if isinstance(node, ast.FunctionDef)
}

missing_functions = sorted(
    wanted_functions - found_functions
)

if missing_functions:
    raise SystemExit(
        "Missing feature helper functions: {}".format(
            ", ".join(missing_functions)
        )
    )

class FakePandas(object):
    @staticmethod
    def isna(value):
        return value is None

namespace = {
    "re": re,
    "hashlib": hashlib,
    "pd": FakePandas(),
}

try:
    module = ast.Module(
        body=selected,
        type_ignores=[],
    )
except TypeError:
    module = ast.Module(
        body=selected,
    )

module = ast.fix_missing_locations(module)

exec(
    compile(
        module,
        str(path),
        "exec",
    ),
    namespace,
)

prefixes = namespace["READABLE_PREFIX"]

if len(prefixes) != len(set(prefixes.values())):
    raise SystemExit(
        "Readable prefixes are not globally unique"
    )

label = namespace["readable_feature_label"]

examples = [
    (
        "human_gene",
        "tpm",
        {
            "gene_name": "TP53",
            "gene_id_base": "ENSG00000141510",
        },
        "ENSG00000141510.18",
        "GENE_TPM|TP53|ENSG00000141510",
    ),
    (
        "herv_class",
        "total_cpm",
        {
            "repeat_class": "LTR",
        },
        "LTR",
        "HERV_CLASS_CPM|LTR",
    ),
    (
        "herv_family",
        "total_cpm",
        {
            "repeat_class": "LTR",
            "repeat_family": "ERV1",
        },
        "LTR|ERV1",
        "HERV_FAMILY_CPM|LTR|ERV1",
    ),
    (
        "herv_repeat_name",
        "total_cpm",
        {
            "repeat_class": "LTR",
            "repeat_family": "ERV1",
            "repeat_name": "LTR7",
        },
        "LTR|ERV1|LTR7",
        "HERV_REPEAT_CPM|LTR|ERV1|LTR7",
    ),
    (
        "te_repeat_name",
        "total_cpm",
        {
            "te_class_group": "Simple_repeat",
            "repeat_class": "Simple_repeat",
            "repeat_family": "Simple_repeat",
            "repeat_name": "(CGT)n",
        },
        "Simple_repeat|Simple_repeat|"
        "Simple_repeat|(CGT)n",
        "TE_REPEAT_CPM|Simple_repeat|motif=CGT",
    ),
]

for (
    block,
    metric,
    row,
    feature_id,
    expected,
) in examples:
    observed = label(
        block,
        metric,
        row,
        feature_id,
    )

    if observed != expected:
        raise SystemExit(
            "Unexpected readable label for {}: "
            "{} != {}".format(
                block,
                observed,
                expected,
            )
        )

    if "__" in observed:
        raise SystemExit(
            "Old feature-name format remains: {}".format(
                observed
            )
        )

unique_columns = namespace[
    "unique_feature_columns"
](
    [
        "TE_REPEAT_CPM|LINE|L1|L1PA6",
        "TE_REPEAT_CPM|LINE|L1|L1PA6",
    ],
    [
        "feature_a",
        "feature_b",
    ],
)

if len(unique_columns) != 2:
    raise SystemExit(
        "Unexpected unique-column count"
    )

if len(set(unique_columns)) != 2:
    raise SystemExit(
        "Feature-name collision was not resolved"
    )

if not all(
    "|uid=" in value
    for value in unique_columns
):
    raise SystemExit(
        "Colliding features lack stable uid suffixes"
    )

keep = namespace[
    "include_in_analysis_ready"
](
    "te_repeat_name",
    {
        "te_class_group": "Simple_repeat",
    },
)

if keep is not True:
    raise SystemExit(
        "Non-core repeat class was silently filtered"
    )

required_source_markers = [
    "analysis_feature_dictionary.tsv.gz",
    "analysis_feature_dictionary.parquet",
    "base.columns.intersection",
    "global readable feature collision",
    "duplicate readable feature columns",
]

for marker in required_source_markers:
    if marker not in source:
        raise SystemExit(
            "Missing feature-table guard: {}".format(
                marker
            )
        )

print("readable_feature_name_guard=OK")
PY

echo '[regression 4/5] Pipeline provenance is resolved and propagated'

(
  unset PROJECT_DIR
  unset PIPELINE_CONFIG
  unset SLURM_CONFIG
  unset ENDO_EXO_GIT_COMMIT
  unset ENDO_EXO_GIT_DESCRIBE

  # shellcheck disable=SC1091
  source 4.Scripts/common/load_config.sh

  expected_commit="$(
    git -C "$ROOT" rev-parse HEAD
  )"

  [[ "$ENDO_EXO_VERSION" == "3.0.0" ]]
  [[ "$ENDO_EXO_GIT_COMMIT" == "$expected_commit" ]]
  [[ -n "$ENDO_EXO_GIT_DESCRIBE" ]]
  [[ "$ENDO_EXO_GIT_DESCRIBE" != "unknown" ]]

  echo "resolved_pipeline_version=$ENDO_EXO_VERSION"
  echo "resolved_pipeline_git_commit=$ENDO_EXO_GIT_COMMIT"
  echo "resolved_pipeline_git_describe=$ENDO_EXO_GIT_DESCRIBE"
)

python3 - <<'PY_PROVENANCE'
from __future__ import print_function

from pathlib import Path


load_config_path = Path(
    "4.Scripts/common/load_config.sh"
)

load_config = load_config_path.read_text(
    encoding="utf-8"
)

required_config_fragments = [
    'ENDO_EXO_VERSION="3.0.0"',
    'ENDO_EXO_GIT_COMMIT="${ENDO_EXO_GIT_COMMIT:-unknown}"',
    'ENDO_EXO_GIT_DESCRIBE="${ENDO_EXO_GIT_DESCRIBE:-unknown}"',
    "export ENDO_EXO_GIT_COMMIT ENDO_EXO_GIT_DESCRIBE",
]

for fragment in required_config_fragments:
    if fragment not in load_config:
        raise SystemExit(
            "Missing provenance configuration fragment: {}".format(
                fragment
            )
        )


wrapper_path = Path(
    "4.Scripts/docker/run_in_core.sh"
)

wrapper = wrapper_path.read_text(
    encoding="utf-8"
)

required_wrapper_fragments = [
    '-e ENDO_EXO_VERSION="${ENDO_EXO_VERSION}"',
    '-e ENDO_EXO_GIT_COMMIT="${ENDO_EXO_GIT_COMMIT}"',
    '-e ENDO_EXO_GIT_DESCRIBE="${ENDO_EXO_GIT_DESCRIBE}"',
]

for fragment in required_wrapper_fragments:
    count = wrapper.count(fragment)

    if count != 1:
        raise SystemExit(
            "Container provenance forwarding count is {} "
            "for fragment: {}".format(
                count,
                fragment,
            )
        )


script_requirements = {
    Path(
        "4.Scripts/pipeline/features/"
        "12_collect_sample_technical_features.py"
    ): [
        "os.getenv('ENDO_EXO_VERSION','unknown')",
        "os.getenv('ENDO_EXO_GIT_COMMIT','unknown')",
        "os.getenv('ENDO_EXO_GIT_DESCRIBE','unknown')",
        "'pipeline_version':version",
        "'pipeline_git_commit':git_commit",
        "'pipeline_git_describe':git_describe",
    ],
    Path(
        "4.Scripts/pipeline/features/"
        "12_validate_sample_features.py"
    ): [
        "os.getenv('ENDO_EXO_VERSION','unknown')",
        "os.getenv('ENDO_EXO_GIT_COMMIT','unknown')",
        "os.getenv('ENDO_EXO_GIT_DESCRIBE','unknown')",
        "'pipeline_version':version",
        "'pipeline_git_commit':git_commit",
        "'pipeline_git_describe':git_describe",
    ],
    Path(
        "4.Scripts/pipeline/features/"
        "13_build_run_feature_tables.py"
    ): [
        "os.getenv('ENDO_EXO_VERSION','unknown')",
        "os.getenv('ENDO_EXO_GIT_COMMIT','unknown')",
        "os.getenv('ENDO_EXO_GIT_DESCRIBE','unknown')",
        "'pipeline_version':version",
        "'pipeline_git_commit':git_commit",
        "'pipeline_git_describe':git_describe",
    ],
}

def canonicalize_provenance_fragment(value):
    normalized = "".join(
        value.replace('"', "'").split()
    )

    # Permit trailing commas in multiline Python calls,
    # for example os.getenv("NAME", "unknown",).
    while ",)" in normalized:
        normalized = normalized.replace(
            ",)",
            ")",
        )

    return normalized


for script_path, required_fragments in script_requirements.items():
    source = script_path.read_text(
        encoding="utf-8"
    )

    normalized_source = (
        canonicalize_provenance_fragment(
            source
        )
    )

    missing = [
        fragment
        for fragment in required_fragments
        if canonicalize_provenance_fragment(
            fragment
        ) not in normalized_source
    ]

    if missing:
        raise SystemExit(
            "{} lacks provenance fragments: {}".format(
                script_path,
                ", ".join(missing),
            )
        )
print("pipeline_provenance_guard=OK")
PY_PROVENANCE

echo '[regression 5/5] Telescope parsing, RPM precision, and strict validation'

python3 tests/telescope_runtime_contract.py

echo 'RUNTIME REGRESSION TESTS PASSED'
