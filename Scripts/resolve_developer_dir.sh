#!/bin/bash
set -euo pipefail

if [ -n "${DEVELOPER_DIR:-}" ]; then
    printf '%s\n' "${DEVELOPER_DIR}"
    exit 0
fi

if xcrun --find actool >/dev/null 2>&1; then
    exit 0
fi

shopt -s nullglob
for candidate in \
    /Applications/Xcode.app/Contents/Developer \
    /Applications/Xcode*.app/Contents/Developer \
    "${HOME}/Applications/Xcode.app/Contents/Developer" \
    "${HOME}/Applications/Xcode"*.app/Contents/Developer; do
    if [ -d "${candidate}" ] && DEVELOPER_DIR="${candidate}" xcrun --find actool >/dev/null 2>&1; then
        printf '%s\n' "${candidate}"
        exit 0
    fi
done
