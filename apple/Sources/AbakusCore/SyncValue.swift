import Foundation

public enum SyncValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case integer(Int)
    case text(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        }
    }

    public var isNull: Bool { self == .null }

    var text: String? {
        if case .text(let value) = self { value } else { nil }
    }

    var integer: Int? {
        if case .integer(let value) = self { value } else { nil }
    }

    var bool: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    static func of(_ value: String?) -> SyncValue {
        value.map(SyncValue.text) ?? .null
    }

    static func of(_ value: Int?) -> SyncValue {
        value.map(SyncValue.integer) ?? .null
    }

    static func cents(_ amount: Decimal) -> SyncValue {
        .integer(SyncFormat.cents(amount))
    }

    static func date(_ date: DateWithoutTime?) -> SyncValue {
        of(date?.description)
    }

    static func moment(_ moment: Date?) -> SyncValue {
        of(moment.map(SyncFormat.moment))
    }

    static func of<Value: RawRepresentable>(_ value: Value?) -> SyncValue where Value.RawValue == String {
        of(value?.rawValue)
    }
}

enum SyncFormat {
    static func cents(_ amount: Decimal) -> Int {
        NSDecimalNumber(decimal: Amount.round(amount) * 100).intValue
    }

    static func amount(cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// ISO 8601 UTC with microseconds, as Abakus writes moments.
    static func moment(_ date: Date) -> String {
        let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
        let seconds = micros >= 0 ? micros / 1_000_000 : (micros - 999_999) / 1_000_000
        let fraction = micros - seconds * 1_000_000
        let whole = Date(timeIntervalSince1970: TimeInterval(seconds))
        let text = wholeSeconds.string(from: whole)
        return String(text.dropLast()) + "." + String(format: "%06lld", fraction) + "Z"
    }

    static func moment(_ text: String) -> Date? {
        guard text.hasSuffix("Z") else { return nil }
        let body = text.dropLast()
        let parts = body.split(separator: ".", maxSplits: 1)
        guard let whole = wholeSeconds.date(from: parts[0] + "Z") else { return nil }
        guard parts.count == 2 else { return whole }
        let digits = parts[1]
        guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy(\.isASCII), let value = Int64(digits) else {
            return nil
        }
        let micros = Double(value) * pow(10, Double(6 - digits.count))
        return Date(timeIntervalSince1970: whole.timeIntervalSince1970 + micros.rounded() / 1_000_000)
    }

    nonisolated(unsafe) private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

public typealias SyncRow = [String: SyncValue]

extension Dictionary where Key == String, Value == SyncValue {
    func text(_ column: String) -> String? { self[column]?.text }
    func integer(_ column: String) -> Int? { self[column]?.integer }
    func bool(_ column: String) -> Bool? { self[column]?.bool }
    func date(_ column: String) -> DateWithoutTime? { text(column).flatMap(DateWithoutTime.init(string:)) }
    func moment(_ column: String) -> Date? { text(column).flatMap(SyncFormat.moment) }
    func amount(_ column: String) -> Decimal? { integer(column).map(SyncFormat.amount(cents:)) }

    func enumValue<Raw: RawRepresentable>(_ column: String, as type: Raw.Type = Raw.self) -> Raw?
    where Raw.RawValue == String {
        text(column).flatMap(Raw.init(rawValue:))
    }

    var isDeleted: Bool { self["deleted_at"].map { !$0.isNull } ?? false }
}
