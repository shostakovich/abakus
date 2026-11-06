import CoreGraphics
import Testing

@testable import AbakusUI

@Suite struct RegisterTouchTableTests {
    static let account: [RegisterColumn] = [.date, .payee, .category, .memo, .amount, .cleared]

    @Test func theStatusComesLastAndTheSchedulersRepeatStaysOut() {
        let table = RegisterTouchTable(visibleColumns: [.cleared, .date, .repeats, .payee, .amount])
        #expect(table.columns == [.date, .payee, .amount, .cleared])
    }

    @Test func theTextsShareWhatTheFixedColumnsLeave() {
        let table = RegisterTouchTable(visibleColumns: Self.account)
        let widths = table.widths(in: 716)
        #expect(widths == [52, 210, 180, 90, 92, 32])
        #expect(widths.reduce(0, +) + 5 * RegisterTouchTable.spacing == 716)
    }

    @Test(arguments: [(CGFloat(716), true), (524, true), (523, false), (412, false)])
    func theTableFitsWhileEveryTextKeepsItsMinimum(width: CGFloat, fits: Bool) {
        #expect(RegisterTouchTable(visibleColumns: Self.account).fits(in: width) == fits)
    }

    @Test func hidingTheMemoLetsTheTableFitANarrowerWidth() {
        let withoutMemo = Self.account.filter { $0 != .memo }
        #expect(!RegisterTouchTable(visibleColumns: Self.account).fits(in: 500))
        #expect(RegisterTouchTable(visibleColumns: withoutMemo).fits(in: 500))
    }

    @Test func largerTextNeedsMoreWidth() {
        #expect(RegisterTouchTable(visibleColumns: Self.account).fits(in: 600))
        #expect(!RegisterTouchTable(visibleColumns: Self.account, scale: 1.4).fits(in: 600))
    }
}
