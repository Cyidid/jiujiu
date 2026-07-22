#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/啾啾.app"
BUILD_APP_DIR="$ROOT_DIR/build/啾啾.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_FILE="$ROOT_DIR/Sources/Jiujiu/main.swift"

mkdir -p "$ROOT_DIR/build"
if [ -d "$BUILD_APP_DIR" ]; then
  mv "$BUILD_APP_DIR" "$ROOT_DIR/build/啾啾.app.old.$$"
fi

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
cp "$ROOT_DIR/additional/Applications/啾啾.app/Contents/Resources/"*.png "$RESOURCES_DIR/"
cp "$ROOT_DIR/additional/Applications/啾啾.app/Contents/Resources/AppIcon.icns" "$RESOURCES_DIR/"

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
  <string>2.0</string>
  <key>CFBundleVersion</key>
  <string>22</string>
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

xattr -cr "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
if [ -d "$ROOT_DIR/啾啾.app" ]; then
  mv "$ROOT_DIR/啾啾.app" "$ROOT_DIR/build/啾啾.app.previous.$$"
fi
mv "$APP_DIR" "$ROOT_DIR/啾啾.app"
echo "Built $APP_DIR"
