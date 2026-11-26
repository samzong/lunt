#!/bin/bash

set -euo pipefail

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
