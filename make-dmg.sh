#!/bin/bash
# Packages build/DummyPet.app into a drag-to-Applications disk image.
# Output: build/DummyPet-<version>.dmg, also copied to website/downloads/DummyPet.dmg
# Usage: ./make-dmg.sh            (builds the app first if needed)
#        ./make-dmg.sh --rebuild  (always rebuilds the app)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DummyPet.app"
if [ "${1:-}" = "--rebuild" ] || [ ! -d "$APP" ]; then
    ./build.sh
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
VOLNAME="DummyPet"
STAGE="build/dmg-stage"
RW="build/DummyPet-rw.dmg"
OUT="build/DummyPet-$VERSION.dmg"

rm -rf "$STAGE" "$RW" "$OUT" build/dmg-art
mkdir -p "$STAGE/.background"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
"$APP/Contents/MacOS/DummyPet" --render-dmg-background build/dmg-art
tiffutil -cathidpicheck build/dmg-art/background.png build/dmg-art/background@2x.png \
    -out "$STAGE/.background/background.tiff" >/dev/null
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

# Detach any stale copy of the volume so Finder addresses the right disk.
for v in /Volumes/"$VOLNAME"*; do
    [ -d "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1 || true
done

SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW" >/dev/null

ATTACH=$(hdiutil attach -readwrite -noverify -noautoopen "$RW")
DEVICE=$(echo "$ATTACH" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT=$(echo "$ATTACH" | grep -o '/Volumes/.*' | head -1)
DISK=$(basename "$MOUNT")

SetFile -a C "$MOUNT" || true

# Lay out the Finder window: background art, big icons, app on the left, Applications on the right.
if ! osascript <<EOF
tell application "Finder"
    tell disk "$DISK"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "DummyPet.app" of container window to {165, 190}
        set position of item "Applications" of container window to {495, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "warning: Finder layout step failed (allow Automation access for your terminal to style the window)" >&2
fi

chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$DEVICE" >/dev/null || hdiutil detach "$DEVICE" -force >/dev/null

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"
codesign --force --sign - "$OUT" >/dev/null 2>&1 || true

mkdir -p website/downloads website/assets
cp "$OUT" website/downloads/DummyPet.dmg
cp build/AppIcon.iconset/icon_256x256@2x.png website/assets/icon.png
for spec in "32 favicon-32" "180 apple-touch-icon" "192 icon-192"; do
    set -- $spec
    sips -z "$1" "$1" build/AppIcon.iconset/icon_512x512@2x.png --out "website/assets/$2.png" >/dev/null
done
# Keep the size shown on the download page in sync with the real file.
SIZE_LABEL=$(awk -v b="$(stat -f%z "$OUT")" 'BEGIN { printf "%.1f MB", b / 1000000 }')
sed -i '' -E "s#<span data-size>[^<]*</span>#<span data-size>$SIZE_LABEL</span>#" website/index.html
echo "Built $OUT ($(du -h "$OUT" | cut -f1)) and copied to website/downloads/DummyPet.dmg"
