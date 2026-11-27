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
TRIPLES=(arm64-apple-macosx14.0 x86_64-apple-macosx14.0)

# Build each architecture with the native build system, then merge with lipo.
# (The multi-arch "--arch a --arch b" path does not accept per-target Swift language modes.)
BINARIES=()
for triple in "${TRIPLES[@]}"; do
  echo "==> Building release binary for $triple"
  swift build -c release --product MacStats --triple "$triple"
  BINARIES+=("$(swift build -c release --product MacStats --triple "$triple" --show-bin-path)/MacStats")
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/MacStats" "${BINARIES[@]}"
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
