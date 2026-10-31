import AbakusCore
import CoreGraphics
import Testing

@testable import AbakusUI

private let singleAccountColumns: [RegisterColumn] = [
    .date, .payee, .errorState, .category, .memo, .outflow, .inflow, .cleared,
]

private func widths(_ gridWidth: CGFloat, _ columns: [RegisterColumn] = singleAccountColumns)
    -> [RegisterColumn: CGFloat]
{
    let values = RegisterColumnLayout.widths(
        gridWidth: gridWidth, visibleColumns: columns, settings: RegisterColumnSettings())
    return Dictionary(uniqueKeysWithValues: zip(columns, values))
}

@Suite struct RegisterColumnLayoutTests {
    @Test(arguments: [(800, 226.6, 30.8), (1000, 312.9, 58.3), (1400, 486.4, 111.2)])
    func flexibleColumnsShareTheRoomLeftOfTheFixedOnes(gridWidth: CGFloat, payee: CGFloat, memo: CGFloat) {
        let result = widths(gridWidth)
        #expect(abs(result[.payee]! - payee) < 0.1)
        #expect(abs(result[.category]! - payee) < 0.1)
        #expect(abs(result[.memo]! - memo) < 0.1)
    }

    @Test func fixedColumnsUseTheirMinimumWidth() {
        let result = widths(1000)
        #expect(result[.date] == 92)
        #expect(result[.errorState] == 32)
        #expect(result[.outflow] == 70)
        #expect(result[.inflow] == 70)
        #expect(result[.cleared] == 32)
    }

    @Test func columnsFillTheDisplayWidthLeftOfTheColumnMenu() {
        let total = widths(1000).values.reduce(0, +)
        #expect(abs(total - 980) < 0.001)
    }

    @Test func hiddenErrorColumnGivesItsWidthToTheFlexibleColumns() {
        let result = widths(733, singleAccountColumns.filter { $0 != .errorState })
        #expect(abs(result[.payee]! - 205.3) < 0.1)
        #expect(abs(result[.memo]! - 38.4) < 0.1)
    }

    @Test func framesAreContiguousOnWholePoints() {
        let layout = RegisterColumnLayout(
            gridWidth: 1000, visibleColumns: singleAccountColumns, settings: RegisterColumnSettings())
        #expect(layout.frames.first?.x == 0)
        for (left, right) in zip(layout.frames, layout.frames.dropFirst()) {
            #expect(left.maxX == right.x)
            #expect(right.x == right.x.rounded())
        }
        #expect(layout.frames.last?.maxX == 980)
        #expect(layout.displayWidth == 980)
        #expect(layout.column(atX: 10) == .date)
        #expect(layout.column(atX: 100) == .payee)
        #expect(layout.column(atX: 990) == nil)
    }

    @Test func savedWidthsScaleTheFlexibleColumns() {
        var settings = RegisterColumnSettings()
        settings[.category]?.width = 87.5
        let values = RegisterColumnLayout.widths(
            gridWidth: 1000, visibleColumns: singleAccountColumns, settings: settings)
        let result = Dictionary(uniqueKeysWithValues: zip(singleAccountColumns, values))
        #expect(result[.payee]! > 2 * result[.category]! - 1)
    }

    @Test func allAccountsNeverGivesTheMemoANegativeWidth() {
        let columns: [RegisterColumn] = [
            .account, .date, .payee, .errorState, .category, .memo, .outflow, .inflow, .cleared,
        ]
        let result = widths(733, columns)
        #expect(result[.memo]! >= 0)
        #expect(abs(result.values.reduce(0, +) - 713) < 0.001)
        #expect(result[.account]! >= RegisterColumn.account.minWidth)
    }

    @Test func onlyTheMenuColumnsCanBeHidden() {
        let hideable = RegisterColumn.allCases.filter(\.canDisable)
        #expect(hideable == [.memo, .runningBalance, .cleared])
        #expect(RegisterColumnSettings()[.runningBalance]?.visible == false)
    }

    @Test func onlyTheRunningBalanceDoesNotSort() {
        #expect(RegisterColumn.allCases.filter { !$0.isSortable } == [.runningBalance])
        #expect(RegisterColumn.date.header == .text("Datum"))
        #expect(RegisterColumn.cleared.header == .symbol("checkmark.circle", label: "Gebucht"))
    }
}

@Suite struct ContentSizedColumnTests {
    @Test func contentSizedColumnsKeepTheirWidthAndTheTextColumnsShareTheRest() {
        let columns: [RegisterColumn] = [.date, .frequency, .payee, .category, .memo, .outflow, .inflow]
        let content: [RegisterColumn: CGFloat] = [.date: 92, .frequency: 130, .outflow: 70, .inflow: 70]
        let layout = RegisterColumnLayout(
            gridWidth: 1000, visibleColumns: columns, settings: RegisterScheduler.defaultColumnSettings,
            contentWidths: content)
        for (column, width) in content { #expect(layout.frame(of: column)?.width == width) }
        let text = [RegisterColumn.payee, .category, .memo].compactMap { layout.frame(of: $0)?.width }
        let rest: CGFloat = 980 - 92 - 130 - 70 - 70
        #expect(abs(text.reduce(0, +) - rest) <= 1)
    }

    @Test func aColumnFitsItsHeaderWhenItsCellsAreShorter() {
        let header: CGFloat = RegisterGridStyle.headerFont.width(of: "Häufigkeit")
        let expected: CGFloat = header + 2 * RegisterGridStyle.cellInset + RegisterGridStyle.sortIndicatorWidth
        #expect(RegisterColumn.frequency.contentWidth(fitting: []) == max(RegisterColumn.frequency.minWidth, expected))
    }
}
