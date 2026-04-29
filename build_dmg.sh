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

echo "==> Creating DMG..."
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_OUTPUT}"

echo "==> Cleaning up temp files..."
rm -rf "${DMG_DIR}"

echo ""
echo "==> DMG created successfully: ${DMG_OUTPUT}"
echo "==> DMG size: $(du -sh "${DMG_OUTPUT}" | cut -f1)"
