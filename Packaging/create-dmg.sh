#!/bin/bash
set -euo pipefail
if [[ $# != 2 ]]; then
    echo "Usage: $0 /path/to/AutoShell.app /path/to/AutoShell-version.dmg" >&2
    exit 1
fi
app_path=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
output_path=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
packaging_dir=$(cd "$(dirname "$0")" && pwd)
[[ -d "$app_path" && "$(basename "$app_path")" == "AutoShell.app" ]]
[[ ! -e "$output_path" ]]
command -v create-dmg >/dev/null
stage_dir=$(mktemp -d -t AutoShell-dmg)
trap 'rm -rf "$stage_dir"' EXIT
ditto "$app_path" "$stage_dir/AutoShell.app"
create-dmg \
    --volname "AutoShell" \
    --volicon "$app_path/Contents/Resources/AppIcon.icns" \
    --background "$packaging_dir/background.tiff" \
    --window-pos 240 160 \
    --window-size 740 488 \
    --icon-size 104 \
    --text-size 13 \
    --icon "AutoShell.app" 200 232 \
    --hide-extension "AutoShell.app" \
    --app-drop-link 540 232 \
    --no-internet-enable \
    "$output_path" "$stage_dir"
