#!/bin/zsh
# Renders site/og.png (1200x630 social share image) from Scripts/og/og.html with headless Chrome.
set -euo pipefail
cd "${0:A:h}/.."
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1200,630 --virtual-time-budget=6000 --screenshot="$PWD/site/og.png" "file://$PWD/Scripts/og/og.html" 2>/dev/null
echo "rendered site/og.png"
