import Foundation

/// The device the app runs on, as the texts about it name it.
public struct DeviceKind: Hashable, Sendable {
    public let name: String
    let nominative: String
    let accusative: String
    let dative: String
    let pronoun: String
    let pronounAccusative: String
    let yourGenitive: String

    public static let mac = DeviceKind(
        name: "Mac", nominative: "dieser Mac", accusative: "diesen Mac", dative: "diesem Mac", pronoun: "er",
        pronounAccusative: "ihn", yourGenitive: "deines Mac")
    public static let iPhone = DeviceKind(
        name: "iPhone", nominative: "dieses iPhone", accusative: "dieses iPhone", dative: "diesem iPhone",
        pronoun: "es", pronounAccusative: "es", yourGenitive: "deines iPhones")
    public static let iPad = DeviceKind(
        name: "iPad", nominative: "dieses iPad", accusative: "dieses iPad", dative: "diesem iPad", pronoun: "es",
        pronounAccusative: "es", yourGenitive: "deines iPads")

    var sentenceSubject: String { nominative.prefix(1).uppercased() + nominative.dropFirst() }
}
