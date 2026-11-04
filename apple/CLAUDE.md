# CLAUDE.md – Abakus for the Mac, iPhone and iPad

The Swift package of the Apple apps; setup and targets in [`README.md`](README.md). The repository's
[`CLAUDE.md`](../CLAUDE.md), [`CONTEXT.md`](../CONTEXT.md) and [`DECISIONS.md`](../DECISIONS.md) apply here too.

## Validation

Run in this folder:

```
swift build -Xswiftc -warnings-as-errors
swift test
swift format lint --strict --recursive Package.swift Sources Tests iOS
swift build --scratch-path .build/ios --target AbakusIOSUI --triple arm64-apple-ios26.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc -warnings-as-errors
tools/test_ios.sh
```

The last two build the iOS UI for the simulator, then the iOS app, and run the core's tests on an iPhone simulator.
CI runs the same on macOS when `apple/` or `sync/` changes.
