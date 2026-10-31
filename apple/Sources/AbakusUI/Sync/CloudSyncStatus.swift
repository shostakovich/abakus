import AbakusCore
import Foundation

public struct CloudSyncStatus: Hashable, Sendable {
    public let symbolName: String
    public let tooltip: String

    public static let local = CloudSyncStatus(
        symbolName: "icloud.slash", tooltip: "Das Budget liegt nur auf diesem Mac und wird nicht synchronisiert.")

    init(symbolName: String, tooltip: String) {
        self.symbolName = symbolName
        self.tooltip = tooltip
    }

    public init(_ status: SyncStatus, pendingChanges: Int, lastSync: Date?) {
        let last = lastSync.map { " Zuletzt synchronisiert: \(Self.moment($0))." } ?? ""
        switch status {
        case .notSignedIn:
            self = .local
        case .signedOutRemotely:
            self.init(
                symbolName: "exclamationmark.icloud",
                tooltip: "Dieser Mac wurde in Abakus abgemeldet. Melde ihn in den Einstellungen wieder an.")
        case .inStep:
            self.init(symbolName: "checkmark.icloud", tooltip: "Das Budget ist mit Abakus abgeglichen." + last)
        case .offline:
            self.init(
                symbolName: pendingChanges > 0 ? "arrow.clockwise.icloud" : "icloud",
                tooltip: "Abakus ist gerade nicht erreichbar." + Self.waiting(pendingChanges) + last)
        case .error(let problem):
            self.init(
                symbolName: "exclamationmark.icloud",
                tooltip: "Beim Synchronisieren ist ein Fehler aufgetreten: " + problem.message)
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
