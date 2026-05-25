#!/bin/bash
set -e

DEST="$HOME/Library/Application Support/ll2lossy/ffmpeg"
mkdir -p "$(dirname "$DEST")"

echo "Ищем ffmpeg..."

for BREW_PREFIX in /opt/homebrew /usr/local; do
    if [ -x "$BREW_PREFIX/bin/ffmpeg" ]; then
        echo "Найден: $BREW_PREFIX/bin/ffmpeg"
        cp "$BREW_PREFIX/bin/ffmpeg" "$DEST"
        chmod +x "$DEST"
        echo "Установлен в: $DEST"
        echo "Готово. Теперь можно собирать и запускать приложение."
        exit 0
    fi
done

# Try which as last resort
if command -v ffmpeg &>/dev/null; then
    SRC=$(which ffmpeg)
    echo "Найден: $SRC"
    cp "$SRC" "$DEST"
    chmod +x "$DEST"
    echo "Установлен в: $DEST"
    exit 0
fi

echo ""
echo "ffmpeg не найден."
echo "Установите через Homebrew:"
echo ""
echo "  brew install ffmpeg"
echo ""
echo "Затем запустите ./setup.sh снова."
exit 1
