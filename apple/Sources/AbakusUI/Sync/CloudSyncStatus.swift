import AbakusCore
import Foundation

public struct CloudSyncStatus: Hashable, Sendable {
    public let symbolName: String
    public let tooltip: String
    /// Only what the owner has to act on, not a passing outage.
    public let needsAttention: Bool

    public static func local(on device: DeviceKind) -> CloudSyncStatus {
        CloudSyncStatus(
            symbolName: "icloud.slash",
            tooltip: "Das Budget liegt nur auf \(device.dative) und wird nicht synchronisiert.")
    }

    init(symbolName: String, tooltip: String, needsAttention: Bool = false) {
        self.symbolName = symbolName
        self.tooltip = tooltip
        self.needsAttention = needsAttention
    }

    public init(_ status: SyncStatus, pendingChanges: Int, lastSync: Date?, on device: DeviceKind) {
        let last = lastSync.map { " Zuletzt synchronisiert: \(Self.moment($0))." } ?? ""
        switch status {
        case .notSignedIn:
            self = .local(on: device)
        case .signedOutRemotely:
            self.init(
                symbolName: "exclamationmark.icloud",
                tooltip:
                    "\(device.sentenceSubject) wurde in Abakus abgemeldet. Melde \(device.pronounAccusative) in den "
                    + "Einstellungen wieder an.",
                needsAttention: true)
        case .inStep:
            self.init(symbolName: "checkmark.icloud", tooltip: "Das Budget ist mit Abakus abgeglichen." + last)
        case .offline:
            self.init(
                symbolName: pendingChanges > 0 ? "arrow.clockwise.icloud" : "icloud",
                tooltip: "Abakus ist gerade nicht erreichbar." + Self.waiting(pendingChanges) + last)
        case .error(let problem):
            self.init(
                symbolName: "exclamationmark.icloud",
                tooltip: "Beim Synchronisieren ist ein Fehler aufgetreten: " + problem.message,
                needsAttention: true)
        }
    }

    static func changes(_ count: Int) -> String {
        count == 1 ? "1 Änderung" : "\(count) Änderungen"
    }

    private static func waiting(_ count: Int) -> String {
        guard count > 0 else { return "" }
        return " \(changes(count)) " + (count == 1 ? "wartet" : "warten") + " darauf, gesendet zu werden."
    }

    static func moment(_ date: Date) -> String {
        date.formatted(
            .dateTime.day(.twoDigits).month(.twoDigits).year().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                .locale(Locale(identifier: "de_DE")))
    }
}
