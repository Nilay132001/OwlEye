#!/bin/sh
# Builds OwlEye.app into ./build.noindex. Usage: ./build.sh [--install]
# The .noindex suffix keeps Spotlight from listing this copy next to the installed one.
set -eu
cd "$(dirname "$0")"

swift build -c release
APP=build.noindex/OwlEye.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/OwlEye "$APP/Contents/MacOS/OwlEye"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/askpass.sh "$APP/Contents/Resources/askpass.sh"
chmod 755 "$APP/Contents/Resources/askpass.sh"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  ditto "$APP" "$HOME/Applications/OwlEye.app"
  echo "Installed to ~/Applications/OwlEye.app"
fi
