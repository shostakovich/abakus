import AbakusCore
import Foundation
import Observation

@MainActor
@Observable
public final class SyncSettingsModel {
    public let sync: BudgetSync
    public var serverAddress: String
    public private(set) var addressError: String?
    /// The unsent changes signing out would lose, while the owner is asked.
    public private(set) var signOutWarning: Int?
    @ObservationIgnored private let authorize: BudgetSync.Authorize

    public init(sync: BudgetSync, authorize: @escaping BudgetSync.Authorize = WebSignIn.authorize) {
        self.sync = sync
        self.authorize = authorize
        serverAddress = sync.serverURL?.absoluteString ?? ""
    }

    public var canEditAddress: Bool { !sync.isSignedIn && !sync.isSigningIn }
    public var showsSignIn: Bool { !sync.isSignedIn }
    public var canSignIn: Bool { !sync.isSigningIn && !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty }
    public var showsSignOut: Bool { sync.isSignedIn || sync.status == .signedOutRemotely }

    public var statusText: String {
        switch sync.status {
        case .notSignedIn:
            "Melde diesen Mac bei Abakus an, um dein Budget zu synchronisieren. Bis dahin zeigt er ein Demo-Budget."
        case .signedOutRemotely:
            "Dieser Mac wurde in Abakus abgemeldet. Melde ihn wieder an, um weiter zu synchronisieren; bis dahin "
                + "bleiben das Budget und \(unsent) auf diesem Mac."
        case .inStep, .offline, .error:
            CloudSyncStatus(sync.status, pendingChanges: sync.pendingChanges, lastSync: sync.lastSync).tooltip
        }
    }

    private var unsent: String {
        sync.pendingChanges == 0 ? "keine ungesendeten Änderungen" : CloudSyncStatus.changes(sync.pendingChanges)
    }

    public var signOutWarningText: String {
        let count = signOutWarning ?? 0
        let (sent, lost) = count == 1 ? ("wurde", "geht") : ("wurden", "gehen")
        return "\(CloudSyncStatus.changes(count)) \(sent) noch nicht an Abakus gesendet und \(lost) beim Abmelden "
            + "verloren."
    }

    public func signInClicked() async {
        guard let url = BudgetSync.serverURL(from: serverAddress) else {
            addressError = "Gib die Adresse von Abakus mit https:// an, etwa https://abakus.example.org."
            return
        }
        addressError = nil
        serverAddress = url.absoluteString
        await sync.signIn(to: url, authorize: authorize)
        if sync.isSignedIn { sync.start() }
    }

    public func signOutClicked() async {
        let pending = sync.pendingChanges
        guard pending == 0 else {
            signOutWarning = pending
            return
        }
        await sync.signOut()
    }

    public func confirmSignOut() async {
        signOutWarning = nil
        await sync.signOut()
    }

    public func cancelSignOut() {
        signOutWarning = nil
    }
}
