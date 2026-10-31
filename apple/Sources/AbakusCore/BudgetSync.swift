import Foundation
import Observation

public enum SyncProblem: Hashable, Sendable {
    case clockAhead(String)
    case unsupportedProtocol(String)
    case failed(String)

    public var message: String {
        switch self {
        case .clockAhead(let message), .unsupportedProtocol(let message), .failed(let message): message
        }
    }
}

public enum SyncStatus: Hashable, Sendable {
    case notSignedIn
    /// Signed out in the web, or its refresh token no longer held; its copy and its unsent changes stay.
    case signedOutRemotely
    case inStep
    case offline
    case error(SyncProblem)
}

/// One loop syncs; its request without messages waits on the server and gives way to a command.
@MainActor
@Observable
public final class BudgetSync {
    public typealias Authorize = @MainActor (URL) async throws -> URL

    public private(set) var status: SyncStatus
    public private(set) var lastSync: Date?
    public private(set) var pendingChanges = 0
    public private(set) var isSigningIn = false
    public private(set) var signInError: String?

    @ObservationIgnored private let store: BudgetStore
    @ObservationIgnored private let database: BudgetDatabase
    @ObservationIgnored private let tokenStore: any TokenStoring
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var tokens: SyncTokens?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var interrupt: (() -> Void)?
    @ObservationIgnored private var interruptGeneration = 0
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var clockRefusedAt: Date?

    public init?(
        store: BudgetStore, tokens: any TokenStoring,
        transport: any HTTPTransport = URLSessionTransport(), deviceName: String,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        guard let database = store.database else { return nil }
        self.store = store
        self.database = database
        tokenStore = tokens
        self.transport = transport
        self.deviceName = deviceName
        self.now = now
        self.sleep = sleep
        let device = try? database.deviceId
        var signedIn = tokens.load()
        if signedIn != nil && signedIn?.deviceId != device {
            try? tokens.save(nil)
            signedIn = nil
        }
        self.tokens = signedIn
        status = signedIn != nil ? .inStep : device == BudgetDatabase.unsignedDevice ? .notSignedIn : .signedOutRemotely
        countPendingChanges()
        store.onChange = { [weak self] in self?.changed() }
    }

    public var isSignedIn: Bool { tokens != nil }

    public var serverURL: URL? { try? database.serverURL }

    /// Plain http only reaches this Mac: elsewhere it would carry the tokens and the budget in clear text.
    public static func serverURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host()
        else { return nil }
        switch scheme {
        case "https": return url
        case "http": return isLoopback(host) ? url : nil
        default: return nil
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return name == "localhost" || name.hasSuffix(".localhost") || name == "::1" || name.hasPrefix("127.")
    }

    private var server: AbakusServer? {
        serverURL.map { AbakusServer(url: $0, transport: transport) }
    }

    public func signIn(to url: URL, authorize: Authorize) async {
        guard !isSigningIn else { return }
        let server = AbakusServer(url: url, transport: transport)
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        do {
            let request = SignInRequest()
            let callback = try await authorize(request.authorizeURL(server: server.url, deviceName: deviceName))
            let code = try request.code(from: callback)
            let signedIn = try await server.exchange(code: code, verifier: request.verifier, now: now())
            let snapshot = try await server.snapshot(accessToken: signedIn.accessToken)
            try adopt(snapshot, from: server.url, as: signedIn)
        } catch SignInError.cancelled {
        } catch {
            signInError = Self.signInMessage(for: error)
        }
    }

    /// Unsent changes go out again under the new device when it signs in anew to the same server.
    private func adopt(_ snapshot: SyncSnapshot, from url: URL, as signedIn: SyncTokens) throws {
        let previousDevice = try database.deviceId
        let sameServer = try database.serverURL == url
        let pending = previousDevice != BudgetDatabase.unsignedDevice && sameServer ? try database.outbox() : []
        try? database.backUpBeforeSignIn()
        try store.adopt(snapshot, deviceId: signedIn.deviceId, serverURL: url, pending: pending)
        try tokenStore.save(signedIn)
        tokens = signedIn
        failures = 0
        lastSync = now()
        status = .inStep
        countPendingChanges()
    }

    public func signOut() async {
        let signedIn = tokens
        stop()
        tokens = nil
        try? tokenStore.save(nil)
        if let signedIn, let server { await server.revoke(signedIn) }
        try? store.signOut()
        lastSync = nil
        status = .notSignedIn
        countPendingChanges()
    }

    private static func signInMessage(for error: any Error) -> String {
        switch error {
        case SignInError.refused(let message): message
        case SyncError.offline: "Abakus ist nicht erreichbar. Prüfe die Adresse und die Verbindung."
        case SyncError.invalidGrant: "Die Anmeldung ist abgelaufen. Bitte melde dich noch einmal an."
        case let error as SyncError: problem(for: error).message
        default: error.localizedDescription
        }
    }

    /// Only this loop syncs, as each refresh token works once.
    public func start() {
        guard loop == nil, tokens != nil else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        interrupt?()
    }

    public func syncNow() {
        interrupt?()
    }

    private func changed() {
        countPendingChanges()
        syncNow()
    }

    private func run() async {
        while !Task.isCancelled, tokens != nil {
            let started = now()
            switch await syncOnce() {
            case .synced(let quiet):
                failures = 0
                if quiet && now().timeIntervalSince(started) < 1 { await pause(.seconds(1)) }
            case .failed:
                failures += 1
                await pause(.seconds(min(60, 1 << min(failures - 1, 6))))
            case .signedOut:
                loop = nil
                return
            }
        }
    }

