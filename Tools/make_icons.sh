#!/bin/zsh
# Tạo 3 biến thể icon (mặc định / tối / phủ màu) vào asset catalog.
set -e
cd "$(dirname "$0")/.."
DIR=UpSnap/Assets.xcassets/AppIcon.appiconset
BIN="${TMPDIR:-/tmp}/upsnap_make_icon"
swiftc -O Tools/make_icon.swift -o "$BIN"
"$BIN" "$DIR/AppIcon.png" light
"$BIN" "$DIR/AppIcon-Dark.png" dark
"$BIN" "$DIR/AppIcon-Tinted.png" tinted
echo "Đã tạo icon trong $DIR"
