#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APP_DIR="$ROOT_DIR/啾啾.app"
BUILD_ROOT="${TMPDIR:-/tmp}/jiujiu-build.$$"
BUILD_APP_DIR="$BUILD_ROOT/啾啾.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_FILE="$ROOT_DIR/Sources/Jiujiu/main.swift"

mkdir -p "$BUILD_ROOT" "$ROOT_DIR/build"

clean_app_metadata() {
  local target="$1"
  xattr -cr "$target" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "$target" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$target" 2>/dev/null || true
  xattr -rd com.apple.FinderInfo "$target" 2>/dev/null || true
  xattr -rd 'com.apple.fileprovider.fpfs#P' "$target" 2>/dev/null || true
  xattr -rd com.apple.ResourceFork "$target" 2>/dev/null || true
  xattr -rd com.apple.provenance "$target" 2>/dev/null || true
}

APP_DIR="$BUILD_APP_DIR"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc "$SOURCE_FILE" \
  -framework Cocoa \
  -framework QuartzCore \
  -framework UserNotifications \
  -o "$MACOS_DIR/jiujiu"

find "$RESOURCES_DIR" -type f -name '*.png' -delete
find "$RESOURCES_DIR" -type f -name '*.icns' -delete
for sprite in "$ROOT_DIR/additional/Applications/啾啾.app/Contents/Resources/"*.png; do
  COPYFILE_DISABLE=1 ditto --norsrc "$sprite" "$RESOURCES_DIR/$(basename "$sprite")"
done
COPYFILE_DISABLE=1 ditto --norsrc \
  "$ROOT_DIR/additional/Applications/啾啾.app/Contents/Resources/AppIcon.icns" \
  "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>啾啾</string>
  <key>CFBundleExecutable</key>
  <string>jiujiu</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.jiujiu.catpet21</string>
  <key>CFBundleName</key>
  <string>啾啾</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>2.8</string>
  <key>CFBundleVersion</key>
  <string>30</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

clean_app_metadata "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

if [ -d "$ROOT_DIR/啾啾.app" ]; then
  mv "$ROOT_DIR/啾啾.app" "$ROOT_DIR/build/啾啾.app.previous.$$"
fi
COPYFILE_DISABLE=1 ditto --norsrc "$APP_DIR" "$ROOT_DIR/啾啾.app"

APP_DIR="$ROOT_DIR/啾啾.app"
clean_app_metadata "$APP_DIR"
echo "Built $APP_DIR"
rm -rf "$BUILD_ROOT"
