#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app_bundle=${1:-/tmp/AutoShell-build/Build/Products/Debug/AutoShell.app}
if [ ! -d "$app_bundle/Contents/Resources/en.lproj" ] || [ ! -d "$app_bundle/Contents/Resources/zh-Hans.lproj" ]; then
    echo 'Build AutoShell first, then pass its .app path to this script.' >&2
    exit 1
fi
test_root=$(mktemp -d -t AutoShell-localization)
trap 'rm -rf "$test_root"' EXIT
contents="$test_root/LocalizationChecks.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp -R "$app_bundle/Contents/Resources/en.lproj" "$contents/Resources/"
cp -R "$app_bundle/Contents/Resources/zh-Hans.lproj" "$contents/Resources/"
cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>LocalizationChecks</string><key>CFBundleIdentifier</key><string>com.autoshell.tests.localization</string><key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -parse-as-library -swift-version 6 AutoShell/ShellTask.swift Tests/LocalizationTests.swift -o "$contents/MacOS/LocalizationChecks"
EXPECTED_LANGUAGE=en "$contents/MacOS/LocalizationChecks" -AppleLanguages '(en)'
EXPECTED_LANGUAGE=zh-Hans "$contents/MacOS/LocalizationChecks" -AppleLanguages '(zh-Hans)'
EXPECTED_LANGUAGE=en "$contents/MacOS/LocalizationChecks" -AppleLanguages '(fr)'
