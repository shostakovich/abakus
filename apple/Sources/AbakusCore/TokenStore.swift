import Foundation
import Security

public protocol TokenStoring: AnyObject, Sendable {
    func load() -> SyncTokens?
    func save(_ tokens: SyncTokens?) throws
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let reason = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "Fehler \(status)"
        return "Der Schlüsselbund ließ sich nicht schreiben. \(reason)"
    }
}

/// The tokens of the signed-in device as one generic password, keyed by the database they sync.
public final class KeychainTokenStore: TokenStoring {
    private static let service = "local.abakus.sync"
    private let account: String

    public init(account: String) {
        self.account = account
    }

    /// An iOS app's container moves with each install, so the account is the database's path inside it.
    public static func account(forDatabaseAt url: URL, inContainer container: URL) -> String {
        let path = canonicalPath(url)
        let prefix = canonicalPath(container) + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.standardizedFileURL.path
    }

    /// The container may be named as /var and the database as /private/var, or the other way round.
    private static func canonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> SyncTokens? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(SyncTokens.self, from: data)
    }

    public func save(_ tokens: SyncTokens?) throws {
        guard let tokens else {
            let deleted = SecItemDelete(query as CFDictionary)
            guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
                throw KeychainError(status: deleted)
            }
            return
        }
        let data = try JSONEncoder().encode(tokens)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updated == errSecItemNotFound else {
            guard updated == errSecSuccess else { throw KeychainError(status: updated) }
            return
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }
}

public final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SyncTokens?

    public init(_ tokens: SyncTokens? = nil) {
        self.tokens = tokens
    }

    public func load() -> SyncTokens? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: SyncTokens?) throws {
        lock.withLock { self.tokens = tokens }
    }
}
