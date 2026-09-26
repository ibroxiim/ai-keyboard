#!/bin/bash
# Renders the adaptive-icon foreground (tools/icon-foreground.html) to a 432 px transparent PNG.
# Needs a headless Chrome: CHROME=/path/to/chrome tools/render_icon.sh   (run from android/)
set -euo pipefail
CHROME="${CHROME:-$(ls ~/.cache/hyperframes/chrome/chrome-headless-shell/*/chrome-headless-shell-mac-arm64/chrome-headless-shell 2>/dev/null | head -1)}"
[ -x "$CHROME" ] || { echo "set CHROME to a headless Chrome binary"; exit 1; }
OUT="app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"
mkdir -p "$(dirname "$OUT")"
"$CHROME" --headless --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=432,432 --screenshot="$PWD/$OUT" "file://$PWD/tools/icon-foreground.html" >/dev/null 2>&1
echo "wrote $OUT"
