# Slurm installation

[Documentation index](README.md) · [Docker images](docker-images.md) · [Verification](verification.md)

Docker images are normally stored locally by every compute-node Docker daemon. An image on the submission host is not automatically available on compute nodes.

## Administrator requirements

Each compute node must provide:

- Docker Engine and a running daemon;
- approved user access;
- compatible CPU architecture;
- sufficient Docker storage;
- access to shared project files and archives;
- `srun`, `sbatch`, `sinfo`, and `squeue`.

## Preflight

```bash
sinfo -N -o "%N %T %C %E"
```

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  docker info
```

## Build and export

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  bash 4.Scripts/docker/build_images.sh
```

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  bash 4.Scripts/docker/export_images.sh \
    --output-dir /shared/software/endo-exo/images
```

## Explicit node list

```bash
bash 4.Scripts/docker/distribute_images_slurm.sh \
  --archive /shared/software/endo-exo/images/endo-exo_3.0.0_COMMIT_images.tar.gz \
  --partition compute \
  --nodes compute-a01,compute-a02,compute-a03 \
  --max-parallel 1
```

## All partition nodes

```bash
bash 4.Scripts/docker/distribute_images_slurm.sh \
  --archive /shared/software/endo-exo/images/endo-exo_3.0.0_COMMIT_images.tar.gz \
  --partition compute \
  --available-nodes \
  --max-parallel 1
```

Blocked nodes are recorded as `SKIPPED_STATE`.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Every eligible selected node succeeded |
| `1` | At least one eligible node failed |
| `3` | No failure, but at least one node was skipped |

## Pipeline execution

```bash
bash 4.Scripts/endo-exo.sh run-slurm \
  --samples config/samples.example.csv \
  --run-name cohort_run \
  --threads 16 \
  --jobs 2 \
  --keep-heavy
```
