import Foundation

/// The device the app runs on, as the texts about it name it.
public struct DeviceKind: Hashable, Sendable {
    public let name: String
    let nominative: String
    let accusative: String
    let dative: String
    let pronounAccusative: String

    public static let mac = DeviceKind(
        name: "Mac", nominative: "dieser Mac", accusative: "diesen Mac", dative: "diesem Mac", pronounAccusative: "ihn")
    public static let iPhone = DeviceKind(
        name: "iPhone", nominative: "dieses iPhone", accusative: "dieses iPhone", dative: "diesem iPhone",
        pronounAccusative: "es")
    public static let iPad = DeviceKind(
        name: "iPad", nominative: "dieses iPad", accusative: "dieses iPad", dative: "diesem iPad",
        pronounAccusative: "es")

    var sentenceSubject: String { nominative.prefix(1).uppercased() + nominative.dropFirst() }
}
