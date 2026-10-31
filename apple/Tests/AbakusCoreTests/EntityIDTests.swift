import AbakusCore
import Foundation
import Testing

@Suite struct EntityIDTests {
    private let id = "01890a5d-ac96-774b-bcce-b302099a8057"
    private let november = DateWithoutTime(year: 2026, month: 11, day: 1)

    @Test func rowsWithANaturalKeyGetTheProtocolsNameBasedIds() {
        #expect(EntityID.assignment(categoryId: id, month: november) == "6acb0211-c88e-59b4-baca-87f0fe072024")
        #expect(EntityID.targetSnooze(categoryId: id, month: november) == "40ec28ed-8c55-5958-9143-194ff78e701e")
        #expect(EntityID.targetVersion(categoryId: id, fromMonth: november) == "dbbd70b6-fe59-5ed4-b545-d4b106935aee")
        #expect(EntityID.transferPayee(accountId: id) == "e884f20e-330e-5cd4-adbd-a7bbed724916")
        #expect(
            EntityID.enteredTransaction(scheduledId: id, date: DateWithoutTime(year: 2026, month: 12, day: 1))
                == "28bca64b-3fac-52b1-8dde-6a7a1ce968b0")
        #expect(
            EntityID.enteredSubtransaction(transactionId: "28bca64b-3fac-52b1-8dde-6a7a1ce968b0", position: 0)
                == "14ba82c4-51c1-5ecd-ba82-b995012c3b39")
        #expect(EntityID.transferCounterpart(of: id) == "9c88c356-e185-5efa-b9f0-818a4644aebf")
    }

    @Test func monthsAreTheirFirstDayAndIdsLowercase() {
        let midMonth = DateWithoutTime(year: 2026, month: 11, day: 17)
        #expect(
            EntityID.assignment(categoryId: id, month: midMonth) == EntityID.assignment(categoryId: id, month: november)
        )
        #expect(
            EntityID.assignment(categoryId: id.uppercased(), month: november)
                == EntityID.assignment(categoryId: id, month: november))
    }

    @Test func newRowsGetUUIDv7WithTheTimeInFront() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000.123)
        let made = EntityID.createUID(now: now)
        let uuid = try #require(UUID(uuidString: made))
        #expect(made == made.lowercased() && made.count == 36)
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        let millis = bytes[0..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        #expect(millis == 1_700_000_000_123)
        #expect(bytes[6] >> 4 == 7)
        #expect(bytes[8] >> 6 == 0b10)
        #expect(EntityID.createUID(now: now) != made)
    }
}
