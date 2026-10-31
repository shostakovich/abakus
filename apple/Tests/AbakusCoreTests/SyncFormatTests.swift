import Foundation
import Testing

@testable import AbakusCore

@Suite struct SyncFormatTests {
    @Test func valuesKeepTheirJSONType() throws {
        let decoded = try JSONDecoder().decode([SyncValue].self, from: Data(#"[0, 1, true, null, "x", -4210]"#.utf8))
        #expect(decoded == [.integer(0), .integer(1), .bool(true), .null, .text("x"), .integer(-4210)])
    }

    @Test func momentsAreUTCWithMicroseconds() throws {
        let text = "2026-11-02T10:00:00.123456Z"
        let moment = try #require(SyncFormat.moment(text))
        #expect(SyncFormat.moment(moment) == text)
        #expect(SyncFormat.moment("2026-11-02T10:00:00Z").map(SyncFormat.moment) == "2026-11-02T10:00:00.000000Z")
    }

    @Test func amountsAreCents() {
        #expect(SyncFormat.cents(decimal("-42.10")) == -4210)
        #expect(SyncFormat.amount(cents: -4210) == decimal("-42.10"))
    }

    @Test func aClockReadsAsItIsWritten() throws {
        let clock = try #require(SyncClock("2026-11-02T10:00:00.000Z-00ff-mac-mini"))
        #expect(clock.counter == 255)
        #expect(clock.device == "mac-mini")
        #expect(clock.description == "2026-11-02T10:00:00.000Z-00ff-mac-mini")
        #expect(SyncClock("2026-11-02T10:00:00.000Z-0000-Mac") == nil)
        #expect(SyncClock("2026-11-02T10:00:00Z-0000-mac") == nil)
    }

    @Test func aClockTicksPastTheNewestItKnows() throws {
        let newest = try #require(SyncClock("2026-11-02T10:00:00.000Z-0003-web"))
        let earlier = try #require(SyncFormat.moment("2026-11-02T09:59:00Z"))
        let later = try #require(SyncFormat.moment("2026-11-02T10:01:00Z"))
        #expect(
            SyncClock.tick(after: newest, now: earlier, device: "mac").description
                == "2026-11-02T10:00:00.000Z-0004-mac")
        #expect(
            SyncClock.tick(after: newest, now: later, device: "mac").description == "2026-11-02T10:01:00.000Z-0000-mac")
        #expect(newest < SyncClock.tick(after: newest, now: earlier, device: "mac"))
    }

    @Test func aFullCounterMovesOnToTheNextMillisecond() throws {
        let full = try #require(SyncClock("2026-11-02T10:00:00.000Z-ffff-web"))
        let earlier = try #require(SyncFormat.moment("2026-11-02T09:59:00Z"))
        #expect(
            SyncClock.tick(after: full, now: earlier, device: "mac").description
                == "2026-11-02T10:00:00.001Z-0000-mac")
    }

    @Test func aChainOfSuccessorsEndsAtALiveRowOrTheSmallestIdOfItsCycle() {
        let chain = SuccessorChain(["a": "b", "b": "c", "x": "y", "y": "x"])
        #expect(chain("a") == "c")
        #expect(chain("c") == "c")
        #expect(chain("y") == "x")
        #expect(chain(nil) == nil)
    }
}
