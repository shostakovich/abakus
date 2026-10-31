import Foundation
import Testing

@Suite struct AppNameTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func theBuiltAppIsNamedAbakus() throws {
        let script = try String(contentsOf: Self.root.appending(path: "tools/make_app.sh"), encoding: .utf8)
        #expect(script.contains("swift build -c release --product Abakus\n"))
        #expect(script.contains(#"app="build/Abakus.app""#))
        let start = try #require(script.range(of: "<?xml"))
        let end = try #require(script.range(of: "</plist>"))
        let plist = try PropertyListSerialization.propertyList(
            from: Data(script[start.lowerBound..<end.upperBound].utf8), format: nil)
        let info = try #require(plist as? [String: Any])
        #expect(info["CFBundleName"] as? String == "Abakus")
        #expect(info["CFBundleExecutable"] as? String == "Abakus")
        #expect(info["CFBundleIdentifier"] as? String == "local.abakus")
        let package = try String(contentsOf: Self.root.appending(path: "Package.swift"), encoding: .utf8)
        #expect(package.contains(#".executable(name: "Abakus", targets: ["Abakus"])"#))
    }
}
