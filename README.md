# IceAndFlame-Updates

Публичный репозиторий обновлений **ICE AND FLAME**.

## Каналы

- `manifest.json` — Stable.
- `manifest-beta.json` — Beta.
- `manifest-dev.json` — Dev.

Все манифесты используют schema 3. Патчер и русификатор имеют независимые версии.

## Публикация русификатора

Положите в `package\`:

```text
~RU_PATCH_1_P.pak
~RU_QFONT.pak
```

Допускаются имена без тильды.

Stable:

```bat
RELEASE_TRANSLATION.cmd 0.0.2
```

Beta:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -Channel beta
```

Dev:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -Channel dev
```

Минимальная версия патчера:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -MinPatcherVersion 0.0.7
```

Совместимость с версией игры:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -MinGameBuild "1.2.0" -MaxGameBuild "1.2.99"
```

Чтобы блокировать установку, если build игры определить не удалось:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -BlockUnknownGameBuild
```

Release Notes:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -ReleaseNotes "Исправлены строки интерфейса и квестов."
```

или `package\RELEASE_NOTES.txt`.

Зеркала:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -PatchMirrorUrl "https://mirror.example/RU_PATCH_1_P.pak" -FontMirrorUrl "https://mirror.example/RU_QFONT.pak"
```

Повторная намеренная публикация:

```bat
RELEASE_TRANSLATION.cmd 0.0.2 -Force
```

## Что делает RELEASE_TRANSLATION

Скрипт:

- проверяет GitHub CLI и авторизацию;
- читает нужный Stable/Beta/Dev manifest;
- валидирует номер версии;
- находит оба `.pak`;
- считает SHA-256;
- создаёт GitHub Release и загружает assets;
- обновляет URL, mirrors, hashes, Release Notes, `minPatcherVersion` и диапазон game build;
- при наличии RSA-ключей подписывает manifest;
- проверяет опубликованный manifest.

Beta и Dev releases создаются как prerelease.

## Подпись manifest

Поддерживаются переменные окружения:

```text
MANIFEST_SIGNING_PRIVATE_KEY_PEM
MANIFEST_SIGNING_PUBLIC_KEY_PEM
```

Если оба ключа заданы, manifest получает `signatureRequired=true` и рядом публикуется файл:

```text
manifest.json.sig
manifest-beta.json.sig
manifest-dev.json.sig
```

Приватный ключ в Git не хранится.

## Schema 3

Основные серверные механизмы:

- `patcher.rolloutPercent` — постепенная выдача обновления;
- `patcher.blockedVersions` — kill switch старых/проблемных патчеров;
- `translation.game` — диапазон совместимых game builds;
- `security` — параметры RSA-подписи;
- `support.diagnosticsUploadUrl` — необязательный endpoint приёма диагностики;
- `support.statusUrl` — резерв для отдельного status endpoint;
- `urls` — резервные зеркала файлов.

## Автоматическая проверка репозитория

GitHub Actions проверяет:

- синтаксис `RELEASE_TRANSLATION.ps1`;
- сборку `tools/ManifestSigner`;
- все три manifest-файла;
- обязательные поля schema 3.

## Требования

Нужен GitHub CLI:

```bat
gh auth login
gh auth status
```
