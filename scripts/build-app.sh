#!/usr/bin/env zsh
set -euo pipefail

# Build and package a standalone Voibe.app from this Swift package.
#
# Usage:
#   scripts/build-app.sh
#   OPEN_AFTER_BUILD=0 scripts/build-app.sh
#   VOIBE_BUNDLE_ID=com.example.voibe CODESIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
cd "$REPO_ROOT"

# Keep app identity stable across builds so macOS permissions can persist.
# Use VOIBE_* overrides to avoid accidental collision with generic env vars.
APP_NAME="${VOIBE_APP_NAME:-Voibe}"
EXECUTABLE_NAME="${VOIBE_EXECUTABLE_NAME:-Voibe}"
BUNDLE_ID="${VOIBE_BUNDLE_ID:-com.corlinp.voibe}"
APP_VERSION="${APP_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_MACOS="${MIN_MACOS:-13.0}"
DIST_DIR="${VOIBE_DIST_DIR:-dist}"
APP_PATH="${DIST_DIR}/${APP_NAME}.app"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-1}"
GENERATE_ICON="${GENERATE_ICON:-1}"
ICON_WORKDIR="${DIST_DIR}/icon-assets"
ICON_PATH="${ICON_WORKDIR}/AppIcon.icns"

if [[ "$GENERATE_ICON" == "1" ]]; then
  echo "Generating app icon..."
  python3 scripts/generate-app-icon.py --out-dir "$ICON_WORKDIR"
fi

echo "Building release binary..."
swift build -c release

echo "Packaging ${APP_PATH}..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources/Sounds"

cp ".build/release/${EXECUTABLE_NAME}" "$APP_PATH/Contents/MacOS/${EXECUTABLE_NAME}"
cp Resources/Sounds/*.wav "$APP_PATH/Contents/Resources/Sounds/"
cp "$ICON_PATH" "$APP_PATH/Contents/Resources/AppIcon.icns"

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_MACOS}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Voibe needs access to your microphone to transcribe your speech.</string>
</dict>
</plist>
EOF

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "Signing app (identity: ${CODESIGN_IDENTITY})..."
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_PATH"
else
  echo "Skipping codesign (set CODESIGN_IDENTITY to sign explicitly)."
fi

echo "Built: ${APP_PATH}"
echo "Next: launch it from Finder or run: open \"$APP_PATH\""

if [[ "$OPEN_AFTER_BUILD" == "1" ]]; then
  open "$APP_PATH"
fi
