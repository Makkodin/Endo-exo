# Endo-exo

[English documentation](docs/README_EN.md)

**Endo-exo 3.0.0** — контейнеризированный пайплайн для обработки парных bulk RNA-seq данных человека и формирования машиночитаемых таблиц признаков для последующего статистического анализа.

Пайплайн рассчитывает технические показатели FASTQ и BAM, экспрессию человеческих генов, сигналы HPV, кандидаты human–HPV junction/integration, экспрессию HERV и других повторов, а также локусные оценки Telescope.

Клиническая метадата, сравнение групп, статистические тесты, графики и отчёты в вычислительный контур не входят.

## Что рассчитывается

Для каждого образца формируются:

- показатели входных FASTQ;
- показатели `fastp`, если очистка включена;
- статистика выравнивания STAR;
- `samtools flagstat`, `stats` и `idxstats`;
- экспрессия человеческих генов: counts, CPM, TPM, RPKM и STAR gene counts;
- HPV signal, coverage, depth и числовой статус;
- экспрессия HPV-генов;
- кандидаты human–HPV junction и integration loci;
- HERV/LTR/ERV counts и нормализованные значения;
- broad TE/repeat counts и нормализованные значения;
- Telescope locus assignment;
- версии программ;
- реестр файлов до очистки;
- per-sample и run-level validation;
- dense и sparse feature matrices.

## Требования

- Linux x86_64;
- Bash;
- Git;
- Docker Engine;
- доступ пользователя к Docker daemon;
- достаточное место для FASTQ, BAM и STAR indices.

Для Slurm дополнительно требуются `sbatch`, `squeue` и `sinfo`.

Ресурсы по умолчанию на один образец:

```text
CPU: 16
RAM: 76 GB
TIME: 72 hours
```

## Структура проекта

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

Содержимое `1.Data`, `2.Results`, `3.Refs` и `_Logs` не отслеживается Git, кроме `.gitkeep`.

## Установка

Клонируйте репозиторий и перейдите в его каталог:

```bash
git clone https://github.com/Makkodin/Endo-exo.git
cd Endo-exo
```

Соберите Docker images:

```bash
bash 4.Scripts/endo-exo.sh setup
```

Проверьте версию:

```bash
bash 4.Scripts/endo-exo.sh version
```

Ожидаемый вывод:

```text
Endo-exo 3.0.0
```

Запустите статический smoke test:

```bash
bash tests/smoke_test.sh
```

## Входной CSV

Файл должен содержать ровно три колонки:

```text
sample,Fq1,Fq2
```

Пример для локальных paired-end FASTQ:

```csv
sample,Fq1,Fq2
Sample_01,/path/to/Sample_01_R1.fastq.gz,/path/to/Sample_01_R2.fastq.gz
```

Требования:

- `sample` должен быть уникальным;
- допустимы латинские буквы, цифры, `.`, `_` и `-`;
- `Fq1` и `Fq2` должны быть абсолютными путями;
- оба файла должны существовать и иметь ненулевой размер;
- поддерживаются `.fastq`, `.fq`, `.fastq.gz` и `.fq.gz`;
- два поля не должны указывать на один файл.

Для SRA accession используется `Fq1`, а `Fq2` оставляется пустым:

```csv
sample,Fq1,Fq2
Sample_SRA_01,sra:SRR123456,
```

Поддерживаются `SRR`, `ERR` и `DRR`.

Проверка входа:

```bash
bash 4.Scripts/endo-exo.sh validate-input \
  --samples config/samples.example.csv
```

## Конфигурация

Основные настройки находятся в:

```text
config/pipeline.conf
```

Ключевые параметры:

| Параметр | Назначение | По умолчанию |
|---|---|---:|
| `DEFAULT_EXECUTOR` | `auto`, `local` или `slurm` | `auto` |
| `THREADS` | CPU на образец | `16` |
| `LOCAL_JOBS` | параллельные локальные образцы | `1` |
| `TELESCOPE_THREADS` | CPU для Telescope | `8` |
| `ENABLE_HPV` | HPV-модуль | `1` |
| `ENABLE_HERV` | HERV-модуль | `1` |
| `ENABLE_TE` | broad TE-модуль | `1` |
| `ENABLE_TELESCOPE` | Telescope | `1` |
| `ENABLE_HUMAN_GENE_EXPRESSION` | человеческие гены | `1` |
| `FASTP_MODE` | `skip` или `run` | `skip` |
| `HEAVY_FILES_POLICY` | `keep` или `delete` | `keep` |
| `INPUT_CHECKSUM_MODE` | `metadata` или `sha256` | `metadata` |
| `BUILD_LOCUS_SPARSE_MATRICES` | формировать sparse locus matrices | `1` |

Для максимального набора признаков оставьте все `ENABLE_*="1"`.

Параметры Slurm находятся в:

```text
config/slurm.conf
```

При необходимости узлы задаются через:

```bash
SLURM_NODELIST="compute-01,compute-02"
```

## Подготовка референсов

Ожидаемая структура:

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

Подключение готовых GRCh38 FASTA и GENCODE GTF:

```bash
bash 4.Scripts/endo-exo.sh prepare-grch38 \
  --fasta /path/to/GRCh38.fa \
  --gtf /path/to/gencode.gtf \
  --mode link
```

`--mode link` создаёт символические ссылки, `--mode copy` копирует файлы.

Подготовка HPV, combined GRCh38+HPV, HERV и TE references:

```bash
bash 4.Scripts/endo-exo.sh prepare-references \
  --email user@example.org \
  --threads 16
```

