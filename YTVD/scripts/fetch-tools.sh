#!/bin/bash
# Скачивает движок (yt-dlp, deno, ffmpeg) для укладки внутрь приложения.
# Запуск: ./scripts/fetch-tools.sh <каталог-назначения> [arm64|x86_64]
#
# Загруженное кэшируется в .build/tools-cache, повторные сборки идут без сети.
set -euo pipefail

cd "$(dirname "$0")/.."
DEST="${1:?укажите каталог назначения}"
ARCH="${2:-$(uname -m)}"
CACHE="$PWD/.build/tools-cache/$ARCH"

case "$ARCH" in
  arm64|aarch64)
    ARCH=arm64
    DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip"
    # У osxexperts адрес привязан к версии — при обновлении ffmpeg поправить здесь.
    FFMPEG_URL="https://www.osxexperts.net/ffmpeg81arm.zip"
    ;;
  x86_64)
    DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-apple-darwin.zip"
    FFMPEG_URL="https://evermeet.cx/ffmpeg/getrelease/zip"
    ;;
  *) echo "неизвестная архитектура: $ARCH" >&2; exit 1 ;;
esac

# yt-dlp собран универсальным — годится обеим архитектурам. Берём распакованную сборку
# (onedir), а не однофайловую: та при каждом запуске заново распаковывает Python во
# временную папку, и macOS заново проверяет его библиотеки — 6–8 секунд на любой вызов.
# Распакованная проверяется один раз, дальше запускается за доли секунды.
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip"

mkdir -p "$CACHE" "$DEST"

# Скачивает файл в кэш, если его там ещё нет.
fetch() {
  local url="$1" file="$2"
  if [[ -s "$CACHE/$file" ]]; then
    echo "  из кэша: $file"
    return
  fi
  echo "  качаю: $file"
  curl -fL --retry 3 --max-time 600 --progress-bar -o "$CACHE/$file.part" "$url"
  mv "$CACHE/$file.part" "$CACHE/$file"
}

# Достаёт один исполняемый файл из zip-архива.
unpack() {
  local archive="$1" name="$2"
  rm -rf "$CACHE/unpack-$name"
  mkdir -p "$CACHE/unpack-$name"
  unzip -qo "$CACHE/$archive" -d "$CACHE/unpack-$name"
  local found
  found=$(find "$CACHE/unpack-$name" -type f -name "$name" -perm +111 | head -1)
  [[ -n "$found" ]] || { echo "в $archive нет $name" >&2; exit 1; }
  cp "$found" "$DEST/$name"
}

echo "▸ Движок для $ARCH"
fetch "$YTDLP_URL" "yt-dlp_macos.zip"
fetch "$DENO_URL" "deno.zip"
fetch "$FFMPEG_URL" "ffmpeg.zip"

# yt-dlp — папка целиком (исполняемый файл и _internal рядом), а bin/yt-dlp — ссылка на него:
# приложение по-прежнему ищет bin/yt-dlp. ditto сохраняет ссылки внутри Python.framework.
rm -rf "$DEST/yt-dlp_macos" "$DEST/yt-dlp"
ditto -x -k "$CACHE/yt-dlp_macos.zip" "$DEST/yt-dlp_macos"
[[ -x "$DEST/yt-dlp_macos/yt-dlp_macos" ]] || { echo "в yt-dlp_macos.zip нет yt-dlp_macos" >&2; exit 1; }
ln -s yt-dlp_macos/yt-dlp_macos "$DEST/yt-dlp"
unpack "deno.zip" "deno"
unpack "ffmpeg.zip" "ffmpeg"
chmod +x "$DEST"/{deno,ffmpeg}

# Скачанное из интернета помечено карантином — снимаем, иначе macOS не даст запустить.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "▸ Проверка"
for tool in yt-dlp deno ffmpeg; do
  printf '  %-8s ' "$tool"
  case "$tool" in
    ffmpeg) "$DEST/$tool" -version 2>&1 | head -1 | cut -c1-40 ;;
    *)      "$DEST/$tool" --version 2>&1 | head -1 ;;
  esac
done

SIZE=$(du -sh "$DEST" | cut -f1)
echo "✓ Движок готов: $DEST ($SIZE)"
