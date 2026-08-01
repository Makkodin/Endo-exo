# Управление Docker-образами

[Оглавление](README.md) · [Локальная установка](installation-local.md) · [Slurm](installation-slurm.md)

## Имена образов

Имена по умолчанию определяются в `4.Scripts/common/load_config.sh`:

```text
endo-exo/core:3.0.0
endo-exo/telescope:3.0.0
```

Тег не гарантирует идентичность содержимого. Для воспроизводимости используется полный Docker image ID.

## Сборка

```bash
bash 4.Scripts/docker/build_images.sh
```

Только core:

```bash
bash 4.Scripts/docker/build_images.sh --core-only
```

Только Telescope:

```bash
bash 4.Scripts/docker/build_images.sh --telescope-only
```

## Проверка

```bash
bash 4.Scripts/docker/verify_images.sh
```

Только image ID:

```bash
bash 4.Scripts/docker/verify_images.sh --ids-only
```

Проверка против манифеста:

```bash
bash 4.Scripts/docker/verify_images.sh \
  --manifest /shared/software/endo-exo/images/archive.manifest.env
```

## Экспорт

```bash
bash 4.Scripts/docker/export_images.sh
```

Каталог по умолчанию:

```text
3.Refs/container_images/
```

Другой каталог:

```bash
bash 4.Scripts/docker/export_images.sh \
  --output-dir /shared/software/endo-exo/images
```

Создаются:

```text
endo-exo_<version>_<commit>_images.tar.gz
endo-exo_<version>_<commit>_images.tar.gz.sha256
endo-exo_<version>_<commit>_images.manifest.env
```

Манифест перемещается последним и служит признаком завершённого экспорта.

## Манифест

Манифест содержит:

- версию формата;
- версию проекта;
- Git commit;
- имя узла;
- версию Docker daemon;
- имена и полные ID образов;
- размеры и даты создания;
- имя, размер и SHA-256 архива.

Скрипты читают манифест как текст и не выполняют его через `source`.

## Загрузка

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/archive.tar.gz
```

При несовпадающем существующем теге загрузка останавливается.

После осознанной проверки:

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/archive.tar.gz \
  --replace-tags
```

Скрипт не удаляет другие образы и не запускает Docker prune.

## Обновление

1. Получить новый commit.
2. Выполнить smoke test.
3. Собрать новые образы.
4. Проверить runtime.
5. Создать новый архив.
6. Распространить архив.
7. Сохранить предыдущий комплект до завершения регрессионного теста.

## Откат

```bash
bash 4.Scripts/docker/load_images.sh \
  --archive /shared/software/endo-exo/images/previous_images.tar.gz \
  --replace-tags
```

После отката:

```bash
bash 4.Scripts/docker/verify_images.sh \
  --manifest /shared/software/endo-exo/images/previous_images.manifest.env
```

## Запрещённые автоматические операции

Утилиты не выполняют:

```text
docker system prune
docker image prune
sudo
изменение Docker socket
изменение Slurm node state
```
