#!/bin/bash
# Puts a KLIPY API key into Shared/Secrets.swift (gitignored) without the key passing through a chat or shell
# history: it is typed here, hidden, and written straight to the file.
#
#   ios/tools/set-klipy-key.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SECRETS="Shared/Secrets.swift"
if [ ! -f "$SECRETS" ]; then
  echo "Shared/Secrets.swift topilmadi — avval Shared/Secrets.swift.example'dan nusxalang." >&2
  exit 1
fi
printf 'KLIPY API kalitini qo'\''ying (ko'\''rinmaydi): '
IFS= read -r -s KEY
echo
KEY="${KEY//[[:space:]]/}"
if [ -z "$KEY" ]; then
  echo "Bo'sh — hech narsa o'zgarmadi." >&2
  exit 1
fi
if grep -q 'static let klipyAPIKey' "$SECRETS"; then
  KEY="$KEY" perl -0pi -e 's/static let klipyAPIKey = "[^"]*"/static let klipyAPIKey = "$ENV{KEY}"/' "$SECRETS"
else
  KEY="$KEY" perl -0pi -e 's/\n}\s*$/\n    static let klipyAPIKey = "$ENV{KEY}"\n}\n/' "$SECRETS"
fi
LEN=${#KEY}
echo "Saqlandi: klipyAPIKey ($LEN belgi) → $SECRETS"
