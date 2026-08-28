#!/bin/bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIGURATION" --product PackingMonitor
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
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
echo "Run:   open '$APP_DIR'"
echo "Web:   http://127.0.0.1:8787"
