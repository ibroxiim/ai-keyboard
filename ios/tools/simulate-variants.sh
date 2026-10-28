#!/bin/bash
# Debug builds in the iOS Simulator: shows the suggestion bar as it looks after ✨ — three fake variants, the
# original draft and one tweak on — without Full Access or a Gemini call. The keyboard must be on screen.
#
#   tools/simulate-variants.sh [device-udid]    # default: the booted simulator
set -euo pipefail
xcrun simctl spawn "${1:-booted}" notifyutil -p com.ibrokhim.dmtranslator.debug.simulatedVariants
echo "Variants simulated"
