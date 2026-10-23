#!/bin/sh
# Regenerates Resources/AppIcon.icns and Resources/icon.png from tools/make-icon.swift.
set -eu
cd "$(dirname "$0")/.."

SET=build/AppIcon.iconset
mkdir -p "$SET"
swift tools/make-icon.swift Resources/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out "$SET/icon_${s}x${s}.png" > /dev/null
  d=$((s * 2))
  sips -z $d $d Resources/icon.png --out "$SET/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
