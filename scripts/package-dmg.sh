#!/usr/bin/env bash
# Build Release and produce release/mcp-aha-<version>-macOS-<arch>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
if [[ ! -x "${DEVELOPER_DIR}/usr/bin/xcodebuild" ]]; then
  echo "Set DEVELOPER_DIR to your Xcode.app Contents/Developer" >&2
  exit 1
fi

VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
ARCH=$(uname -m)
DMG_NAME="mcp-aha-${VER}-macOS-${ARCH}.dmg"
DERIVED="$ROOT/build/DerivedDataRelease"
APP="$DERIVED/Build/Products/Release/mcp-aha.app"
STAGE="$ROOT/release/.dmg-staging"

echo "==> XcodeGen + Release build"
command -v xcodegen >/dev/null 2>&1 && xcodegen generate
set +e
if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild -project mcp-aha.xcodeproj -scheme mcp-aha -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    build 2>&1 | xcbeautify
  XC=${PIPESTATUS[0]}
else
  xcodebuild -project mcp-aha.xcodeproj -scheme mcp-aha -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    build
  XC=$?
fi
set -e
[[ $XC -eq 0 ]] || exit $XC

[[ -d "$APP" ]] || { echo "Missing: $APP" >&2; exit 1; }

echo "==> Assemble DMG: release/$DMG_NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$ROOT/release"
ditto "$APP" "$STAGE/mcp-aha.app"
ln -sf /Applications "$STAGE/Applications"
rm -f "$ROOT/release/$DMG_NAME"
hdiutil create -volname "mcp-aha ${VER}" -srcfolder "$STAGE" -ov -format UDZO \
  -imagekey zlib-level=9 "$ROOT/release/$DMG_NAME"
rm -rf "$STAGE"

echo "Done: $ROOT/release/$DMG_NAME"
shasum -a 256 "$ROOT/release/$DMG_NAME"
