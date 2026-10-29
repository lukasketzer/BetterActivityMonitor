#!/bin/zsh
# Regenerates the app icon from scripts/make-icon.swift:
#   Resources/AppIcon.icns          legacy icon (macOS 14–15, small sizes hand-tuned)
#   Resources/AppIcon.icon/Assets/  full-bleed art of the macOS 26+ icon; bundle.sh compiles it into Assets.car
# Preview PNGs land in build/icon.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/icon}"
mkdir -p "$OUT"
swift scripts/make-icon.swift "$OUT"
iconutil -c icns "$OUT/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$OUT/AppIcon-fullbleed-1024.png" Resources/AppIcon.icon/Assets/art.png
echo "Wrote Resources/AppIcon.icns and Resources/AppIcon.icon (preview: $OUT/AppIcon-1024.png)"
