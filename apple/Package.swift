// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Abakus",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .executable(name: "Abakus", targets: ["Abakus"]),
        .executable(name: "Snapshot", targets: ["Snapshot"]),
        .library(name: "AbakusIOSUI", targets: ["AbakusIOSUI"]),
    ],
    targets: [
        .target(name: "AbakusCore"),
        .target(name: "AbakusUI", dependencies: ["AbakusCore"]),
        .target(name: "AbakusMacUI", dependencies: ["AbakusCore", "AbakusUI"]),
        .target(name: "AbakusIOSUI", dependencies: ["AbakusCore", "AbakusUI"]),
        .executableTarget(
            name: "Abakus",
            dependencies: ["AbakusCore", "AbakusUI", "AbakusMacUI"],
            exclude: ["AppIcon.icon"]
        ),
        .executableTarget(name: "Snapshot", dependencies: ["AbakusCore", "AbakusUI", "AbakusMacUI"]),
        .testTarget(name: "AbakusCoreTests", dependencies: ["AbakusCore"]),
        .testTarget(name: "AbakusUITests", dependencies: ["AbakusCore", "AbakusUI"]),
        .testTarget(
            name: "AbakusMacUITests", dependencies: ["AbakusCore", "AbakusUI", "AbakusMacUI", "AbakusUITests"]),
        .testTarget(name: "SnapshotTests", dependencies: ["Snapshot"]),
    ],
    swiftLanguageModes: [.v6]
)
