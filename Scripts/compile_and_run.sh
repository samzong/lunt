#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVED_DEVELOPER_DIR="$("${SCRIPT_DIR}/resolve_developer_dir.sh")"
if [ -n "${RESOLVED_DEVELOPER_DIR}" ]; then
    export DEVELOPER_DIR="${RESOLVED_DEVELOPER_DIR}"
fi
if ! xcrun --find actool >/dev/null 2>&1; then
    echo "❌ Error: Xcode is required to compile Assets.xcassets. Install Xcode or set DEVELOPER_DIR." >&2
    exit 1
fi

CONFIG="${1:-debug}"
APP_NAME="${APP_NAME:-Lunt}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-Lunt}"
ARCH="$(uname -m)"
if [ "${ARCH}" != "arm64" ]; then
    echo "❌ Error: Lunt requires Apple Silicon (arm64). Current host is '${ARCH}'." >&2
    exit 1
fi

echo "===> Stopping any running ${APP_NAME} instances..."
pkill -x "${EXECUTABLE_NAME}" 2>/dev/null || true

echo "===> Building ${APP_NAME} (${CONFIG})..."
swift build -c "${CONFIG}" --triple "${ARCH}-apple-macosx"

echo "===> Packaging app bundle..."
./Scripts/package_app.sh "${CONFIG}" "${ARCH}"

echo "===> Launching ${APP_NAME}..."
open "$(swift build -c "$CONFIG" --triple "${ARCH}-apple-macosx" --show-bin-path)/${APP_NAME}.app"