    public enum Outcome: Hashable, Sendable {
        case synced(quiet: Bool)
        case failed
        case signedOut
    }

    /// One push and pull; a request without messages may wait on the server until another writer writes.
    @discardableResult
    public func syncOnce() async -> Outcome {
        guard let server, tokens != nil else { return .signedOut }
        do {
            return try await pushAndPull(server)
        } catch is CancellationError {
            return .synced(quiet: false)
        } catch SyncError.invalidGrant {
            signedOutRemotely()
            return .signedOut
        } catch SyncError.offline {
            status = .offline
            return .failed
        } catch let error as SyncError {
            if case .clockAhead(_, let serverTime) = error { clockRefusedAt = serverTime }
            status = .error(Self.problem(for: error))
            return .failed
        } catch {
            status = .error(.failed(error.localizedDescription))
            return .failed
        }
    }

    private func pushAndPull(_ server: AbakusServer) async throws -> Outcome {
        if let serverTime = clockRefusedAt, abs(now().timeIntervalSince(serverTime)) <= 300 {
            try database.restampFutureClocks(now: now())
            clockRefusedAt = nil
        }
        let cursor = try database.cursor
        let device = tokens?.deviceId
        var refusal: SyncError?
        let (sent, answer): ([SyncMessage], SyncAnswer)
        do {
            (sent, answer) = try await exchange(pushing: true, after: cursor, with: server)
        } catch let error as SyncError {
            guard case .invalidRequest = error else { throw error }
            refusal = error
            (sent, answer) = try await exchange(pushing: false, after: cursor, with: server)
        }
        guard self.tokens?.deviceId == device else { throw CancellationError() }
        try database.markSent(sent)
        if !answer.messages.isEmpty { try store.receive(answer.messages) }
        try database.setCursor(max(answer.cursor, try database.cursor))
        if !answer.more { store.pulled() }
        lastSync = now()
        status = refusal.map { .error(Self.problem(for: $0)) } ?? .inStep
        countPendingChanges()
        if refusal != nil { return .failed }
        if answer.more { return .synced(quiet: false) }
        return .synced(quiet: sent.isEmpty && answer.messages.isEmpty)
    }

    private func exchange(pushing: Bool, after cursor: Int, with server: AbakusServer) async throws
        -> (sent: [SyncMessage], answer: SyncAnswer)
    {
        do {
            return try await send(pushing: pushing, after: cursor, to: server, with: freshTokens(server))
        } catch SyncError.invalidToken {
            return try await send(pushing: pushing, after: cursor, to: server, with: refreshedTokens(server))
        }
    }

    /// The outbox is read only once the tokens are at hand, so a command made meanwhile does not wait.
    private func send(pushing: Bool, after cursor: Int, to server: AbakusServer, with tokens: SyncTokens)
        async throws -> (sent: [SyncMessage], answer: SyncAnswer)
    {
        let pending = pushing ? try database.outbox() : []
        let access = tokens.accessToken
        guard pending.isEmpty else {
            return (pending, try await server.sync(accessToken: access, cursor: cursor, messages: pending))
        }
        let answer = try await interruptibly {
            try await server.sync(accessToken: access, cursor: cursor, messages: [])
        }
        return ([], answer)
    }

    private func freshTokens(_ server: AbakusServer) async throws -> SyncTokens {
        guard let tokens else { throw SyncError.invalidGrant }
        if tokens.expiresAt.timeIntervalSince(now()) > 60 { return tokens }
        return try await refreshedTokens(server)
    }

    private func refreshedTokens(_ server: AbakusServer) async throws -> SyncTokens {
        guard let tokens else { throw SyncError.invalidGrant }
        var refreshed = try await server.refresh(tokens, now: now())
        guard self.tokens == tokens else { throw CancellationError() }
        refreshed.deviceId = tokens.deviceId
        self.tokens = refreshed
        try tokenStore.save(refreshed)
        return refreshed
    }

    private func signedOutRemotely() {
        tokens = nil
        try? tokenStore.save(nil)
        status = .signedOutRemotely
    }

    private func pause(_ duration: Duration) async {
        try? await interruptibly { [sleep] in try await sleep(duration) }
    }

    private func interruptibly<Value: Sendable>(_ work: @escaping @Sendable () async throws -> Value) async throws
        -> Value
    {
        let task = Task { try await work() }
        interruptGeneration += 1
        let current = interruptGeneration
        interrupt = { task.cancel() }
        defer { if interruptGeneration == current { interrupt = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func countPendingChanges() {
        pendingChanges = (try? database.pendingChanges) ?? 0
    }

    static func problem(for error: SyncError) -> SyncProblem {
        switch error {
        case .clockAhead(let message, _):
            .clockAhead(message ?? "Die Uhr dieses Mac geht vor. Bitte stelle sie richtig.")
        case .unsupportedProtocol(let message):
            .unsupportedProtocol(
                message ?? "Diese Version der App kann nicht mehr synchronisieren. Bitte aktualisiere sie.")
        case .invalidRequest(let detail), .refused(let detail): .failed(detail)
        case .offline: .failed("Abakus ist nicht erreichbar.")
        case .invalidToken, .invalidGrant: .failed("Die Anmeldung gilt nicht mehr.")
        }
    }
}
