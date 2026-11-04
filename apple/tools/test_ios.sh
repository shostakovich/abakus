#!/bin/sh
# Builds the iOS app and runs the core's tests on an iPhone simulator, a booted one if there is one.
set -eu
cd "$(dirname "$0")/.."
iphones=$(xcrun simctl list devices available | grep -E '^ +iPhone')
device=$( (echo "$iphones" | grep Booted || echo "$iphones") | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl bootstatus "$device" -b > /dev/null
xcodebuild build -project iOS/Abakus.xcodeproj -scheme Abakus -destination "id=$device" \
  -derivedDataPath .build/xcode-app CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild build-for-testing -scheme AbakusCoreTests -destination "id=$device" -derivedDataPath .build/xcode-tests -quiet
# Run directly, as xcodebuild's test runner may hang before it connects to the simulator.
xcrun simctl spawn "$device" "$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest" \
  "$PWD/.build/xcode-tests/Build/Products/Debug-iphonesimulator/AbakusCoreTests.xctest"
