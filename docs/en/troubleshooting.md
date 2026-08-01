# Troubleshooting

[Documentation index](README.md) · [Verification](verification.md)

## Docker CLI is missing

```bash
command -v docker
```

Ask the administrator to install or expose Docker.

## Docker daemon access is denied

```bash
docker info
```

Do not modify Docker socket permissions or use `sudo` unless system policy explicitly permits it.

## Image is missing

```bash
bash 4.Scripts/endo-exo.sh setup
```

or:

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/archive.tar.gz
```

## Image ID mismatch

Investigate the manifest and build history before using `--replace-tags`.

## SHA-256 or archive-size mismatch

Do not run `docker load`. Obtain the complete matching archive, checksum, and manifest again.

## Insufficient Docker storage

```bash
docker info --format '{{.DockerRootDir}}'
df -h /var/lib/docker
```

Endo-exo does not automatically prune Docker data.

## Node is skipped

```bash
sinfo -N -o "%N %T %E"
```

`SKIPPED_STATE` and exit code `3` mean that eligible nodes succeeded but at least one selected node was unavailable.

## Interrupted `srun`

Check `squeue`, node logs, and run `verify_images.sh --manifest` on the target node. Re-running distribution is idempotent when image IDs already match.

## Slurm accounting is unavailable

Use `squeue`, `.out`, `.err`, per-node return-code files, `summary.tsv`, pipeline status files, and completion markers.
