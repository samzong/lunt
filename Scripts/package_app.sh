#!/bin/bash
# Package SPM build output into a macOS .app bundle
# Usage: ./Scripts/package_app.sh [debug|release] [arch]
#   config: debug or release (default: release)
#   arch: x86_64 or arm64 (default: current machine arch)

set -euo pipefail

CONFIG="${1:-release}"
ARCH="${2:-$(uname -m)}"
APP_NAME="${APP_NAME:-Lunt}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-Lunt}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Lunt/Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Lunt/Info.plist)}"
BUILD_DIR="$(swift build -c "$CONFIG" --triple "${ARCH}-apple-macosx" --show-bin-path)"

BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "===> Packaging ${APP_NAME}.app (${CONFIG}, ${ARCH})..."

# Create app bundle structure
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

# Copy binary
if [ -f "${BUILD_DIR}/${EXECUTABLE_NAME}" ]; then
    cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${BUNDLE}/Contents/MacOS/"
else
    echo "❌ Error: Binary not found at ${BUILD_DIR}/${EXECUTABLE_NAME}"
    echo "   Run 'swift build -c ${CONFIG}' first."
    exit 1
fi

if [ -f "Sources/Lunt/Info.plist" ]; then
    cp "Sources/Lunt/Info.plist" "${BUNDLE}/Contents/"
    
    INFO_PLIST="${BUNDLE}/Contents/Info.plist"
    echo "===> Updating version to ${VERSION} (${BUILD_NUMBER})..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${INFO_PLIST}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${INFO_PLIST}"
fi

ASSETS_PATH="Sources/Lunt/Resources/Assets.xcassets"
if [ -d "${ASSETS_PATH}" ]; then
    if command -v actool &> /dev/null; then
        actool --compile "${BUNDLE}/Contents/Resources" \
               --platform macosx \
               --minimum-deployment-target 15.0 \
               --app-icon AppIcon \
               --output-partial-info-plist /dev/null \
               "${ASSETS_PATH}" 2>/dev/null || cp -r "${ASSETS_PATH}" "${BUNDLE}/Contents/Resources/"
    else
        cp -r "${ASSETS_PATH}" "${BUNDLE}/Contents/Resources/"
    fi
fi

for lproj in Sources/Lunt/Resources/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -r "$lproj" "${BUNDLE}/Contents/Resources/"
    fi
done

# Copy Sparkle framework
SPARKLE_SRC="${BUILD_DIR}/Sparkle.framework"
if [ -d "${SPARKLE_SRC}" ]; then
    echo "===> Copying Sparkle.framework..."
    mkdir -p "${BUNDLE}/Contents/Frameworks"
    # Use -a to preserve links and attributes, avoiding ambiguous bundle format errors
    cp -a "${SPARKLE_SRC}" "${BUNDLE}/Contents/Frameworks/"
    
    # Remove quarantine attribute if present to avoid verification issues
    xattr -cr "${BUNDLE}/Contents/Frameworks/Sparkle.framework"
    
    # Fix rpath to find Sparkle in Frameworks folder
    echo "===> Fixing rpath for Sparkle..."
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true
else
    echo "❌ Error: Sparkle.framework not found at ${SPARKLE_SRC}"
    exit 1
fi

# Self-sign the app (with frameworks)
codesign --force --deep --sign - "${BUNDLE}"

echo "✅ Created ${BUNDLE}"
echo "   Run: open ${BUNDLE}"
