#!/bin/bash
# Builds CapturePreviewIOS (the real three-screen app, not the component
# gallery), wraps it into a throwaway .app bundle -- SwiftPM's executable
# target produces a bare Mach-O, not an app bundle -- then installs and
# launches it on a chosen iOS Simulator device. The sibling
# run-ios-preview.sh does the same for the design system gallery.
#
# Usage: scripts/run-ios-app.sh ["iPhone 17"]
set -euo pipefail

DS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${1:-iPhone 17}"
BUNDLE_ID="com.reminderapp.app"

DEVICE_ID=$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | grep -v "Pro\|Plus\|e (" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
if [ -z "$DEVICE_ID" ]; then
  echo "Could not find an available simulator matching '$DEVICE_NAME'" >&2
  exit 1
fi

cd "$DS_DIR"
xcodebuild -scheme CapturePreviewIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build

# The Groq key, for the simulator path only. The real app target reads this
# through XcodeGen's configFiles; this bundle is hand-assembled below, so the
# key has to be lifted out of the same gitignored xcconfig by hand. Missing or
# empty is fine -- the app falls back to on-device heuristics and still saves
# every capture.
SECRETS="$DS_DIR/../Secrets.xcconfig"
GROQ_API_KEY=""
if [ -f "$SECRETS" ]; then
  GROQ_API_KEY=$(sed -n 's/^[[:space:]]*GROQ_API_KEY[[:space:]]*=[[:space:]]*//p' "$SECRETS" | head -1 | tr -d '[:space:]')
fi

PRODUCTS="$DS_DIR/.build/xcode/Build/Products/Debug-iphonesimulator"
APP="$PRODUCTS/CapturePreviewIOS.app"
rm -rf "$APP"
mkdir -p "$APP"
cp "$PRODUCTS/CapturePreviewIOS" "$APP/CapturePreviewIOS"

# SwiftPM puts a target's resources in a sibling .bundle rather than inside the
# executable, so a hand-assembled .app has to carry it across by hand.
# DesignSystem's Resources hold Sorts Mill Goudy, which DSFont.serif registers
# at runtime -- without this the app traps on the first serif glyph, which is
# the masthead on the very first screen.
for BUNDLE in "$PRODUCTS"/*.bundle; do
  [ -e "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/"
done

cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CapturePreviewIOS</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>CapturePreviewIOS</string>
  <key>CFBundleDisplayName</key><string>Capture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
  <key>DTPlatformName</key><string>iphonesimulator</string>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  <key>NSMicrophoneUsageDescription</key>
  <string>So you can talk instead of type. Audio is transcribed on your device and never leaves it.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>To turn what you say into text, on this device, while you're still saying it.</string>
  <key>GROQ_API_KEY</key><string>$GROQ_API_KEY</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

open -a Simulator
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" "$APP"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

echo "Running on device $DEVICE_ID. Screenshot with:"
echo "  xcrun simctl io $DEVICE_ID screenshot out.png"
