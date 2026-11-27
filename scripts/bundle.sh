#!/usr/bin/env bash
# Build layer: builds a universal release binary and wraps it into "Mac Stats.app".
# Usage: scripts/bundle.sh <version>     (BUILD_NUMBER env var sets CFBundleVersion; default 1)
# Output: build/Mac Stats.app and build/MacStats-<version>.zip
set -euo pipefail

VERSION="${1:?usage: scripts/bundle.sh <version>}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Mac Stats"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "==> Building universal release binary"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacStats" "$APP/Contents/MacOS/MacStats"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" scripts/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/MacStats"

echo "==> Ad-hoc signing (no Developer ID yet; see docs/kb/stack.md D4)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping"
rm -f "$BUILD_DIR/MacStats-$VERSION.zip"
(cd "$BUILD_DIR" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "MacStats-$VERSION.zip")
ls -l "$BUILD_DIR"
