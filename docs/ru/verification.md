# Проверка установки

[Оглавление](README.md) · [Решение проблем](troubleshooting.md)

## Статическая проверка

```bash
bash tests/smoke_test.sh
```

Ожидается:

```text
SMOKE TEST PASSED
```

## Проверка окружения

```bash
bash 4.Scripts/endo-exo.sh doctor
```

С входным CSV:

```bash
bash 4.Scripts/endo-exo.sh doctor \
  --samples config/samples.example.csv
```

## Проверка Docker-образов

```bash
bash 4.Scripts/docker/verify_images.sh
```

Проверяются:

```text
STAR
samtools
Bowtie2
fastp
featureCounts
bedtools
SeqKit
Python
Python imports
Telescope
telescope --help
telescope assign -h
```

Ожидаемые маркеры:

```text
core_image_status=OK
core_runtime_status=OK
telescope_image_status=OK
telescope_runtime_status=OK
final_status=OK
```

## Проверка против манифеста

```bash
bash 4.Scripts/docker/verify_images.sh \
  --manifest /shared/software/endo-exo/images/archive.manifest.env
```

## Проверка CSV

```bash
bash 4.Scripts/endo-exo.sh validate-input \
  --samples config/samples.example.csv
```

Проверьте:

- уникальность `sample`;
- абсолютные пути FASTQ;
- соответствие R1 и R2;
- ненулевой размер;
- доступность FASTQ на compute-узлах.

## Локальный smoke test

```bash
bash 4.Scripts/endo-exo.sh run-local \
  --samples config/samples.smoke.csv \
  --run-name local_smoke \
  --threads 4 \
  --jobs 1 \
  --keep-heavy
```

## Slurm smoke test

```bash
bash 4.Scripts/endo-exo.sh run-slurm \
  --samples config/samples.smoke.csv \
  --run-name slurm_smoke \
  --threads 4 \
  --jobs 1 \
  --keep-heavy
```

Используйте валидную paired-end контрольную библиотеку.

## Признаки успешного завершения

Для образца:

```text
2.Results/<sample>/<sample>.feature_validation.tsv
2.Results/<sample>/<sample>.features_complete.json
```

Для запуска:

```text
2.Results/Feature_tables/<run-name>/run_feature_validation.tsv
2.Results/Feature_tables/<run-name>/run_features_complete.json
```

Очистка тяжёлых файлов разрешается только после успешной строгой валидации.
