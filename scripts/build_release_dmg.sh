#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Mneme"
VERSION="${VERSION:-0.1.0}"
ARCHIVE_NAME="${APP_NAME}-v${VERSION}-macos-arm64.dmg"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/.build/${APP_NAME}.app"
OUTPUT_PATH="${1:-"$REPO_ROOT/.build/$ARCHIVE_NAME"}"

mkdir -p "$REPO_ROOT/.build"
"$SCRIPT_DIR/build_app_bundle.sh" "$APP_DIR" >/dev/null

STAGING_DIR="$(mktemp -d "$REPO_ROOT/.build/${APP_NAME}-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$OUTPUT_PATH"
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$OUTPUT_PATH" >/dev/null

echo "$OUTPUT_PATH"
