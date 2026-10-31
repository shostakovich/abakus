import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public struct SyncTokens: Codable, Hashable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var deviceId: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, deviceId: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.deviceId = deviceId
    }
}

public struct SyncAnswer: Hashable, Sendable, Decodable {
    public var cursor: Int
    public var messages: [SyncMessage]
    public var more: Bool
}

public struct SyncSnapshot: Hashable, Sendable, Codable {
    public struct Row: Hashable, Sendable, Codable {
        public var id: String
        public var fields: [String: SyncValue]
        public var clocks: [String: String]

        public init(id: String, fields: [String: SyncValue], clocks: [String: String] = [:]) {
            self.id = id
            self.fields = fields
            self.clocks = clocks
        }
    }

    public var cursor: Int
    public var tables: [String: [Row]]

    public init(cursor: Int, tables: [String: [Row]]) {
        self.cursor = cursor
        self.tables = tables
    }
}

public enum SyncError: Error, Hashable, Sendable {
    case offline
    /// The access token no longer holds; a refresh may still.
    case invalidToken
    /// The code or refresh token no longer holds: the device is signed out.
    case invalidGrant
    case clockAhead(message: String?, serverTime: Date?)
    case unsupportedProtocol(message: String?)
    case invalidRequest(String)
    case refused(String)
}

public struct AbakusServer: Sendable {
    public static let clientId = "abakus-apple"
    public static let callbackScheme = "local.abakus"
    public static let redirectURI = "local.abakus:/oauth/callback"
    public static let protocolVersion = 1

    public let url: URL
    private let transport: any HTTPTransport

    public init(url: URL, transport: any HTTPTransport = URLSessionTransport()) {
        self.url = url
        self.transport = transport
    }

    public func exchange(code: String, verifier: String, now: Date) async throws -> SyncTokens {
        try await token(
            [
                "grant_type": "authorization_code", "client_id": Self.clientId, "code": code,
                "code_verifier": verifier, "redirect_uri": Self.redirectURI,
            ], now: now)
    }

    public func refresh(_ tokens: SyncTokens, now: Date) async throws -> SyncTokens {
        try await token(
            ["grant_type": "refresh_token", "client_id": Self.clientId, "refresh_token": tokens.refreshToken],
            now: now)
    }

    /// Answers alike whether or not the token still held, so failures are of no interest.
    public func revoke(_ tokens: SyncTokens) async {
        var request = URLRequest(url: url.appending(path: "oauth/revoke"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["client_id": Self.clientId, "token": tokens.refreshToken])
        _ = try? await transport.send(request)
    }

    public func snapshot(accessToken: String) async throws -> SyncSnapshot {
        var request = apiRequest("api/snapshot", accessToken: accessToken)
        request.httpMethod = "GET"
        return try await decode(SyncSnapshot.self, from: send(request))
    }

    public func sync(accessToken: String, cursor: Int, messages: [SyncMessage]) async throws -> SyncAnswer {
        var request = apiRequest("api/sync", accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SyncPush(cursor: cursor, messages: messages))
        request.timeoutInterval = 60
        return try await decode(SyncAnswer.self, from: send(request))
    }

    private func apiRequest(_ path: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url.appending(path: path))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(String(Self.protocolVersion), forHTTPHeaderField: "Abakus-Protocol")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func token(_ parameters: [String: String], now: Date) async throws -> SyncTokens {
        var request = URLRequest(url: url.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.form(parameters)
        let answer = try await decode(TokenAnswer.self, from: send(request))
        return SyncTokens(
            accessToken: answer.accessToken, refreshToken: answer.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(answer.expiresIn)), deviceId: answer.deviceId)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where Self.insecure.contains(error.code) {
            throw SyncError.refused(
                "Abakus ließ sich nicht sicher erreichen. Prüfe, ob die Adresse mit https:// beginnt und das "
                    + "Zertifikat des Servers gültig ist.")
        } catch is URLError {
            throw SyncError.offline
        }
        guard (200..<300).contains(response.statusCode) else { throw Self.error(data, response) }
        return (data, response)
    }

    private static let insecure: Set<URLError.Code> = [
        .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed, .serverCertificateHasBadDate,
        .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
        .clientCertificateRejected, .clientCertificateRequired,
    ]

    private func decode<Answer: Decodable>(_ type: Answer.Type, from sent: (Data, HTTPURLResponse)) throws -> Answer {
        do {
            return try JSONDecoder().decode(type, from: sent.0)
        } catch {
            throw SyncError.refused("Die Antwort von Abakus ließ sich nicht lesen.")
        }
    }

    private static func error(_ data: Data, _ response: HTTPURLResponse) -> SyncError {
        let body = try? JSONDecoder().decode(ErrorAnswer.self, from: data)
        switch body?.error {
        case "invalid_token": return .invalidToken
        case "invalid_grant": return .invalidGrant
        case "clock_ahead":
            return .clockAhead(message: body?.message, serverTime: body?.serverTime.flatMap(SyncFormat.moment))
        case "unsupported_protocol": return .unsupportedProtocol(message: body?.message)
        case "invalid_request": return .invalidRequest(body?.detail ?? "Abakus hat die Anfrage abgelehnt.")
        default:
            if response.statusCode == 401 { return .invalidToken }
            return .refused(body?.detail ?? body?.error ?? "Abakus antwortete mit Status \(response.statusCode).")
        }
    }

    private static func form(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = parameters.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}

private struct SyncPush: Encodable {
    var cursor: Int
    var messages: [SyncMessage]
}

private struct TokenAnswer: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
    var deviceId: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case deviceId = "device_id"
    }
}

private struct ErrorAnswer: Decodable {
    var error: String
    var message: String?
    var detail: String?
    var serverTime: String?

    enum CodingKeys: String, CodingKey {
        case error, message, detail
        case serverTime = "server_time"
    }
}
