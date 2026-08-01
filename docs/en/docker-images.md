# Docker image lifecycle

[Documentation index](README.md) · [Local installation](installation-local.md) · [Slurm installation](installation-slurm.md)

Default image references:

```text
endo-exo/core:3.0.0
endo-exo/telescope:3.0.0
```

A tag is not an immutable identity. Endo-exo compares full Docker image IDs.

## Build

```bash
bash 4.Scripts/docker/build_images.sh
```

Optional:

```bash
bash 4.Scripts/docker/build_images.sh --core-only
bash 4.Scripts/docker/build_images.sh --telescope-only
```

## Verify

```bash
bash 4.Scripts/docker/verify_images.sh
bash 4.Scripts/docker/verify_images.sh --ids-only
```

## Export

```bash
bash 4.Scripts/docker/export_images.sh \
  --output-dir /shared/software/endo-exo/images
```

Artifacts:

```text
endo-exo_<version>_<commit>_images.tar.gz
endo-exo_<version>_<commit>_images.tar.gz.sha256
endo-exo_<version>_<commit>_images.manifest.env
```

## Load

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/archive.tar.gz
```

Existing mismatching tags stop the operation unless `--replace-tags` is explicitly supplied.

The script never runs Docker pruning and does not delete unrelated images.

## Update and rollback

Keep the previous artifact set until the new images pass a regression run. Rollback is performed by loading the previous archive with its original manifest and running `verify_images.sh --manifest`.
