#!/bin/bash
# Builds build/DummyPet.app (universal arm64 + x86_64 when possible).
# Usage: ./build.sh          build
#        ./build.sh run      build and launch
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DummyPet.app"
BIN="$APP/Contents/MacOS/DummyPet"
SOURCES=(Sources/*.swift)

rm -rf "$APP" build/obj build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

slices=()
for arch in arm64 x86_64; do
    if swiftc -O -target "$arch-apple-macos12.0" -o "build/obj/DummyPet-$arch" "${SOURCES[@]}" 2>build/obj/$arch.log; then
        slices+=("build/obj/DummyPet-$arch")
    else
        echo "warning: $arch build failed (see build/obj/$arch.log)" >&2
    fi
done
if [ ${#slices[@]} -eq 0 ]; then
    cat build/obj/*.log >&2
    exit 1
fi
lipo -create "${slices[@]}" -output "$BIN"

cp Info.plist "$APP/Contents/Info.plist"
"$BIN" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP ($(lipo -archs "$BIN"))"

if [ "${1:-}" = "run" ]; then
    pkill -x DummyPet 2>/dev/null || true
    open "$APP"
fi
