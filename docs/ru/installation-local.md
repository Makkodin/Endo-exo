# Локальная установка

[Оглавление](README.md) · [Docker-образы](docker-images.md) · [Проверка](verification.md)

Под локальной установкой понимается запуск на Linux-сервере или рабочей станции без Slurm.

## Требования администратора

Администратор должен обеспечить:

- Linux x86_64;
- установленный Docker Engine;
- запущенный Docker daemon;
- разрешённый способ доступа пользователя к Docker;
- достаточное место в Docker root directory;
- доступ к FASTQ и референсам.

Endo-exo не выполняет `sudo`, не изменяет Docker socket и не добавляет пользователя в системные группы.

## Проверка пользователем

```bash
command -v docker
docker version
docker info
```

При ошибке доступа к Docker daemon необходимо обратиться к администратору.

Не следует самостоятельно выполнять:

```text
sudo chmod /var/run/docker.sock
sudo chown /var/run/docker.sock
sudo usermod
```

## Клонирование

```bash
git clone https://github.com/Makkodin/Endo-exo.git
cd Endo-exo

bash tests/smoke_test.sh
```

## Сценарий A: сборка из Dockerfile

```bash
bash 4.Scripts/endo-exo.sh setup
```

Эквивалентная команда:

```bash
bash 4.Scripts/docker/build_images.sh
```

Проверка:

```bash
bash 4.Scripts/docker/verify_images.sh
```

Сборка требует доступа к Docker Registry, Ubuntu repositories, conda-forge, bioconda и PyPI.

## Сценарий B: загрузка готового архива

Комплект должен содержать:

```text
<archive>.tar.gz
<archive>.tar.gz.sha256
<archive>.manifest.env
```

Загрузка:

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/endo-exo_3.0.0_COMMIT_images.tar.gz
```

Перед `docker load` проверяются:

- имя и размер архива;
- SHA-256;
- gzip integrity;
- манифест;
- существующие Docker-теги;
- итоговые image ID;
- runtime инструментов.

Если образы уже совпадают с манифестом, повторная загрузка не выполняется.

## Подготовка референсов

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

Проверка:

```bash
bash 4.Scripts/endo-exo.sh doctor
```

## Локальный запуск

```bash
bash 4.Scripts/endo-exo.sh run-local \
  --samples config/samples.example.csv \
  --run-name local_test \
  --threads 16 \
  --jobs 1 \
  --keep-heavy
```

Для рабочей станции начинайте с `--jobs 1`.

## Внешние каталоги

```bash
export ENDO_EXO_DATA_DIR=/data/endo-exo/input
export ENDO_EXO_RESULTS_DIR=/data/endo-exo/results
export ENDO_EXO_REFS_DIR=/data/endo-exo/references
export ENDO_EXO_LOGS_DIR=/data/endo-exo/logs
```

После изменения Dockerfile необходимо пересобрать образы или загрузить новый проверенный архив. Совпадения одного тега недостаточно: сравнивается полный image ID.
