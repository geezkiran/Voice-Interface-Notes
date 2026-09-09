#!/bin/bash
# Builds DesignSystemPreviewIOS, wraps it into a throwaway .app bundle
# (SwiftPM's executable target produces a bare Mach-O, not an app bundle),
# then installs and launches it on a chosen iOS Simulator device. Use this
# to eyeball the design system on a real device silhouette without a full
# Xcode app project existing yet.
#
# Usage: scripts/run-ios-preview.sh ["iPhone 17"]
set -euo pipefail

DS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${1:-iPhone 17}"
BUNDLE_ID="com.reminderapp.designsystempreview"

DEVICE_ID=$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | grep -v "Pro\|Plus\|e (" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
if [ -z "$DEVICE_ID" ]; then
  echo "Could not find an available simulator matching '$DEVICE_NAME'" >&2
  exit 1
fi

cd "$DS_DIR"
xcodebuild -scheme DesignSystemPreviewIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build

PRODUCTS="$DS_DIR/.build/xcode/Build/Products/Debug-iphonesimulator"
APP="$PRODUCTS/DesignSystemPreviewIOS.app"
rm -rf "$APP"
mkdir -p "$APP"
cp "$PRODUCTS/DesignSystemPreviewIOS" "$APP/DesignSystemPreviewIOS"

cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DesignSystemPreviewIOS</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>DesignSystemPreviewIOS</string>
  <key>CFBundleDisplayName</key><string>Design Preview</string>
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
