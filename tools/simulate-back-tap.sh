#!/bin/bash
# Stand-in for Back Tap in the iOS Simulator (Debug builds): screenshots the simulator,
# hands the image to the AI Keyboard through the App Group and triggers the same analysis
# the Back Tap shortcut runs on a phone. The keyboard must be on screen.
#
#   tools/simulate-back-tap.sh [device-udid]    # default: the booted simulator
set -euo pipefail
DEVICE="${1:-booted}"
BUNDLE_ID="com.ibrokhim.dmtranslator"
GROUP_ID="group.com.ibrokhim.dmtranslator"

GROUP_DIR="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" "$GROUP_ID")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

xcrun simctl io "$DEVICE" screenshot --type=png "$TMP/shot.png" >/dev/null
# Same size the app sends to Gemini, so the keyboard extension does not decode a full-resolution PNG.
sips -s format jpeg -s formatOptions 80 --resampleWidth 720 "$TMP/shot.png" --out "$GROUP_DIR/simulated-back-tap.jpg" >/dev/null
xcrun simctl spawn "$DEVICE" notifyutil -p com.ibrokhim.dmtranslator.debug.simulatedBackTap
echo "Back Tap simulated on $DEVICE"
