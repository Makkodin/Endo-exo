# Endo-exo

[Документация на русском](../README.md)

**Endo-exo 3.0.0** is a containerized pipeline for paired-end human bulk RNA-seq data. It produces machine-readable feature tables for downstream statistical analysis.

The workflow calculates FASTQ and BAM technical metrics, human gene expression, HPV signals, candidate human–HPV junctions and integration loci, HERV and broad repeat expression, and Telescope locus-level estimates.

Clinical metadata, group comparisons, statistical tests, plots, dashboards, and narrative reports are outside the computational workflow.

## Calculated feature blocks

For every sample, the pipeline can produce:

- input FASTQ metrics;
- `fastp` metrics when trimming is enabled;
- STAR alignment statistics;
- `samtools flagstat`, `stats`, and `idxstats`;
- human-gene counts, CPM, TPM, RPKM, and STAR gene counts;
- HPV signal, coverage, depth, and numerical status;
- HPV-gene expression;
- candidate human–HPV junctions and integration loci;
- HERV/LTR/ERV counts and normalized values;
- broad TE/repeat counts and normalized values;
- Telescope locus assignment;
- software versions;
- a pre-cleanup file inventory;
- per-sample and run-level validation;
- dense and sparse feature matrices.

## Requirements

- Linux x86_64;
- Bash;
- Git;
- Docker Engine;
- access to the Docker daemon;
- sufficient storage for FASTQ files, BAM files, and STAR indices.

Slurm execution additionally requires `sbatch`, `squeue`, and `sinfo`.

Default resources per sample:

```text
CPU: 16
RAM: 76 GB
TIME: 72 hours
```

## Repository structure

```text
Endo-exo/
├── 1.Data/
├── 2.Results/
├── 3.Refs/
├── 4.Scripts/
│   ├── common/
│   ├── docker/
│   ├── maintenance/
│   ├── pipeline/
│   ├── reference_setup/
│   ├── runtime_bin/
│   └── endo-exo.sh
├── config/
│   ├── pipeline.conf
│   ├── samples.example.csv
│   └── slurm.conf
├── docs/
│   └── README_EN.md
├── tests/
├── _Logs/
├── .gitattributes
├── .gitignore
└── README.md
```

Only `.gitkeep` files are tracked inside `1.Data`, `2.Results`, `3.Refs`, and `_Logs`.

## Installation

```bash
git clone https://github.com/Makkodin/Endo-exo.git
cd Endo-exo
bash 4.Scripts/endo-exo.sh setup
bash 4.Scripts/endo-exo.sh version
bash tests/smoke_test.sh
```

Expected version output:

```text
Endo-exo 3.0.0
```

## Input CSV

The input file must contain exactly:

```text
sample,Fq1,Fq2
```

Local paired-end example:

```csv
sample,Fq1,Fq2
Sample_01,/path/to/Sample_01_R1.fastq.gz,/path/to/Sample_01_R2.fastq.gz
```

Requirements:

- unique `sample` values;
- sample names limited to letters, digits, `.`, `_`, and `-`;
- absolute paths in `Fq1` and `Fq2`;
- existing non-empty files;
- supported suffixes: `.fastq`, `.fq`, `.fastq.gz`, `.fq.gz`;
- R1 and R2 must not point to the same file.

SRA example:

```csv
sample,Fq1,Fq2
Sample_SRA_01,sra:SRR123456,
```

`SRR`, `ERR`, and `DRR` accessions are supported.

Validation:

```bash
bash 4.Scripts/endo-exo.sh validate-input \
  --samples config/samples.example.csv
```

## Configuration

Pipeline settings:

```text
config/pipeline.conf
```

Important parameters:

| Parameter | Purpose | Default |
|---|---|---:|
| `DEFAULT_EXECUTOR` | `auto`, `local`, or `slurm` | `auto` |
| `THREADS` | CPU threads per sample | `16` |
| `LOCAL_JOBS` | parallel local samples | `1` |
| `TELESCOPE_THREADS` | Telescope threads | `8` |
| `ENABLE_HPV` | HPV module | `1` |
| `ENABLE_HERV` | HERV module | `1` |
| `ENABLE_TE` | broad TE module | `1` |
| `ENABLE_TELESCOPE` | Telescope | `1` |
| `ENABLE_HUMAN_GENE_EXPRESSION` | human-gene expression | `1` |
| `FASTP_MODE` | `skip` or `run` | `skip` |
| `HEAVY_FILES_POLICY` | `keep` or `delete` | `keep` |
| `INPUT_CHECKSUM_MODE` | `metadata` or `sha256` | `metadata` |
| `BUILD_LOCUS_SPARSE_MATRICES` | build sparse locus matrices | `1` |

Slurm settings:

```text
config/slurm.conf
```

Optional node allowlist:

```bash
SLURM_NODELIST="compute-01,compute-02"
```

