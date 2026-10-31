import AppKit
import Testing

@Suite struct AppIconTests {
    private struct Document: Decodable {
        struct Specialization: Decodable { let appearance: String? }
        struct Group: Decodable { let layers: [Layer] }
        struct Layer: Decodable {
            let imageName: String
            enum CodingKeys: String, CodingKey { case imageName = "image-name" }
        }

        let fills: [Specialization]
        let groups: [Group]
        enum CodingKeys: String, CodingKey {
            case fills = "fill-specializations"
            case groups
        }
    }

    private static let bundle = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/Abakus/AppIcon.icon")

    private func document() throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(contentsOf: Self.bundle.appending(path: "icon.json")))
    }

    @Test func backgroundHasALightAndADarkVariant() throws {
        #expect(try document().fills.map(\.appearance) == [nil, "dark"])
    }

    @Test func layersAreFullResolutionSquareArtwork() throws {
        let layers = try document().groups.flatMap(\.layers)
        #expect(!layers.isEmpty)
        for layer in layers {
            let image = try #require(NSImageRep(contentsOf: Self.bundle.appending(path: "Assets/\(layer.imageName)")))
            #expect(image.pixelsWide == 1024 && image.pixelsHigh == 1024)
        }
    }
}
