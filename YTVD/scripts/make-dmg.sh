#!/bin/bash
# Собирает готовый к раздаче образ YTVD.dmg.
# Запуск: ./scripts/make-dmg.sh [версия]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${1:-1.0}"
STAGE="$ROOT/.build/dmg"
DMG="$ROOT/dist/YTVD-$VERSION.dmg"

"$ROOT/scripts/make-app.sh" >/dev/null

echo "▸ Готовлю содержимое образа"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$ROOT/dist/YTVD.app" "$STAGE/YTVD.app"
ln -s /Applications "$STAGE/Программы"

cat > "$STAGE/Прочтите меня.txt" <<'TXT'
YTVD — виджет для скачивания видео с YouTube, Vimeo, Rutube и VK Видео

УСТАНОВКА

1. Перетащите YTVD в папку «Программы» (ярлык рядом).

2. Установите движок — без него приложение запустится, но качать не сможет.
   Откройте Терминал и выполните:

       brew install yt-dlp ffmpeg

   Если Homebrew ещё нет, поставьте его с https://brew.sh

3. Запустите YTVD из Launchpad или Spotlight (⌘ + пробел, «YTVD»).


ПЕРВЫЙ ЗАПУСК

Приложение подписано ad-hoc, без платной учётной записи Apple, поэтому macOS
при первом запуске скажет, что разработчик не проверен. Это ожидаемо.

Разрешить можно двумя способами:

  • Системные настройки → Конфиденциальность и безопасность → пролистать вниз
    до сообщения о YTVD → «Открыть всё равно».

  • Или одной командой в Терминале:

        xattr -dr com.apple.quarantine /Applications/YTVD.app


КАК ПОЛЬЗОВАТЬСЯ

Значка в Dock нет — приложение живёт иконкой в строке меню сверху.

  ⌥⌘D    показать или спрятать виджет из любой программы
  ⌘V     взять ссылку из буфера обмена и разобрать
  ↑ ↓    выбрать качество
  ⏎      скачать
  ⌘,     настройки
  ⎋      спрятать

Скопируйте ссылку на видео — виджет сам предложит её вставить.

Требуется macOS 14 или новее. Подходит и для Apple Silicon, и для Intel.
TXT

echo "▸ Собираю образ"
rm -f "$DMG"
mkdir -p "$ROOT/dist"
hdiutil create -volname "YTVD $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
    -quiet "$DMG"

rm -rf "$STAGE"
SIZE=$(du -h "$DMG" | cut -f1)
echo "✓ Готово: $DMG ($SIZE)"
