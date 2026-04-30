#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="SwiftCull"
SCHEME="SwiftCull"
BUNDLE_ID="com.swiftcull.app"
BUILD_DIR="${PROJECT_DIR}/build"
DMG_DIR="${BUILD_DIR}/dmg"
APP_PATH="${BUILD_DIR}/Release/${PROJECT_NAME}.app"
DMG_OUTPUT="${PROJECT_DIR}/${PROJECT_NAME}.dmg"
DMG_RW="${BUILD_DIR}/${PROJECT_NAME}_rw.dmg"
VOLUME_NAME="${PROJECT_NAME}"

echo "==> Cleaning previous build..."
rm -rf "${BUILD_DIR}"
rm -f "${DMG_OUTPUT}"

echo "==> Building ${PROJECT_NAME} in Release mode..."
xcodebuild \
    -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}/Release" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Automatic \
    clean build \
    | tail -5

if [ ! -d "${APP_PATH}" ]; then
    echo "Error: ${APP_PATH} not found. Build may have failed."
    exit 1
fi

echo "==> Built app size: $(du -sh "${APP_PATH}" | cut -f1)"

echo "==> Preparing DMG contents..."
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

echo "==> Creating read-write DMG..."
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDRW \
    "${DMG_RW}"

echo "==> Customizing DMG window..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_RW}" | \
    grep -m 1 "/Volumes/${VOLUME_NAME}" | \
    awk '{print $NF}')

echo "    Mounted at: ${MOUNT_DIR}"
sleep 3

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1060, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set label position of viewOptions to bottom
        set position of item "${PROJECT_NAME}.app" of container window to {200, 240}
        set position of item "Applications" of container window to {460, 240}
        close
        open
        delay 3
        close
    end tell
end tell
APPLESCRIPT

echo "==> Detaching DMG..."
sync
hdiutil detach "${MOUNT_DIR}" -force -quiet

echo "==> Converting to compressed DMG..."
hdiutil convert "${DMG_RW}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_OUTPUT}"

echo "==> Cleaning up temp files..."
rm -rf "${DMG_DIR}"
rm -f "${DMG_RW}"

echo ""
echo "==> DMG created successfully: ${DMG_OUTPUT}"
echo "==> DMG size: $(du -sh "${DMG_OUTPUT}" | cut -f1)"
