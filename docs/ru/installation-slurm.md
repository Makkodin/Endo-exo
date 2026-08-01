# Установка на Slurm-кластере

[Оглавление](README.md) · [Docker-образы](docker-images.md) · [Проверка](verification.md)

## Архитектура

```text
submit host
    |
    | sbatch / srun
    v
compute-a01  compute-a02  compute-a03
    |             |             |
local Docker  local Docker  local Docker
```

Наличие образа на submit host не означает его наличие на compute-узлах.

## Требования администратора

На каждом compute-узле должны быть:

- Docker Engine и запущенный daemon;
- разрешённый пользователю доступ к Docker;
- совместимая архитектура CPU;
- достаточное место в Docker root directory;
- доступ к общей файловой системе;
- `srun`, `sbatch`, `sinfo` и `squeue`.

Docker должен быть разрешён политикой кластера.

Endo-exo не выполняет административные команды и не меняет состояния Slurm-узлов.

## Предварительная проверка

```bash
sinfo -N -o "%N %T %C %E"
```

Проверка Docker на одном узле:

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  docker info
```

Проверка доступности архива:

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  test -r /shared/software/endo-exo/images/archive.tar.gz
```

## Рекомендуемый процесс

1. Собрать образы на одном подходящем compute-узле.
2. Выполнить runtime-проверку.
3. Экспортировать оба образа в общий архив.
4. Проверить SHA-256.
5. Распространить архив по доступным узлам.
6. Сравнить полные image ID.

Сборка:

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  --cpus-per-task 4 \
  --mem 8G \
  bash 4.Scripts/docker/build_images.sh
```

Экспорт:

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  bash 4.Scripts/docker/export_images.sh \
    --output-dir /shared/software/endo-exo/images
```

## Распространение на заданные узлы

```bash
bash 4.Scripts/docker/distribute_images_slurm.sh \
  --archive /shared/software/endo-exo/images/endo-exo_3.0.0_COMMIT_images.tar.gz \
  --partition compute \
  --nodes compute-a01,compute-a02,compute-a03 \
  --max-parallel 1
```

## Автоматический выбор узлов

```bash
bash 4.Scripts/docker/distribute_images_slurm.sh \
  --archive /shared/software/endo-exo/images/endo-exo_3.0.0_COMMIT_images.tar.gz \
  --partition compute \
  --available-nodes \
  --max-parallel 1
```

`--max-parallel 1` уменьшает одновременную нагрузку на общую файловую систему.

## Пропускаемые состояния

```text
DOWN
DRAIN
FAIL
MAINT
REBOOT
POWER
UNKNOWN
```

Недоступные узлы отмечаются как:

```text
SKIPPED_STATE
```

После восстановления узла команду можно запустить повторно.

Узлы с уже совпадающими образами получают:

```text
SKIP_ALREADY_MATCHING
```

## Коды завершения

| Код | Значение |
|---:|---|
| `0` | Все доступные выбранные узлы успешно проверены |
| `1` | Хотя бы один доступный узел завершился с ошибкой |
| `3` | Ошибок нет, но хотя бы один узел был пропущен |

Код `3` означает управляемое частичное выполнение.

## Журналы

```text
_Logs/image_distribution/<timestamp>/
```

Содержимое:

```text
selected_nodes.tsv
summary.tsv
<node>.out
<node>.err
<node>.rc
```

## Запуск анализа

```bash
bash 4.Scripts/endo-exo.sh run-slurm \
  --samples config/samples.example.csv \
  --run-name cohort_run \
  --threads 16 \
  --jobs 2 \
  --keep-heavy
```

Мониторинг:

```bash
bash 4.Scripts/endo-exo.sh monitor
```
