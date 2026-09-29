#!/bin/sh
# Builds build/KeepLidOpen.app with swiftc (no Xcode project needed).
# If swiftc says the SDK was built by a different compiler version, point
# SDKROOT at another SDK, e.g.
#   SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk scripts/build.sh
set -eu
cd "$(dirname "$0")/.."
app=build/KeepLidOpen.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Resources/Info.plist "$app/Contents/"
swiftc -O -module-name KeepLidOpen -o "$app/Contents/MacOS/KeepLidOpen" Sources/*.swift
codesign --force --sign - "$app"
echo "built $app"
