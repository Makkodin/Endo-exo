# Endo-exo

**Endo-exo 3.0.0** — контейнеризированный пайплайн обработки парных bulk RNA-seq данных человека с формированием машиночитаемых таблиц признаков для последующего статистического анализа.

[English documentation](docs/en/README.md)

## Назначение

Пайплайн рассчитывает:

- технические показатели FASTQ и BAM;
- экспрессию человеческих генов;
- HPV-сигнал, покрытие и экспрессию вирусных генов;
- кандидаты human–HPV junction и integration loci;
- экспрессию HERV/LTR/ERV;
- broad TE/repeat expression;
- локусные оценки Telescope;
- dense и sparse feature matrices;
- техническую валидацию результатов.

Клиническая метадата, сравнение групп, статистические тесты, графики и содержательные отчёты выполняются отдельно от вычислительного пайплайна.

## Быстрый старт

```bash
git clone https://github.com/Makkodin/Endo-exo.git
cd Endo-exo

bash tests/smoke_test.sh
bash 4.Scripts/endo-exo.sh setup
bash 4.Scripts/endo-exo.sh doctor
```

Локальный запуск:

```bash
bash 4.Scripts/endo-exo.sh run-local \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 1 \
  --keep-heavy
```

Запуск через Slurm:

```bash
bash 4.Scripts/endo-exo.sh run-slurm \
  --samples config/samples.example.csv \
  --run-name example_run \
  --threads 16 \
  --jobs 2 \
  --keep-heavy
```

## Документация

| Раздел | Русская версия | English version | Описание |
|---|---|---|---|
| Оглавление | [Русский](docs/ru/README.md) | [English](docs/en/README.md) | Навигация по документации |
| Локальная установка | [Русский](docs/ru/installation-local.md) | [English](docs/en/installation-local.md) | Linux-сервер или рабочая станция без Slurm |
| Установка на Slurm | [Русский](docs/ru/installation-slurm.md) | [English](docs/en/installation-slurm.md) | Подготовка и распространение образов по compute-узлам |
| Docker-образы | [Русский](docs/ru/docker-images.md) | [English](docs/en/docker-images.md) | Сборка, экспорт, загрузка, SHA-256 и версии |
| Проверка установки | [Русский](docs/ru/verification.md) | [English](docs/en/verification.md) | Проверка кода, образов, референсов и тестовый запуск |
| Решение проблем | [Русский](docs/ru/troubleshooting.md) | [English](docs/en/troubleshooting.md) | Docker, Slurm, права, архивы и состояния узлов |

## Основные требования

- Linux x86_64;
- Bash;
- Git;
- Python 3.6 или новее на управляющем узле;
- Docker Engine;
- разрешённый пользователю доступ к Docker daemon;
- достаточное место для FASTQ, BAM, референсов и Docker-образов.

Для Slurm дополнительно необходимы:

```text
sbatch
squeue
sinfo
srun
```

Ресурсы по умолчанию на один образец:

```text
CPU: 16
RAM: 76 GB
TIME: 72 hours
```

## Входной CSV

Файл должен содержать ровно три колонки:

```text
sample,Fq1,Fq2
```

Локальные paired-end FASTQ:

```csv
sample,Fq1,Fq2
Sample_01,/data/Sample_01_R1.fastq.gz,/data/Sample_01_R2.fastq.gz
```

SRA:

```csv
sample,Fq1,Fq2
Sample_SRA_01,sra:SRR123456,
```

Проверка:

```bash
bash 4.Scripts/endo-exo.sh validate-input \
  --samples config/samples.example.csv
```

## Основные команды

| Команда | Назначение |
|---|---|
| `version` | Показать версию |
| `setup` | Собрать Docker-образы |
| `doctor` | Проверить окружение и референсы |
| `validate-input` | Проверить входной CSV |
| `run` | Автоматически выбрать local или Slurm |
| `run-local` | Выполнить локальный запуск |
| `run-slurm` | Отправить анализ в Slurm |
| `monitor` | Показать состояние Slurm-запуска |
| `build-tables` | Повторно собрать итоговые таблицы |
| `cleanup-sample` | Очистить тяжёлые файлы одного образца |
| `cleanup-completed` | Очистить завершённые образцы |
| `prepare-grch38` | Подключить FASTA и GTF |
| `prepare-references` | Подготовить остальные референсы |

Полная справка:

```bash
bash 4.Scripts/endo-exo.sh --help
```

## Основные результаты

```text
2.Results/<sample>/
2.Results/Feature_tables/<run-name>/
```

Рекомендуемые точки входа:

- `run_sample_features.tsv`;
- `analysis_ready_normalized_sample_by_feature.*`;
- матрицы в `blocks/`;
- sparse locus matrices в `locus_sparse/`;
- `feature_registry.tsv`;
- HPV integration long tables.

## Структура репозитория

```text
1.Data/       входные данные или ссылки
2.Results/    результаты анализа
3.Refs/       референсы и локальные архивы образов
4.Scripts/    код пайплайна и служебные утилиты
config/       настройки и пример CSV
docs/         русская и английская документация
tests/        статические тесты
_Logs/        журналы выполнения
```

Данные, результаты, референсы и журналы не публикуются в Git.
