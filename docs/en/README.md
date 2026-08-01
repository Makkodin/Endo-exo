# Endo-exo documentation

[Main README](../../README.md) · [Русская документация](../ru/README.md)

| Document | Purpose |
|---|---|
| [Local installation](installation-local.md) | Linux server or workstation without Slurm |
| [Slurm installation](installation-slurm.md) | Compute-node preparation and image distribution |
| [Docker images](docker-images.md) | Build, export, load, update, and identity verification |
| [Verification](verification.md) | Static checks, runtime checks, and smoke runs |
| [Troubleshooting](troubleshooting.md) | Docker, Slurm, permissions, archives, and node states |

## Local workflow

1. Check Docker access.
2. Build images or load a verified archive.
3. Verify image IDs and runtime.
4. Prepare references.
5. Run `doctor`.
6. Process one validation sample.
7. Start the main analysis.

## Slurm workflow

1. Confirm that Docker is allowed.
2. Confirm shared-file visibility.
3. Build images once or obtain a verified archive.
4. Distribute images to eligible nodes.
5. Compare full image IDs.
6. Run a one-sample Slurm smoke test.
7. Start the main analysis.
