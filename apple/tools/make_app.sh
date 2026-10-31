#!/bin/zsh
# Builds a release build and wraps it as build/Abakus.app (unsigned, for local use).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Abakus
bin=$(swift build -c release --show-bin-path)
app="build/Abakus.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Abakus" "$app/Contents/MacOS/Abakus"
xcrun actool Sources/Abakus/AppIcon.icon --compile "$app/Contents/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist "$(mktemp -d)/icon.plist" \
  --output-format human-readable-text --errors --warnings
test -f "$app/Contents/Resources/Assets.car"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>CFBundleExecutable</key><string>Abakus</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.abakus</string>
  <key>CFBundleName</key><string>Abakus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF
echo "$app"
