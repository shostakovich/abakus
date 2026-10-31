// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Abakus",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Abakus", targets: ["Abakus"]),
        .executable(name: "Snapshot", targets: ["Snapshot"]),
    ],
    targets: [
        .target(name: "AbakusCore"),
        .target(name: "AbakusUI", dependencies: ["AbakusCore"]),
        .executableTarget(
            name: "Abakus",
            dependencies: ["AbakusCore", "AbakusUI"],
            exclude: ["AppIcon.icon"]
        ),
        .executableTarget(name: "Snapshot", dependencies: ["AbakusCore", "AbakusUI"]),
        .testTarget(name: "AbakusCoreTests", dependencies: ["AbakusCore"]),
        .testTarget(name: "AbakusUITests", dependencies: ["AbakusCore", "AbakusUI"]),
        .testTarget(name: "SnapshotTests", dependencies: ["Snapshot"]),
    ],
    swiftLanguageModes: [.v6]
)
