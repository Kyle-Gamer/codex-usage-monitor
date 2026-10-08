#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

UNIVERSAL=false
SIGNING_IDENTITY=""
for argument in "$@"; do
    case "$argument" in
        --universal) UNIVERSAL=true ;;
        --developer-id=*) SIGNING_IDENTITY="${argument#--developer-id=}" ;;
        --help|-h)
            cat <<'USAGE'
Usage: ./Scripts/package_app.sh [--universal] [--developer-id="Developer ID Application: ..."]

Default: build an arm64 ZIP with an ad-hoc signature for personal/manual use.
--universal: build arm64 + x86_64 and combine them with lipo.
--developer-id: sign with a Developer ID Application identity instead of ad-hoc signing.
USAGE
            exit 0
            ;;
        *) print -u2 "Unknown option: $argument"; exit 2 ;;
    esac
done

swift run -c debug CodexUsageMonitorTests

BUILD_DIR="$PROJECT_DIR/Build"
DIST_DIR="$PROJECT_DIR/Dist"
APP_PATH="$BUILD_DIR/Codex Usage Monitor.app"
CONTENTS="$APP_PATH/Contents"
EXECUTABLE="$CONTENTS/MacOS/CodexUsageMonitor"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$DIST_DIR"

if $UNIVERSAL; then
    swift build -c release --triple arm64-apple-macosx13.0 --product CodexUsageMonitor
    swift build -c release --triple x86_64-apple-macosx13.0 --product CodexUsageMonitor
    ARM64_BIN="$PROJECT_DIR/.build/arm64-apple-macosx/release/CodexUsageMonitor"
    X86_BIN="$PROJECT_DIR/.build/x86_64-apple-macosx/release/CodexUsageMonitor"
    lipo -create "$ARM64_BIN" "$X86_BIN" -output "$EXECUTABLE"
    ARCH_LABEL="universal"
else
    swift build -c release --product CodexUsageMonitor
    BIN_DIR="$(swift build -c release --show-bin-path)"
    cp "$BIN_DIR/CodexUsageMonitor" "$EXECUTABLE"
    ARCH_LABEL="arm64"
fi

cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
chmod +x "$EXECUTABLE"
# Finder metadata can be inherited when the build directory is viewed in Finder;
# remove it before signing so codesign sees a clean bundle.
xattr -cr "$APP_PATH" 2>/dev/null || true

if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
    SIGNATURE_LABEL="developer-id"
else
    codesign --force --deep --sign - --timestamp=none "$APP_PATH"
    SIGNATURE_LABEL="adhoc"
fi
xattr -cr "$APP_PATH" 2>/dev/null || true
codesign --verify --deep --strict "$APP_PATH"

ZIP_PATH="$DIST_DIR/Codex Usage Monitor-${VERSION}-${ARCH_LABEL}-${SIGNATURE_LABEL}.zip"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "Package: $ZIP_PATH"
echo "SHA-256: $(awk '{print $1}' "$ZIP_PATH.sha256")"
echo "Architectures: $(lipo -archs "$EXECUTABLE")"
