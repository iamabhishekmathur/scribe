#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
APP_NAME="Scribe"
BUNDLE_ID="com.scribe.app"
VERSION="0.1.0"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING_DIR=".build/dmg-staging"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_DIR"

echo "==> Building ${APP_NAME} v${VERSION} (release)..."
swift build -c release 2>&1 | tail -5

BINARY="${BUILD_DIR}/Scribe"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at ${BINARY}"
    exit 1
fi
echo "==> Binary built: $(du -h "$BINARY" | cut -f1)"

# ─── Create .app bundle ─────────────────────────────────────────
echo "==> Creating ${APP_BUNDLE}..."
rm -rf "${BUILD_DIR}/${APP_BUNDLE}"

CONTENTS="${BUILD_DIR}/${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BINARY" "${MACOS}/${APP_NAME}"
chmod +x "${MACOS}/${APP_NAME}"

# Copy Info.plist
cp "ScribeApp/Info.plist" "${CONTENTS}/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "${CONTENTS}/PkgInfo"

# Create .icns from PNG icons
echo "==> Creating app icon..."
ICONSET_DIR=".build/Scribe.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# macOS iconset requires specific filenames
ICON_SRC="ScribeApp/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "${ICON_SRC}/icon_1024.png" ]; then
    cp "${ICON_SRC}/icon_1024.png" "${ICONSET_DIR}/icon_512x512@2x.png"
fi
if [ -f "${ICON_SRC}/icon_512.png" ]; then
    cp "${ICON_SRC}/icon_512.png" "${ICONSET_DIR}/icon_512x512.png"
    cp "${ICON_SRC}/icon_512.png" "${ICONSET_DIR}/icon_256x256@2x.png"
fi
if [ -f "${ICON_SRC}/icon_256.png" ]; then
    cp "${ICON_SRC}/icon_256.png" "${ICONSET_DIR}/icon_256x256.png"
    cp "${ICON_SRC}/icon_256.png" "${ICONSET_DIR}/icon_128x128@2x.png"
fi
if [ -f "${ICON_SRC}/icon_128.png" ]; then
    cp "${ICON_SRC}/icon_128.png" "${ICONSET_DIR}/icon_128x128.png"
fi

# Generate .icns
iconutil -c icns "$ICONSET_DIR" -o "${RESOURCES}/AppIcon.icns" 2>/dev/null || {
    echo "    (iconutil failed — .app will use default icon)"
}

# Add icon reference to Info.plist if not present
if ! grep -q "CFBundleIconFile" "${CONTENTS}/Info.plist"; then
    sed -i '' 's|</dict>|    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>\n</dict>|' "${CONTENTS}/Info.plist"
fi

# Also add CFBundleExecutable if missing
if ! grep -q "CFBundleExecutable" "${CONTENTS}/Info.plist"; then
    sed -i '' 's|</dict>|    <key>CFBundleExecutable</key>\n    <string>Scribe</string>\n</dict>|' "${CONTENTS}/Info.plist"
fi

rm -rf "$ICONSET_DIR"

echo "==> ${APP_BUNDLE} created: $(du -sh "${BUILD_DIR}/${APP_BUNDLE}" | cut -f1)"

# ─── Create DMG ──────────────────────────────────────────────────
echo "==> Creating ${DMG_NAME}..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy .app to staging
cp -R "${BUILD_DIR}/${APP_BUNDLE}" "${STAGING_DIR}/"

# Create Applications symlink (for drag-to-install)
ln -s /Applications "${STAGING_DIR}/Applications"

# Remove old DMG if exists
rm -f "${BUILD_DIR}/${DMG_NAME}"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}" 2>/dev/null

rm -rf "$STAGING_DIR"

DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
echo ""
echo "==> Done!"
echo "    .app: ${BUILD_DIR}/${APP_BUNDLE}"
echo "    .dmg: ${DMG_PATH} ($(du -h "$DMG_PATH" | cut -f1))"
echo ""
echo "To install: Open the .dmg and drag Scribe to Applications."
echo "On first launch: Right-click > Open (to bypass Gatekeeper for unsigned apps)."