Email используется NCBI Entrez при загрузке HPV records.

## Проверка окружения

```bash
bash 4.Scripts/endo-exo.sh doctor \
  --samples config/samples.example.csv
```

Проверяются Docker, Slurm CLI, обязательные references, рабочие каталоги и структура входного CSV.

## Запуск

Автоматический выбор local или Slurm:

```bash
bash 4.Scripts/endo-exo.sh run \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 2 \
  --keep-heavy
```

Локальный режим:

```bash
bash 4.Scripts/endo-exo.sh run-local \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 1 \
  --keep-heavy
```

Slurm:

```bash
bash 4.Scripts/endo-exo.sh run-slurm \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 2 \
  --keep-heavy
```

Опции:

- `--copy-fastq` — копировать локальные FASTQ вместо символических ссылок;
- `--clean-incomplete` — удалить незавершённый управляемый результат перед повторным запуском;
- `--cleanup-heavy` — удалить тяжёлые промежуточные файлы после успешной строгой проверки;
- `--keep-heavy` — сохранить тяжёлые промежуточные файлы.

## Контроль выполнения

Последний Slurm-запуск:

```bash
bash 4.Scripts/endo-exo.sh monitor
```

Конкретный запуск:

```bash
bash 4.Scripts/endo-exo.sh monitor \
  --run-dir _Logs/_slurm/example_run_TIMESTAMP
```

Основной лог образца:

```text
_Logs/<sample>/run_one_sample.full.log
```

Статусы шагов:

```text
2.Results/<sample>/.status/
```

## Результаты одного образца

Корневой каталог:

```text
2.Results/<sample>/
```

Основные файлы:

```text
<sample>.input_manifest.tsv
<sample>.technical_features.tsv
<sample>.sample_features.tsv
<sample>.file_inventory_before_cleanup.tsv
<sample>.software_versions.tsv
<sample>.feature_validation.tsv
<sample>.features_complete.json
```

Модульные каталоги:

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

`technical_features.tsv` содержит технические показатели FASTQ, STAR, samtools и featureCounts.

`sample_features.tsv` содержит одну широкую строку на образец. Полные gene-, repeat- и locus-level значения сохраняются в модульных таблицах.

## Итоговые таблицы запуска

Каталог:

```text
2.Results/Feature_tables/<run-name>/
```

Основные файлы:

| Файл | Содержание |
|---|---|
| `run_sample_features.tsv` | технические и агрегированные sample-level признаки |
| `run_sample_features.parquet` | та же таблица в Parquet |
| `analysis_ready_normalized_sample_by_feature.tsv.gz` | объединённая normalized dense matrix |
| `analysis_ready_normalized_sample_by_feature.parquet` | та же матрица в Parquet |
| `feature_registry.tsv` | реестр блоков и метрик |
| `sample_completion_status.tsv` | статус запрошенных образцов |
| `run_feature_validation.tsv` | run-level проверки |
| `run_features_complete.json` | итоговый completion marker |

Dense matrices находятся в:

```text
blocks/<block>/
```

Поддерживаемые блоки:

```text
human_gene
hpv_gene
herv_class
herv_family
herv_repeat_name
te_class
te_family
te_repeat_name
telescope_class
telescope_family
telescope_repeat_name
```

Lossless sparse locus matrices находятся в:

```text
locus_sparse/<block>/
```

Блоки:

```text
herv_locus
te_locus
telescope_locus
```

## Строгая проверка и очистка

Per-sample validation:

```text
2.Results/<sample>/<sample>.feature_validation.tsv
```

Run-level validation:

```text
2.Results/Feature_tables/<run-name>/run_feature_validation.tsv
```

Очистка разрешается только при наличии успешного strict completion marker.

Предварительный просмотр:

```bash
bash 4.Scripts/endo-exo.sh cleanup-sample \
  --sample Sample_01 \
  --dry-run
```

Очистка одного образца:

```bash
bash 4.Scripts/endo-exo.sh cleanup-sample \
  --sample Sample_01
```

Очистка завершённых образцов из CSV:

```bash
bash 4.Scripts/endo-exo.sh cleanup-completed \
  --samples config/samples.example.csv \
  --dry-run
```

Внешние FASTQ, указанные во входном CSV, не удаляются.

## Повторная сборка таблиц

Run-level таблицы можно повторно построить из валидированных per-sample результатов без повторного выравнивания:

```bash
bash 4.Scripts/endo-exo.sh build-tables \
  --samples config/samples.example.csv \
  --run-name example_run
```

## Downstream-анализ

Рекомендуемые точки входа:

- `run_sample_features.tsv` — технические и агрегированные признаки;
- `analysis_ready_normalized_sample_by_feature.*` — нормализованные dense blocks;
- `blocks/` — отдельные feature matrices;
- `locus_sparse/` — полные HERV, TE и Telescope locus matrices;
- HPV integration long tables — junction- и locus-level сущности;
- `feature_registry.tsv` — происхождение и структура признаков.

Метадата присоединяется отдельно:

```text
feature_table.sample_id = metadata.sample_id
```

Перед статистическим анализом необходимо проверить полноту метадаты, дубликаты образцов, batch structure, library size, mapping rate, zero inflation, нормализацию, технические ковариаты и multiple-testing correction.

## Резервная копия кода

```bash
bash 4.Scripts/maintenance/backup_project.sh
```

Можно указать путь архива:

```bash
bash 4.Scripts/maintenance/backup_project.sh /path/to/Endo-exo_code.tar.gz
```

Архив не включает `.git`, данные, результаты, references и логи. Рядом создаётся SHA256-файл.
