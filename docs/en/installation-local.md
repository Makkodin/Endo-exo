# Local installation

[Documentation index](README.md) · [Docker images](docker-images.md) · [Verification](verification.md)

## Administrator requirements

The administrator must provide:

- Linux x86_64;
- Docker Engine and a running daemon;
- approved user access to Docker;
- sufficient Docker storage;
- access to FASTQ files and references.

Endo-exo does not run `sudo`, modify Docker socket permissions, or change system groups.

## User preflight

```bash
command -v docker
docker version
docker info
```

Contact the administrator if Docker daemon access fails.

## Clone and test

```bash
git clone https://github.com/Makkodin/Endo-exo.git
cd Endo-exo
bash tests/smoke_test.sh
```

## Build from source

```bash
bash 4.Scripts/endo-exo.sh setup
bash 4.Scripts/docker/verify_images.sh
```

## Load a prepared archive

Required files:

```text
<archive>.tar.gz
<archive>.tar.gz.sha256
<archive>.manifest.env
```

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/endo-exo_3.0.0_COMMIT_images.tar.gz
```

## References

```bash
bash 4.Scripts/endo-exo.sh prepare-grch38 \
  --fasta /references/GRCh38.fa \
  --gtf /references/gencode.gtf \
  --mode link
```

```bash
bash 4.Scripts/endo-exo.sh prepare-references \
  --email user@example.org \
  --threads 16
```

```bash
bash 4.Scripts/endo-exo.sh doctor
```

## Local run

```bash
bash 4.Scripts/endo-exo.sh run-local \
  --samples config/samples.example.csv \
  --run-name local_test \
  --threads 16 \
  --jobs 1 \
  --keep-heavy
```

Start with one concurrent sample.
