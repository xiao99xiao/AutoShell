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
app_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist")
dmgbuild_bin=${DMGBUILD_BIN:-dmgbuild}
command -v "$dmgbuild_bin" >/dev/null
"$dmgbuild_bin" --settings "$packaging_dir/dmg-settings.py" \
    -D "app=$app_path" -D "background=$packaging_dir/background.tiff" "AutoShell $app_version" "$output_path"
