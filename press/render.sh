#!/bin/bash
# Renders the social and Product Hunt images from press/cards.html with headless Chrome.
# Output: website/assets/og-image.png, website/assets/social-square.png, press/producthunt/*.png
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PAGE="file://$PWD/press/cards.html"
mkdir -p press/producthunt website/assets
PROFILE=$(mktemp -d)   # throwaway profile: never touch the user's real Chrome
trap 'rm -rf "$PROFILE"' EXIT

render() { # id width height output
    "$CHROME" --headless=new --user-data-dir="$PROFILE" --no-first-run --disable-extensions --hide-scrollbars --force-device-scale-factor=1 \
        --use-angle=swiftshader --enable-unsafe-swiftshader --allow-file-access-from-files \
        --window-size="$2,$3" --virtual-time-budget=4000 \
        --screenshot="$4" "$PAGE?card=$1" >/dev/null 2>&1 || true
    if [ -s "$4" ]; then echo "  $4"; else echo "  FAILED: $4" >&2; fi
}

[ -z "${ONLY:-}" ] || { render "$ONLY" "$W" "$H" "$OUT"; exit 0; }
render og 1200 630 website/assets/og-image.png
render square 1080 1080 website/assets/social-square.png
for id in ph-1-hero ph-2-fetch ph-3-day ph-4-tricks ph-5-breeds ph-6-free; do
    render "$id" 1270 760 "press/producthunt/gallery-${id#ph-}.png"
done
