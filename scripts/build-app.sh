#!/bin/bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ARCH="${PACKING_MONITOR_ARCH:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_ARGS=(-c "$CONFIGURATION")
if [[ -n "$ARCH" ]]; then
  BUILD_ARGS+=(--arch "$ARCH")
fi

swift build "${BUILD_ARGS[@]}" --product PackingMonitor
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$ROOT/.build/app/PackingMonitor.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/PackingMonitor" "$CONTENTS/MacOS/PackingMonitor"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/PackingMonitor"

plutil -lint "$CONTENTS/Info.plist"

# Ad-hoc signing gives the development bundle a stable macOS code identity.
# A Developer ID signature/notarization can replace this for distribution.
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Built: $APP_DIR"
if [[ -n "$ARCH" ]]; then
  echo "Arch:  $ARCH"
fi
echo "Run:   open '$APP_DIR'"
echo "Web:   http://127.0.0.1:8787"
