# Решение проблем

[Оглавление](README.md) · [Проверка](verification.md)

## Docker не найден

```bash
command -v docker
```

Обратитесь к администратору для установки или подключения Docker CLI.

## Нет доступа к Docker daemon

```bash
docker info
```

Не изменяйте самостоятельно права `/var/run/docker.sock` и не используйте `sudo`, если это не предусмотрено политикой системы.

## Образ отсутствует

```text
core_image_status=MISSING
telescope_image_status=MISSING
```

Соберите образы:

```bash
bash 4.Scripts/endo-exo.sh setup
```

или загрузите архив:

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/archive.tar.gz
```

## Image ID не совпадает

```text
core_image_status=MISMATCH
```

Одинаковый тег указывает на другое содержимое. Проверьте манифест и историю сборки.

## Ошибка SHA-256

Не выполняйте `docker load`. Архив повреждён или не соответствует манифесту.

## Недостаточно места

```bash
docker info --format '{{.DockerRootDir}}'
df -h /var/lib/docker
```

Endo-exo не выполняет автоматическую очистку Docker storage.

## Архив не виден на compute-узле

```bash
srun \
  --partition compute \
  --nodelist compute-a01 \
  --nodes 1 \
  --ntasks 1 \
  test -r /shared/software/endo-exo/images/archive.tar.gz
```

## Узел пропущен

```text
SKIPPED_STATE
distribution_final_status=PARTIAL
```

Проверьте:

```bash
sinfo -N -o "%N %T %E"
```

После восстановления повторите распространение.

## Код распространения равен 3

Это означает:

- доступные узлы завершились успешно;
- один или несколько узлов были пропущены.

Код `3` не означает повреждение установленных образов.

## `srun` был прерван

Проверьте:

```bash
squeue -u "$USER"
```

Затем изучите:

```text
_Logs/image_distribution/<timestamp>/<node>.out
_Logs/image_distribution/<timestamp>/<node>.err
```

Повторный запуск безопасен: совпадающие образы не загружаются заново.

## `sacct` недоступен

Используйте:

- `squeue`;
- `.out` и `.err`;
- per-node `.rc`;
- `summary.tsv`;
- pipeline status files;
- completion markers.

## Python отсутствует в PATH Telescope

Telescope wrapper запускает Python по абсолютному пути. Значимы успешные проверки:

```text
telescope --help
telescope assign -h
telescope_runtime_status=OK
```
