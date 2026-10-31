import AbakusCore
import Foundation

/// Abakus's sign-in and sync API over a fake transport: it keeps every writer's messages and numbers them.
final class FakeAbakus: HTTPTransport, @unchecked Sendable {
    struct Stored {
        var number: Int
        var device: String
        var message: SyncMessage
    }

    static let url = URL(string: "https://abakus.test")!

    private let lock = NSLock()
    private var log: [Stored] = []
    private var accessTokens: [String: String] = [:]
    private var refreshTokens: [String: String] = [:]
    private var issued = 0
    private var _snapshot = SyncSnapshot(cursor: 0, tables: [:])
    private var _offline = false
    private var _refusesTokens = false
    private var _clockAhead = false
    private var _speaksProtocol = true
    private var _waits = false
    private var _refusesPushes = false
    private var _failure: URLError.Code?
    private var _holdsRefreshes = false
    private var _requests: [URLRequest] = []

    var deviceId = "mac-1"
    /// Like the server's 1000: an answer reads at most this many messages.
    var pageSize = 1000

    var snapshot: SyncSnapshot {
        get { lock.withLock { _snapshot } }
        set { lock.withLock { _snapshot = newValue } }
    }
    var offline: Bool {
        get { lock.withLock { _offline } }
        set { lock.withLock { _offline = newValue } }
    }
    /// Every token stops working, as when the device is signed out in the web.
    var refusesTokens: Bool {
        get { lock.withLock { _refusesTokens } }
        set { lock.withLock { _refusesTokens = newValue } }
    }
    var clockAhead: Bool {
        get { lock.withLock { _clockAhead } }
        set { lock.withLock { _clockAhead = newValue } }
    }
    var speaksProtocol: Bool {
        get { lock.withLock { _speaksProtocol } }
        set { lock.withLock { _speaksProtocol = newValue } }
    }
    /// A request without messages that finds nothing new waits for another writer, as the server does.
    var waits: Bool {
        get { lock.withLock { _waits } }
        set { lock.withLock { _waits = newValue } }
    }
    /// Every request fails with this error before it reaches the server.
    var failure: URLError.Code? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }
    /// A refresh waits until this is false again.
    var holdsRefreshes: Bool {
        get { lock.withLock { _holdsRefreshes } }
        set { lock.withLock { _holdsRefreshes = newValue } }
    }
    var refreshRequested: Bool {
        requests.contains { $0.url?.path() == "/oauth/token" && form($0)["grant_type"] == "refresh_token" }
    }
    var refusesPushes: Bool {
        get { lock.withLock { _refusesPushes } }
        set { lock.withLock { _refusesPushes = newValue } }
    }
    var requests: [URLRequest] { lock.withLock { _requests } }

    func messages(from device: String) -> [SyncMessage] {
        lock.withLock { log.filter { $0.device == device }.map(\.message) }
    }

    func write(_ messages: [SyncMessage], from device: String = "web") {
        lock.withLock { append(messages, from: device) }
    }

    private func append(_ messages: [SyncMessage], from device: String) {
        for message in messages {
            log.append(Stored(number: (log.last?.number ?? _snapshot.cursor) + 1, device: device, message: message))
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        if offline { throw URLError(.notConnectedToInternet) }
        if let failure { throw URLError(failure) }
        let path = request.url?.path() ?? ""
        switch path {
        case "/oauth/token":
            let form = form(request)
            while form["grant_type"] == "refresh_token" && holdsRefreshes {
                try await Task.sleep(for: .milliseconds(5))
            }
            return token(form)
        case "/oauth/revoke": return answer(200, [:])
        case "/api/snapshot", "/api/sync":
            guard let device = device(of: request) else { return answer(401, ["error": "invalid_token"]) }
            guard request.value(forHTTPHeaderField: "Abakus-Protocol") == "1", speaksProtocol else {
                return answer(
                    400, ["error": "unsupported_protocol", "supported": [2], "message": "Bitte aktualisieren."])
            }
            if path == "/api/snapshot" { return try json(200, snapshot) }
            return try await sync(request, from: device)
        default: return answer(404, ["error": "not_found"])
        }
    }

    private func device(of request: URLRequest) -> String? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer ") else {
            return nil
        }
        return lock.withLock { _refusesTokens ? nil : accessTokens[String(header.dropFirst(7))] }
    }

    private func sync(_ request: URLRequest, from device: String) async throws -> (Data, HTTPURLResponse) {
        let push = try JSONDecoder().decode(Push.self, from: request.httpBody ?? Data())
        let latest = Date().addingTimeInterval(300)
        let ahead = push.messages.contains { message in
            SyncClock(message.clock).map { Double($0.millis) / 1000 > latest.timeIntervalSince1970 } ?? false
        }
        if (clockAhead || ahead) && !push.messages.isEmpty {
            let time = ISO8601DateFormatter.string(
                from: Date(), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
            return answer(
                400, ["error": "clock_ahead", "server_time": time, "message": "Die Uhr geht vor."])
        }
        guard push.messages.allSatisfy({ $0.clock.hasSuffix("-" + device) }), !refusesPushes || push.messages.isEmpty
        else {
            return answer(400, ["error": "invalid_request", "detail": "foreign clock"])
        }
        lock.withLock { append(push.messages, from: device) }
        while push.messages.isEmpty && waits && pulled(after: push.cursor, for: device).messages.isEmpty {
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                throw URLError(.cancelled)
            }
        }
        let pulled = pulled(after: push.cursor, for: device)
        return try json(200, Answer(cursor: pulled.cursor, messages: pulled.messages, more: pulled.more))
    }

    private func pulled(after cursor: Int, for device: String) -> (cursor: Int, messages: [SyncMessage], more: Bool) {
        lock.withLock {
            let after = log.filter { $0.number > cursor }
            let read = after.prefix(pageSize)
            return (
                read.last?.number ?? cursor, read.filter { $0.device != device }.map(\.message), after.count > pageSize
            )
        }
    }

    private func token(_ form: [String: String]) -> (Data, HTTPURLResponse) {
        lock.withLock {
            switch form["grant_type"] {
            case "authorization_code" where form["code"] == "CODE" && form["code_verifier"]?.count ?? 0 >= 43:
                return issue(for: deviceId)
            case "refresh_token":
                guard !_refusesTokens, let device = refreshTokens.removeValue(forKey: form["refresh_token"] ?? "")
                else { return answer(400, ["error": "invalid_grant"]) }
                return issue(for: device)
            default:
                return answer(400, ["error": "invalid_grant"])
            }
        }
    }

    private func issue(for device: String) -> (Data, HTTPURLResponse) {
        issued += 1
        accessTokens["access-\(issued)"] = device
        refreshTokens["refresh-\(issued)"] = device
        return answer(
            200,
            [
                "access_token": "access-\(issued)", "token_type": "Bearer", "expires_in": 3600,
                "refresh_token": "refresh-\(issued)", "device_id": device,
            ])
    }

    /// Lets the next access token run out at once.
    func expireAccessTokens() {
        lock.withLock { accessTokens.removeAll() }
    }

    private func form(_ request: URLRequest) -> [String: String] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    private func answer(_ status: Int, _ body: [String: Any]) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return (data, HTTPURLResponse(url: Self.url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func json(_ status: Int, _ body: some Encodable) throws -> (Data, HTTPURLResponse) {
        (
            try JSONEncoder().encode(body),
            HTTPURLResponse(url: Self.url, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }

    private struct Push: Decodable {
        var cursor: Int
        var messages: [SyncMessage]
    }

    private struct Answer: Encodable {
        var cursor: Int
        var messages: [SyncMessage]
        var more: Bool
    }
}

extension SyncSnapshot {
    init(of budget: Budget, cursor: Int = 0) {
        self.init(
            cursor: cursor,
            tables: budget.syncedRows.mapValues { rows in rows.map { Row(id: $0.key, fields: $0.value) } })
    }
}
