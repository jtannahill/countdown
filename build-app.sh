#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Set to your Developer ID identity for reliable notifications, e.g.
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# Leave empty to fall back to ad-hoc signing (notifications may be unreliable).
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

echo "Building Countdown..."
swift build -c release

APP="Countdown.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/Countdown "$APP/Contents/MacOS/Countdown"

# Bundle fonts if present (NHG Display is licensed and not included in the repo —
# see README). The app falls back to the system font when none are bundled.
mkdir -p "$APP/Contents/Resources/Fonts"
if compgen -G "Resources/Fonts/*.ttf" > /dev/null; then
    cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
else
    echo "No fonts in Resources/Fonts/ — building without bundled fonts (system font fallback)."
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Countdown</string>
    <key>CFBundleDisplayName</key>
    <string>Countdown</string>
    <key>CFBundleIdentifier</key>
    <string>com.jamestannahill.countdown</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Countdown</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>ATSApplicationFontsPath</key>
    <string>Fonts</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Countdown shows the time remaining until your next calendar event.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Countdown shows the time remaining until your next calendar event.</string>
</dict>
</plist>
PLIST

# Sign the app — use Developer ID for reliable notifications, fall back to ad-hoc
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    echo "No SIGN_IDENTITY set — ad-hoc signing (notifications may be unreliable)."
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "Built $APP"
echo ""
echo "Launch:   open $(pwd)/$APP"
echo "Install:  mv $APP ~/Applications/   (then double-click to launch)"
