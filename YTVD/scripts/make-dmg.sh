#!/bin/bash
# Собирает готовый к раздаче образ YTVD.dmg.
# Запуск: ./scripts/make-dmg.sh [версия]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${1:-1.2}"
STAGE="$ROOT/.build/dmg"
DMG="$ROOT/dist/YTVD-$VERSION.dmg"

YTVD_VERSION="$VERSION" "$ROOT/scripts/make-app.sh" --with-tools >/dev/null

echo "▸ Готовлю содержимое образа"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$ROOT/dist/YTVD.app" "$STAGE/YTVD.app"
ln -s /Applications "$STAGE/Программы"

cat > "$STAGE/Прочтите меня.txt" <<'TXT'
YTVD — виджет для скачивания видео с YouTube, Vimeo, Rutube и VK Видео

УСТАНОВКА

Перетащите YTVD в папку «Программы» (ярлык рядом) и запустите из Launchpad
или Spotlight (⌘ + пробел, «YTVD»).

Больше ничего ставить не нужно: движок (yt-dlp, ffmpeg, deno) уже внутри
приложения. Интернет нужен только для самих загрузок.


ЕСЛИ macOS ПИШЕТ, ЧТО РАЗРАБОТЧИК НЕ ПРОВЕРЕН

Приложение подписано без платной учётной записи Apple, поэтому при первом
запуске система его придержит. Снимается одной командой в Терминале:

    xattr -dr com.apple.quarantine /Applications/YTVD.app

Либо: «Системные настройки» → «Конфиденциальность и безопасность» →
пролистать вниз до сообщения о YTVD → «Открыть всё равно».


КАК ПОЛЬЗОВАТЬСЯ

Значка в Dock нет — приложение живёт иконкой в строке меню сверху.

  ⌥⌘D    показать или спрятать виджет из любой программы
  ⌘V     взять ссылку из буфера обмена и разобрать
  ↑ ↓    выбрать качество
  ⏎      скачать
  ⌘,     настройки
  ⎋      спрятать

Скопируйте ссылку на видео — виджет сам предложит её вставить.

Если площадка сломает движок, приложение это заметит и предложит обновиться.

Требуется macOS 14 или новее.
TXT

echo "▸ Собираю образ"
rm -f "$DMG"
mkdir -p "$ROOT/dist"
hdiutil create -volname "YTVD $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
    -quiet "$DMG"

rm -rf "$STAGE"
SIZE=$(du -h "$DMG" | cut -f1)
echo "✓ Готово: $DMG ($SIZE)"
