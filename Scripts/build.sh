#!/bin/zsh
# Builds StayLive.app (with the embedded StayLive.saver) into build/.
# Usage: Scripts/build.sh [--zip]
set -euo pipefail
cd "${0:A:h}/.."

BUNDLE_ID="${STAYLIVE_BUNDLE_ID:-io.github.pradyumnagarg.StayLive}"
VERSION="$(cat VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
TARGET="arm64-apple-macos14.0"

APP=build/StayLive.app
SAVER="$APP/Contents/Resources/StayLive.saver"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"

swiftc -O -target "$TARGET" -parse-as-library -module-name StayLive \
    -o "$APP/Contents/MacOS/StayLive" App/*.swift

swiftc -O -target "$TARGET" -parse-as-library -module-name StayLiveSaver \
    -Xlinker -bundle -o "$SAVER/Contents/MacOS/StayLiveSaver" ScreenSaver/*.swift

if [[ ! -f build/AppIcon.icns || Scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
    Scripts/make-icon.sh build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp build/AppIcon.icns "$SAVER/Contents/Resources/thumbnail.icns"

SAVER_VERSION=$(cat ScreenSaver/*.swift | shasum | cut -c1-12)

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>StayLive</string>
    <key>CFBundleDisplayName</key><string>StayLive</string>
    <key>CFBundleExecutable</key><string>StayLive</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
EOF

cat > "$SAVER/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID.saver</string>
    <key>CFBundleName</key><string>StayLive</string>
    <key>CFBundleExecutable</key><string>StayLiveSaver</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$SAVER_VERSION</string>
    <key>NSPrincipalClass</key><string>StayLiveSaverView</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF

codesign --force --sign - "$SAVER"
codesign --force --sign - "$APP"
echo "built $APP ($VERSION, build $BUILD_NUMBER)"

if [[ "${1:-}" == "--zip" ]]; then
    mkdir -p dist
    ditto -c -k --keepParent "$APP" "dist/StayLive-$VERSION.zip"
    echo "packaged dist/StayLive-$VERSION.zip"
fi
