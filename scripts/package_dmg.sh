#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="VoltGuard.app"
APP_DIR="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/VoltGuard.dmg"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

cd "$ROOT_DIR"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
MAIN_BIN="$BIN_DIR/VoltGuard"
HELPER_BIN="$BIN_DIR/voltguard-helper"

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Helpers" "$APP_DIR/Contents/Resources"

cp "$MAIN_BIN" "$APP_DIR/Contents/MacOS/VoltGuard"
cp "$HELPER_BIN" "$APP_DIR/Contents/Helpers/voltguard-helper"
chmod +x "$APP_DIR/Contents/MacOS/VoltGuard" "$APP_DIR/Contents/Helpers/voltguard-helper"

ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VoltGuard</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.voltguard.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VoltGuard</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSMultipleInstancesProhibited</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

DMG_STAGE="$DIST_DIR/dmg_stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create -volname "VoltGuard" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGE"

if [ -d "$ICLOUD_DIR" ]; then
    cp "$DMG_PATH" "$ICLOUD_DIR/VoltGuard.dmg"
    echo "Uploaded to iCloud Drive: $ICLOUD_DIR/VoltGuard.dmg"
fi

rm -rf "/Applications/$APP_NAME"
cp -R "$APP_DIR" "/Applications/$APP_NAME"
echo "Installed to /Applications/$APP_NAME"
