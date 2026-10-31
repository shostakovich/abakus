import CryptoKit
import Foundation

public enum SignInError: Error, Hashable, Sendable {
    case cancelled
    case refused(String)
}

public struct SignInRequest: Sendable {
    public let verifier: String
    public let state: String

    public init(verifier: String = Self.randomText(), state: String = Self.randomText()) {
        self.verifier = verifier
        self.state = state
    }

    public var challenge: String {
        Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public func authorizeURL(server: URL, deviceName: String) -> URL {
        server.appending(path: "oauth/authorize").appending(queryItems: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: AbakusServer.clientId),
            URLQueryItem(name: "redirect_uri", value: AbakusServer.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "device_name", value: String(deviceName.prefix(60))),
        ])
    }

    public func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { throw SignInError.refused("Die Anmeldung passt nicht zu dieser Anfrage.") }
        if let error = value("error") {
            if error == "access_denied" { throw SignInError.cancelled }
            throw SignInError.refused("Abakus hat die Anmeldung abgelehnt (\(error)).")
        }
        guard let code = value("code"), !code.isEmpty else {
            throw SignInError.refused("Abakus hat keinen Anmeldecode geschickt.")
        }
        return code
    }

    public static func randomText() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
