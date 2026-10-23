#!/bin/bash
# Builds "Ambient Control.app" with the webOS TV app bundled inside it.
# Usage: ./build-app.sh            (output: build/Ambient Control.app)
#        ./build-app.sh --install  (also copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")"

TV_DIR="$(cd ../webos-screensaver && pwd)"
APP="build/Ambient Control.app"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "▸ Compiling (release)…"
swift build -c release 2>&1 | grep -v "ld: warning: search path" || true
BIN="$(swift build -c release --show-bin-path)/AmbientControl"
[ -x "$BIN" ] || { echo "Build failed"; exit 1; }

echo "▸ Packaging TV app…"
rm -f build/*.ipk
mkdir -p build
ares-package "$TV_DIR" -o build -e server -e README.md > /dev/null

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/tv"
cp "$BIN" "$APP/Contents/MacOS/AmbientControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
rsync -a --exclude server --exclude README.md --exclude '.*' "$TV_DIR/" "$APP/Contents/Resources/tv/"
cp build/*.ipk "$APP/Contents/Resources/"

echo "▸ Signing (AmbientControl Dev)…"
# Stable identity so the Screen Recording permission survives rebuilds
codesign --force --deep --sign "AmbientControl Dev" "$APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Ambient Control.app"
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/Ambient Control.app"
else
  echo "✓ Built $APP"
fi
