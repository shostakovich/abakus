import Foundation

/// The hybrid logical clock of `sync/PROTOCOL.md`; its text sorts like the clock.
public struct SyncClock: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let millis: Int64
    public let counter: Int
    public let device: String

    public init(millis: Int64, counter: Int, device: String) {
        self.millis = millis
        self.counter = counter
        self.device = device
    }

    public static func tick(after last: SyncClock?, now: Date, device: String) -> SyncClock {
        let wall = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        guard let last, wall <= last.millis else { return SyncClock(millis: wall, counter: 0, device: device) }
        guard last.counter < 0xffff else { return SyncClock(millis: last.millis + 1, counter: 0, device: device) }
        return SyncClock(millis: last.millis, counter: last.counter + 1, device: device)
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "-", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 5, let counter = Int(parts[3], radix: 16), parts[3].count == 4,
            let time = SyncFormat.moment(parts[0...2].joined(separator: "-"))
        else { return nil }
        let device = String(parts[4])
        guard !device.isEmpty, device.unicodeScalars.allSatisfy(Self.isDeviceCharacter) else { return nil }
        self.init(millis: Int64((time.timeIntervalSince1970 * 1000).rounded()), counter: counter, device: device)
        guard description == text else { return nil }
    }

    public var description: String {
        let time = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let moment = SyncFormat.moment(time)
        let hex = String(counter, radix: 16)
        return String(moment.prefix(23)) + "Z-" + String(repeating: "0", count: max(4 - hex.count, 0)) + hex + "-"
            + device
    }

    public static func < (lhs: SyncClock, rhs: SyncClock) -> Bool {
        (lhs.millis, lhs.counter, lhs.device) < (rhs.millis, rhs.counter, rhs.device)
    }

    private static func isDeviceCharacter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
    }
}

public struct SyncMessage: Hashable, Sendable, Codable {
    public var table: String
    public var rowId: String
    public var column: String
    public var value: SyncValue
    public var clock: String

    public init(table: String, rowId: String, column: String, value: SyncValue, clock: String) {
        self.table = table
        self.rowId = rowId
        self.column = column
        self.value = value
        self.clock = clock
    }

    /// The same change under another device's clock, as after signing in anew.
    func restamped(for device: String) -> SyncMessage? {
        guard let old = SyncClock(clock) else { return nil }
        var message = self
        message.clock = SyncClock(millis: old.millis, counter: old.counter, device: device).description
        return message
    }

    private enum CodingKeys: String, CodingKey {
        case table
        case rowId = "row_id"
        case column, value, clock
    }
}
