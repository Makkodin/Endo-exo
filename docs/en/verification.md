# Verification

[Documentation index](README.md) · [Troubleshooting](troubleshooting.md)

## Repository smoke test

```bash
bash tests/smoke_test.sh
```

Expected:

```text
SMOKE TEST PASSED
```

## Environment

```bash
bash 4.Scripts/endo-exo.sh doctor
```

## Image runtime

```bash
bash 4.Scripts/docker/verify_images.sh
```

Expected markers:

```text
core_image_status=OK
core_runtime_status=OK
telescope_image_status=OK
telescope_runtime_status=OK
final_status=OK
```

## Manifest comparison

```bash
bash 4.Scripts/docker/verify_images.sh \
  --manifest /shared/software/endo-exo/images/archive.manifest.env
```

## Input validation

```bash
bash 4.Scripts/endo-exo.sh validate-input \
  --samples config/samples.example.csv
```

## Local smoke run

```bash
bash 4.Scripts/endo-exo.sh run-local \
  --samples config/samples.smoke.csv \
  --run-name local_smoke \
  --threads 4 \
  --jobs 1 \
  --keep-heavy
```

## Slurm smoke run

```bash
bash 4.Scripts/endo-exo.sh run-slurm \
  --samples config/samples.smoke.csv \
  --run-name slurm_smoke \
  --threads 4 \
  --jobs 1 \
  --keep-heavy
```

Use a valid paired-end control library.
