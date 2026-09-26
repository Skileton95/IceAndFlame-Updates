# IceAndFlame-Updates

Публичный репозиторий обновлений **ICE AND FLAME**.

## Каналы

- `manifest.json` — Stable.
- `manifest-beta.json` — Beta.

Патчер и русификатор имеют независимые версии.

## Публикация русификатора

Положите в `package\`:

```text
~RU_PATCH_1_P.pak
~RU_QFONT.pak
```

Допускаются имена без тильды:

```text
RU_PATCH_1_P.pak
RU_QFONT.pak
```

Stable:

```bat
RELEASE_TRANSLATION.cmd 0.0.2
```

Beta:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -Channel beta
```

С минимальной версией патчера:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -MinPatcherVersion 0.0.6
```

Release Notes можно передать параметром:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -ReleaseNotes "Исправлены строки интерфейса и квестов."
```

или положить текст в:

```text
package\RELEASE_NOTES.txt
```

Повторная публикация существующей версии:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -Force
```

Скрипт сам:

- проверит GitHub CLI;
- прочитает актуальный Stable/Beta манифест;
- найдёт оба `.pak`;
- посчитает SHA-256;
- создаст соответствующий GitHub Release;
- загрузит файлы;
- обновит только секцию `translation`;
- запишет Release Notes и `minPatcherVersion`;
- проверит публичный манифест.

Файлы из `package\` в Git не добавляются.

## Зеркала

Каждый файл поддерживает массив `urls`. Первый `url` остаётся основным, дополнительные адреса можно добавить в `urls`. Патчер автоматически повторяет загрузку и переключается на следующий адрес при ошибке.

## Требования

Нужен GitHub CLI:

```bat
gh auth login
gh auth status
```
