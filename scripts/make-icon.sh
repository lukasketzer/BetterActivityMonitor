#!/bin/zsh
# Regenerates the app icon from scripts/make-icon.swift:
#   Resources/AppIcon.icns          legacy icon (macOS 14–15, small sizes hand-tuned)
#   Resources/AppIcon.icon/Assets/  full-bleed art of the macOS 26+ icon; bundle.sh compiles it into Assets.car
#   docs/icon.png                   256 px icon shown in the README
# Preview PNGs land in build/icon.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/icon}"
mkdir -p "$OUT"
swift scripts/make-icon.swift "$OUT"
iconutil -c icns "$OUT/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$OUT/AppIcon-fullbleed-1024.png" Resources/AppIcon.icon/Assets/art.png
cp "$OUT/AppIcon-256.png" docs/icon.png
echo "Wrote Resources/AppIcon.icns, Resources/AppIcon.icon and docs/icon.png (preview: $OUT/AppIcon-1024.png)"
