#!/bin/bash
# Собирает YTVD.app из пакета SwiftPM.
# Запуск: ./scripts/make-app.sh [--install]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/.build"
APP="$ROOT/dist/YTVD.app"
VERSION="${YTVD_VERSION:-1.3.2}"

echo "▸ Сборка релиза"
# Универсальный бинарник: пойдёт и на Apple Silicon, и на Intel.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BINARY="$BUILD/apple/Products/Release/YTVD"
else
  echo "  (универсальная сборка недоступна — собираю только под эту машину)"
  swift build -c release
  BINARY="$(swift build -c release --show-bin-path)/YTVD"
fi

echo "▸ Иконка"
swift "$ROOT/scripts/make-icon.swift" "$BUILD" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

if [[ " $* " == *" --with-tools "* ]]; then
  echo "▸ Движок внутрь приложения"
  "$ROOT/scripts/fetch-tools.sh" "$BUILD/bin" >/dev/null
fi

echo "▸ Бандл"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/YTVD"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Приложение ищет движок здесь в первую очередь — см. BinaryLocator.bundledDirectory.
if [[ -d "$BUILD/bin" ]]; then
  # ditto, а не cp: yt-dlp — папка со ссылкой bin/yt-dlp на исполняемый файл внутри.
  # cp без -R папку пропустил бы, а ссылку превратил бы в копию, которой не найти _internal.
  ditto "$BUILD/bin" "$APP/Contents/Resources/bin"
  find "$APP/Contents/Resources/bin" -maxdepth 1 -type f -exec chmod +x {} +
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>YTVD</string>
    <key>CFBundleDisplayName</key>       <string>YTVD</string>
    <key>CFBundleExecutable</key>        <string>YTVD</string>
    <key>CFBundleIdentifier</key>        <string>studio.dk.ytvd</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSHumanReadableCopyright</key>  <string>Иконки: Obra Icons (MIT)</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Сервер для iPhone: приложение на iPhone находит этот Mac в домашней сети и забирает с него скачанные видео.</string>
    <key>NSBonjourServices</key>
    <array><string>_ytvd._tcp</string></array>
</dict>
</plist>
PLIST

cat > "$APP/Contents/PkgInfo" <<< "APPL????"

echo "▸ Подпись (ad-hoc)"
# Вложенные исполняемые файлы подписываем раньше самого бандла. Ссылки пропускаем:
# сборка yt-dlp уже подписана целиком, и переподписывать её по одному файлу незачем.
for tool in "$APP/Contents/Resources/bin/"*; do
  [[ -f "$tool" && ! -L "$tool" ]] && codesign --force --sign - --timestamp=none "$tool" >/dev/null 2>&1 || true
done
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "  предупреждение: подписать не удалось, приложение всё равно запустится локально"

SIZE=$(du -sh "$APP" | cut -f1)
echo "✓ Готово: $APP ($SIZE)"

if [[ " $* " == *" --install "* ]]; then
  echo "▸ Копирую в /Applications"
  rm -rf "/Applications/YTVD.app"
  cp -R "$APP" "/Applications/YTVD.app"
  # Если исходники приехали архивом из интернета, на файлах висит карантин —
  # без этого macOS откажется запускать приложение.
  xattr -dr com.apple.quarantine "/Applications/YTVD.app" 2>/dev/null || true
  echo "✓ /Applications/YTVD.app"
fi
