#!/bin/bash
# Builds the animated Product Hunt thumbnail (and a still PNG) from the app's renderer.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build press/producthunt
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
swiftc -O -o build/ph-thumbnail $SOURCES press/thumbnail/main.swift
build/ph-thumbnail press/producthunt/thumbnail.gif
sips -s format png press/producthunt/thumbnail.gif --out press/producthunt/thumbnail.png >/dev/null
echo "  press/producthunt/thumbnail.png"
