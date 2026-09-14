#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
output_dir="$project_dir/dist"
app_dir="$output_dir/WireMenu.app"
build_dir="$project_dir/.build/release"

swift build -c release --package-path "$project_dir"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/App/Info.plist" "$app_dir/Contents/Info.plist"
cp "$build_dir/WireMenu" "$app_dir/Contents/MacOS/WireMenu"
cp "$project_dir/Sources/WireMenu/Resources/ethernet-windows-connected.png" "$app_dir/Contents/Resources/"
swift "$project_dir/App/generate-icon.swift" "$project_dir/.build/AppIcon.iconset"
iconutil -c icns "$project_dir/.build/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
