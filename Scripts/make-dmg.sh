#!/bin/zsh
# Packages build/StayLive.app into dist/StayLive-<version>.dmg (drag-to-Applications installer).
# Usage: Scripts/make-dmg.sh   (run Scripts/build.sh first)
set -euo pipefail
cd "${0:A:h}/.."

VERSION="$(cat VERSION)"
APP=build/StayLive.app
[[ -d "$APP" ]] || { echo "Build the app first: Scripts/build.sh"; exit 1; }

STAGE="$(mktemp -d)/StayLive"
mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/StayLive.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me First.txt" <<'EOF'
Installing StayLive
===================

1. Drag StayLive onto the Applications folder in this window.
2. Open StayLive from your Applications folder.

The first time you open it, macOS may say it can't verify the developer,
because StayLive is a free open-source app that isn't notarized by Apple.
To open it anyway:

  System Settings > Privacy & Security > scroll down > "Open Anyway" next to StayLive

StayLive then lives in your menu bar (the play icon) and starts automatically at login.
Source code, how it works and how to uninstall: https://github.com/PradyumnaGarg/StayLive
EOF

OUT="dist/StayLive-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "StayLive $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
rm -rf "$(dirname "$STAGE")"
echo "packaged $OUT ($(du -h "$OUT" | cut -f1))"
