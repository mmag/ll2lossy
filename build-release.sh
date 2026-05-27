#!/bin/bash
set -e

VERSION="0.1"
APP_NAME="LosslessToMP3"
BINARY_NAME="ll2lossy"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"

echo "==> Building $APP_NAME $VERSION..."
swift build -c release --arch arm64

echo "==> Creating .app bundle..."
rm -rf "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$BINARY_NAME" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp "Sources/$BINARY_NAME/Resources/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Verifying..."
codesign --verify --deep "$APP_BUNDLE"

echo "==> Zipping..."
ZIP_NAME="$APP_NAME.app.zip"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

echo "==> SHA256:"
SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
echo "$SHA"
echo ""
echo "Done: $ZIP_NAME  (sha256: $SHA)"