## Reference preparation

Expected layout:

```text
3.Refs/
├── GRCh38/
│   ├── GRCh38.fa
│   ├── gencode.gtf
│   └── STAR_index/Genome
├── HPV/
│   ├── hpv_curated.fa
│   ├── hpv_genes.gtf
│   └── bowtie2_index/hpv_curated.1.bt2
├── GRCh38_HPV/
│   ├── GRCh38_plus_HPV.fa
│   ├── GRCh38_plus_HPV.gtf
│   └── STAR_index/Genome
├── HERV/
│   ├── herv_loci.gtf
│   └── herv_loci.metadata.tsv
└── TE/
    ├── te_loci.gtf
    └── te_loci.metadata.tsv
```

Register existing GRCh38 FASTA and GENCODE GTF:

```bash
bash 4.Scripts/endo-exo.sh prepare-grch38 \
  --fasta /path/to/GRCh38.fa \
  --gtf /path/to/gencode.gtf \
  --mode link
```

Prepare the remaining references:

```bash
bash 4.Scripts/endo-exo.sh prepare-references \
  --email user@example.org \
  --threads 16
```

## Environment check

```bash
bash 4.Scripts/endo-exo.sh doctor \
  --samples config/samples.example.csv
```

## Running the pipeline

Automatic executor selection:

```bash
bash 4.Scripts/endo-exo.sh run \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 2 \
  --keep-heavy
```

Local execution:

```bash
bash 4.Scripts/endo-exo.sh run-local \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 1 \
  --keep-heavy
```

Slurm execution:

```bash
bash 4.Scripts/endo-exo.sh run-slurm \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 2 \
  --keep-heavy
```

## Monitoring

```bash
bash 4.Scripts/endo-exo.sh monitor
```

A specific Slurm run:

```bash
bash 4.Scripts/endo-exo.sh monitor \
  --run-dir _Logs/_slurm/example_run_TIMESTAMP
```

Main sample log:

```text
_Logs/<sample>/run_one_sample.full.log
```

## Per-sample outputs

Root:

```text
2.Results/<sample>/
```

Main files:

```text
<sample>.input_manifest.tsv
<sample>.technical_features.tsv
<sample>.sample_features.tsv
<sample>.file_inventory_before_cleanup.tsv
<sample>.software_versions.tsv
<sample>.feature_validation.tsv
<sample>.features_complete.json
```

Module directories:

```text
03_star_grch38/
05_hpv_calling/
06_hpv_expression/
07_hpv_integration/
08_human_gene_expression/
09_herv_expression/
10_te_expression/
11_telescope/
```

## Run-level feature tables

Root:

```text
2.Results/Feature_tables/<run-name>/
```

Main outputs:

| File | Content |
|---|---|
| `run_sample_features.tsv` | technical and aggregated sample-level features |
| `run_sample_features.parquet` | Parquet representation |
| `analysis_ready_normalized_sample_by_feature.tsv.gz` | combined normalized dense matrix |
| `analysis_ready_normalized_sample_by_feature.parquet` | Parquet representation |
| `feature_registry.tsv` | block and metric registry |
| `sample_completion_status.tsv` | requested-sample status |
| `run_feature_validation.tsv` | run-level validation |
| `run_features_complete.json` | completion marker |

Dense matrices:

```text
blocks/<block>/
```

Sparse locus matrices:

```text
locus_sparse/herv_locus/
locus_sparse/te_locus/
locus_sparse/telescope_locus/
```

## Validation and cleanup

Preview sample cleanup:

```bash
bash 4.Scripts/endo-exo.sh cleanup-sample \
  --sample Sample_01 \
  --dry-run
```

Run sample cleanup:

```bash
bash 4.Scripts/endo-exo.sh cleanup-sample \
  --sample Sample_01
```

Preview cleanup for completed samples:

```bash
bash 4.Scripts/endo-exo.sh cleanup-completed \
  --samples config/samples.example.csv \
  --dry-run
```

External FASTQ files listed in the input CSV are not deleted.

## Rebuilding run-level tables

```bash
bash 4.Scripts/endo-exo.sh build-tables \
  --samples config/samples.example.csv \
  --run-name example_run
```

This operation uses validated per-sample outputs and does not repeat alignment.

## Downstream analysis

Recommended entry points:

- `run_sample_features.tsv`;
- `analysis_ready_normalized_sample_by_feature.*`;
- block-level matrices under `blocks/`;
- locus-level sparse matrices under `locus_sparse/`;
- HPV integration long tables;
- `feature_registry.tsv`.

Join study metadata separately:

```text
feature_table.sample_id = metadata.sample_id
```

## Code backup

```bash
bash 4.Scripts/maintenance/backup_project.sh
```

An optional output path can be supplied as the first argument. The archive excludes `.git`, data, results, references, and logs and is accompanied by a SHA256 file.
