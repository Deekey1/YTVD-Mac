#!/bin/bash
# Собирает YTVD.app из пакета SwiftPM.
# Запуск: ./scripts/make-app.sh [--install]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/.build"
APP="$ROOT/dist/YTVD.app"
VERSION="1.0"

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

echo "▸ Бандл"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/YTVD"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
</dict>
</plist>
PLIST

cat > "$APP/Contents/PkgInfo" <<< "APPL????"

echo "▸ Подпись (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "  предупреждение: подписать не удалось, приложение всё равно запустится локально"

SIZE=$(du -sh "$APP" | cut -f1)
echo "✓ Готово: $APP ($SIZE)"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Копирую в /Applications"
  rm -rf "/Applications/YTVD.app"
  cp -R "$APP" "/Applications/YTVD.app"
  # Если исходники приехали архивом из интернета, на файлах висит карантин —
  # без этого macOS откажется запускать приложение.
  xattr -dr com.apple.quarantine "/Applications/YTVD.app" 2>/dev/null || true
  echo "✓ /Applications/YTVD.app"
fi
