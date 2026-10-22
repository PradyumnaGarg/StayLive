#!/bin/zsh
# Renders the app icon to an .icns file. Usage: Scripts/make-icon.sh <output.icns>
set -euo pipefail
cd "${0:A:h}/.."
OUT="$1"
TMP="$(mktemp -d)"
swiftc -O -o "$TMP/make-icon" Scripts/make-icon.swift
"$TMP/make-icon" "$TMP/AppIcon.iconset"
mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT"
cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" docs/icon.png 2>/dev/null || true
rm -rf "$TMP"
