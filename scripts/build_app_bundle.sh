#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Mneme"
BUNDLE_ID="local.mneme.app"
CONFIGURATION="${CONFIGURATION:-release}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_PATH="$(cd "$REPO_ROOT" && swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="${1:-"$REPO_ROOT/.build/$APP_NAME.app"}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$REPO_ROOT/Assets/AppIcon/Mneme.icns"

cd "$REPO_ROOT"
swift build -c "$CONFIGURATION" --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"

find "$BIN_PATH" -maxdepth 1 -name "*.bundle" -type d -exec cp -R {} "$RESOURCES_DIR" \;

if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/Mneme.icns"
fi

if [ -d "$REPO_ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal" ]; then
    "$SCRIPT_DIR/build_mlx_metallib.sh" "$MACOS_DIR/mlx.metallib" >/dev/null
fi

MODEL_SOURCE="$REPO_ROOT/.build/Models/e5"
if [ -d "$MODEL_SOURCE" ]; then
    mkdir -p "$RESOURCES_DIR/Models"
    cp -R "$MODEL_SOURCE" "$RESOURCES_DIR/Models/e5"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>Mneme</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    if [ -f "$MACOS_DIR/mlx.metallib" ]; then
        codesign --force --sign - "$MACOS_DIR/mlx.metallib" >/dev/null
    fi
    codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
