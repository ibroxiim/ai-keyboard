#!/usr/bin/env python3
"""Types text on the AI Keyboard in an emulator by tapping its keys.

Key centres come from the debug-build logcat line `AIKeys: layout {...}` that KeysView prints after
every layout. Lowercase letters, digits on the numbers layer, space and the Uzbek letters oʻ/gʻ.
Usage: tools/adb-type.py "salom dunyo"   (ADB env var overrides the adb path)
"""
import json, os, re, subprocess, sys, time

ADB = os.environ.get("ADB", os.path.expanduser("~/Library/Android/sdk/platform-tools/adb"))


def layout():
    log = subprocess.run([ADB, "logcat", "-d", "-s", "AIKeys:D"], capture_output=True, text=True).stdout
    lines = re.findall(r"layout (\{.*\})", log)
    if not lines:
        sys.exit("no AIKeys layout in logcat — is the debug keyboard on screen?")
    return json.loads(lines[-1])


def tap(point):
    subprocess.run([ADB, "shell", "input", "tap", str(point[0]), str(point[1])], check=True)
    time.sleep(0.08)


def main(text):
    keys = layout()
    i = 0
    while i < len(text):
        pair = text[i:i + 2]
        if pair in ("oʻ", "gʻ"):
            tap(keys[pair]); i += 2; continue
        ch = text[i]
        name = "space" if ch == " " else ch
        if name not in keys and "layer:123" in keys:
            tap(keys["layer:123"]); time.sleep(0.2); keys = layout()
        if name not in keys and "layer:ABC" in keys:
            tap(keys["layer:ABC"]); time.sleep(0.2); keys = layout()
        if name not in keys:
            sys.exit(f"no key for {ch!r}")
        tap(keys[name])
        if name == "space" and "layer:ABC" in keys:
            time.sleep(0.2); keys = layout()  # space returns to the letter layer
        i += 1


if __name__ == "__main__":
    main(sys.argv[1])
