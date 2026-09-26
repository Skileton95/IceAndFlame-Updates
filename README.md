# IceAndFlame-Updates

Публичный репозиторий обновлений для **ICE AND FLAME — русификатора World of Jade Dynasty**.

Здесь хранятся:

- `manifest.json` — единый манифест патчера и русификатора;
- `RELEASE_TRANSLATION.cmd` / `RELEASE_TRANSLATION.ps1` — публикация русификатора из локальной папки `package`;
- GitHub Releases — готовые версии патчера и русификатора.

## Публикация новой версии русификатора

1. Обновите локальный репозиторий `IceAndFlame-Updates`.
2. Положите актуальные файлы в папку `package`:

```text
package\~RU_PATCH_1_P.pak
package\~RU_QFONT.pak
```

Допускаются также имена без тильды:

```text
package\RU_PATCH_1_P.pak
package\RU_QFONT.pak
```

3. Запустите:

```text
RELEASE_TRANSLATION.cmd
```

4. Введите новую версию, например:

```text
0.0.1
```

Можно передать версию сразу:

```text
RELEASE_TRANSLATION.cmd 0.0.1
```

Скрипт:

- проверит авторизацию GitHub CLI;
- прочитает актуальный `manifest.json` прямо с GitHub;
- проверит структуру секции `translation`;
- найдёт оба `.pak`;
- посчитает SHA-256;
- создаст Release `translation-X.Y.Z`;
- загрузит `RU_PATCH_1_P.pak` и `RU_QFONT.pak`;
- проверит наличие обоих файлов в Release;
- обновит только секцию `translation` в `manifest.json`;
- проверит публичный `manifest.json` после публикации.

Секция `patcher` при выпуске русификатора не изменяется.

## Повторная публикация той же версии

Обычный запуск не даст случайно перезаписать уже существующую версию.

Если повторная публикация действительно нужна:

```text
RELEASE_TRANSLATION.cmd 0.0.1 -Force
```

Это перезапишет assets существующего Release и заново обновит SHA-256 в манифесте.

## Требования

Нужен GitHub CLI `gh` с выполненной авторизацией:

```text
gh auth login
```

Проверить:

```text
gh auth status
```

## Важно

Файлы из `package\` не добавляются в Git. Они используются только как локальный источник для создания Release.
