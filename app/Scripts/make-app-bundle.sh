#!/bin/bash
#
# Assemble a real .app bundle from the SwiftPM build product.
#
# Why a script instead of an .xcodeproj: the project stays entirely text —
# diffable, reviewable, and editable by tooling — instead of a binary blob that
# churns on every touch. The tradeoff is that we hand-write Info.plist, which is
# a dozen lines and rarely changes.
#
# Usage:
#   ./Scripts/make-app-bundle.sh [debug|release]
#
# Output: build/Umber.app
#
set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="Umber"
BUNDLE_ID="com.griffinlong.umber"
VERSION="0.1.0"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "error: expected executable at $BIN" >&2
  exit 1
fi

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# Any resource bundles SwiftPM produced for dependencies must travel with the
# app, or code that looks them up at runtime finds nothing once the binary is
# moved out of .build.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key>
	<false/>
	<key>NSSupportsSuddenTermination</key>
	<false/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough for local launch; a real distribution build needs a
# Developer ID identity and notarisation.
codesign --force --sign - "$APP" >/dev/null 2>&1 \
  && echo "==> ad-hoc signed" \
  || echo "==> warning: codesign failed; app may still launch locally"

echo "==> built $APP"
echo "    open $APP"
