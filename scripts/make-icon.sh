#!/usr/bin/env bash
# Rigenera app/Icon/AppIcon.icns da app/Icon/AppIcon.svg (serve solo se cambia il disegno).
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
swiftc -O -o "$tmp/svg-to-png" "$repo/scripts/svg-to-png.swift"
set_dir="$tmp/AppIcon.iconset"; mkdir "$set_dir"
for s in 16 32 128 256 512; do
  "$tmp/svg-to-png" "$repo/app/Icon/AppIcon.svg" "$set_dir/icon_${s}x${s}.png" "$s"
  "$tmp/svg-to-png" "$repo/app/Icon/AppIcon.svg" "$set_dir/icon_${s}x${s}@2x.png" "$((s * 2))"
done
iconutil -c icns "$set_dir" -o "$repo/app/Icon/AppIcon.icns"
echo "scritto app/Icon/AppIcon.icns"
