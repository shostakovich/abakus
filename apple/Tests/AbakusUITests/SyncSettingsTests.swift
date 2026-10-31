import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

/// Signs in and serves a snapshot, or is unreachable.
private final class SignInServer: HTTPTransport, @unchecked Sendable {
    let snapshot: SyncSnapshot
    private let lock = NSLock()
    private var _offline = false

    init(budget: Budget) {
        snapshot = SyncSnapshot(
            cursor: 1, tables: budget.syncedRows.mapValues { $0.map { SyncSnapshot.Row(id: $0.key, fields: $0.value) } }
        )
    }

    var offline: Bool {
        get { lock.withLock { _offline } }
        set { lock.withLock { _offline = newValue } }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if offline { throw URLError(.notConnectedToInternet) }
        let body: Data =
            switch request.url?.path() {
            case "/oauth/token":
                Data(
                    #"{"access_token":"a","token_type":"Bearer","expires_in":3600,"refresh_token":"r","device_id":"mac-1"}"#
                        .utf8)
            case "/api/snapshot": try JSONEncoder().encode(snapshot)
            default: Data("{}".utf8)
            }
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
@Suite struct SyncSettingsTests {
    private let today = DateWithoutTime(year: 2026, month: 10, day: 23)

    private func confirm(_ url: URL) -> URL {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }
        return URL(string: "local.abakus:/oauth/callback?code=CODE&state=\(state?.value ?? "")")!
    }

    private func signedIn() async throws -> (BudgetStore, SyncSettingsModel, SignInServer) {
        var serverBudget = Budget(budgetName: "")
        serverBudget.accounts = [Account(id: "giro", name: "Girokonto", kind: .checking)]
        let server = SignInServer(budget: serverBudget)
        let store = try BudgetStore.open(BudgetDatabase(), today: { today })
        let made = BudgetSync(
            store: store, tokens: MemoryTokenStore(), transport: server, deviceName: "MacBook", sleep: { _ in })
        let sync = try #require(made)
        let model = SyncSettingsModel(sync: sync, authorize: { confirm($0) })
        model.serverAddress = "https://abakus.test/"
        await model.signInClicked()
        sync.stop()
        try #require(sync.isSignedIn)
        return (store, model, server)
    }

    @Test func signingInShowsTheBudgetFromAbakus() async throws {
        let (store, model, _) = try await signedIn()
        #expect(store.budget.accounts.map(\.name) == ["Girokonto"])
        #expect(model.serverAddress == "https://abakus.test")
        #expect(!model.canEditAddress)
        #expect(model.showsSignOut)
        #expect(!model.showsSignIn)
    }

    @Test func unsentChangesStayBehindWhenSigningInToAnotherServer() async throws {
        let (store, model, server) = try await signedIn()
        server.offline = true
        var account = try #require(store.budget.account(withId: "giro"))
        account.name = "Giro"
        try store.perform(.editAccount(account))
        server.offline = false

        model.serverAddress = "https://other.test"
        await model.signInClicked()
        model.sync.stop()

        #expect(model.sync.serverURL?.absoluteString == "https://other.test")
        #expect(try store.database?.outbox().isEmpty == true)
        #expect(model.sync.pendingChanges == 0)
    }

    @Test func anAddressWithoutSchemeIsRefused() async throws {
        let store = try BudgetStore.open(BudgetDatabase(), today: { today })
        let sync = try #require(BudgetSync(store: store, tokens: MemoryTokenStore(), deviceName: "MacBook"))
        let model = SyncSettingsModel(sync: sync, authorize: { $0 })
        model.serverAddress = "abakus.example.org"
        await model.signInClicked()
        #expect(model.addressError != nil)
        #expect(!sync.isSignedIn)
    }

    @Test func signingOutWithUnsentChangesWarnsFirst() async throws {
        let (store, model, server) = try await signedIn()
        server.offline = true
        for name in ["Giro", "Konto", "Girokonto 2"] {
            var account = try #require(store.budget.account(withId: "giro"))
            account.name = name
            try store.perform(.editAccount(account))
        }

        await model.signOutClicked()

        #expect(model.signOutWarning == 3)
        #expect(
            model.signOutWarningText
                == "3 Änderungen wurden noch nicht an Abakus gesendet und gehen beim Abmelden verloren.")
        #expect(store.budget.account(withId: "giro") != nil)

        await model.confirmSignOut()

        #expect(model.signOutWarning == nil)
        #expect(store.budget.budgetName == "Demo-Budget")
        #expect(model.sync.status == .notSignedIn)
    }

    @Test func signingOutWithoutUnsentChangesAsksNothing() async throws {
        let (store, model, _) = try await signedIn()
        await model.signOutClicked()
        #expect(model.signOutWarning == nil)
        #expect(store.budget.budgetName == "Demo-Budget")
    }

    @Test func aCancelledWarningKeepsTheBudget() async throws {
        let (store, model, server) = try await signedIn()
        server.offline = true
        var account = try #require(store.budget.account(withId: "giro"))
        account.name = "Giro"
        try store.perform(.editAccount(account))
        await model.signOutClicked()

        model.cancelSignOut()

        #expect(model.signOutWarning == nil)
        #expect(store.budget.account(withId: "giro")?.name == "Giro")
        #expect(model.sync.isSignedIn)
    }
}
