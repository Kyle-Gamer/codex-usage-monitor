#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

CONFIGURATION="release"
INSTALL=false
if [[ "${1:-}" == "--install" ]]; then
    INSTALL=true
fi

swift run -c debug CodexUsageMonitorTests
swift build -c "$CONFIGURATION" --product CodexUsageMonitor
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUILD_DIR="$PROJECT_DIR/Build"
APP_PATH="$BUILD_DIR/Codex Usage Monitor.app"
CONTENTS="$APP_PATH/Contents"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/CodexUsageMonitor" "$CONTENTS/MacOS/CodexUsageMonitor"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
chmod +x "$CONTENTS/MacOS/CodexUsageMonitor"
# Finder/File Provider metadata can invalidate a local ad-hoc signature.
xattr -cr "$APP_PATH" 2>/dev/null || true

codesign --force --deep --sign - --timestamp=none "$APP_PATH"
# The workspace may reattach Finder/File Provider metadata during signing.
# Strip it once more so verification sees a clean bundle.
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --verify --deep --strict "$APP_PATH"

echo "Built: $APP_PATH"
echo "Signature: $(codesign -dv --verbose=2 "$APP_PATH" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')"

if $INSTALL; then
    INSTALL_DIR="$HOME/Applications"
    INSTALL_PATH="$INSTALL_DIR/Codex Usage Monitor.app"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_PATH"
    ditto "$APP_PATH" "$INSTALL_PATH"
    echo "Installed: $INSTALL_PATH"
fi
