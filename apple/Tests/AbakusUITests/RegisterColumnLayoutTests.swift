import AbakusCore
import CoreGraphics
import Testing

@testable import AbakusUI

private let singleAccountColumns: [RegisterColumn] = [
    .date, .payee, .category, .memo, .amount, .cleared,
]

private func widths(_ gridWidth: CGFloat, _ columns: [RegisterColumn] = singleAccountColumns)
    -> [RegisterColumn: CGFloat]
{
    let values = RegisterColumnLayout.widths(
        gridWidth: gridWidth, visibleColumns: columns, settings: RegisterColumnSettings())
    return Dictionary(uniqueKeysWithValues: zip(columns, values))
}

@Suite struct RegisterColumnLayoutTests {
    @Test(arguments: [800, 1000, 1400] as [CGFloat])
    func theMemoTakesTheRoomLeftOfTheOtherColumns(gridWidth: CGFloat) {
        let result = widths(gridWidth)
        let amount = RegisterColumn.signedAmountWidth
        #expect(result[.payee] == 175)
        #expect(result[.category] == 175)
        #expect(abs(result[.memo]! - (gridWidth - 20 - 92 - amount - 32 - 350)) < 0.001)
    }

    @Test func aNarrowGridShrinksTheTextColumnsTogether() {
        let result = widths(600)
        #expect(result[.payee]! < 175)
        #expect(abs(result[.payee]! - result[.category]!) < 0.001)
        #expect(result[.memo] == RegisterColumn.memo.minWidth)
        #expect(abs(result.values.reduce(0, +) - 580) < 0.001)
    }

    @Test func fixedColumnsUseTheirMinimumWidth() {
        let result = widths(1000)
        #expect(result[.date] == 92)
        #expect(result[.amount] == RegisterColumn.signedAmountWidth)
        #expect(result[.cleared] == 32)
    }

    @Test func amountColumnsFitTenThousandWithItsSign() {
        let room = RegisterColumn.amountWidth - 2 * RegisterGridStyle.cellInset
        #expect(RegisterGridStyle.rowBoldFont.width(of: "−10.000,00") <= room)
        #expect(RegisterGridStyle.rowBoldFont.width(of: "+10.000,00") <= room)
    }

    @Test func columnsFillTheDisplayWidthLeftOfTheColumnMenu() {
        let total = widths(1000).values.reduce(0, +)
        #expect(abs(total - 980) < 0.001)
    }

    @Test func framesAreContiguousOnWholePoints() {
        let layout = RegisterColumnLayout(
            gridWidth: 1000, visibleColumns: singleAccountColumns, settings: RegisterColumnSettings())
        #expect(layout.frames.first?.x == RegisterMetrics.leadingInset)
        for (left, right) in zip(layout.frames, layout.frames.dropFirst()) {
            #expect(left.maxX == right.x)
            #expect(right.x == right.x.rounded())
        }
        #expect(layout.frames.last?.maxX == 980)
        #expect(layout.displayWidth == 980)
        #expect(layout.column(atX: 20) == .date)
        #expect(layout.column(atX: 110) == .payee)
        #expect(layout.column(atX: 990) == nil)
    }

    @Test func savedWidthsCapTheOtherTextColumns() {
        var settings = RegisterColumnSettings()
        settings[.category]?.width = 87.5
        let values = RegisterColumnLayout.widths(
            gridWidth: 1000, visibleColumns: singleAccountColumns, settings: settings)
        let result = Dictionary(uniqueKeysWithValues: zip(singleAccountColumns, values))
        #expect(result[.category] == 87.5)
        #expect(result[.payee] == 175)
    }

    @Test func allAccountsKeepsTheMemosMinimum() {
        let columns: [RegisterColumn] = [
            .account, .date, .payee, .category, .memo, .amount, .cleared,
        ]
        let result = widths(680, columns)
        #expect(result[.memo] == RegisterColumn.memo.minWidth)
        #expect(abs(result.values.reduce(0, +) - 660) < 0.001)
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
        #expect(RegisterColumn.cleared.header == .symbol("checkmark.circle", label: "Status"))
    }
}

@Suite struct ContentSizedColumnTests {
    @Test func contentSizedColumnsKeepTheirWidthAndTheTextColumnsShareTheRest() {
        let columns: [RegisterColumn] = [.date, .frequency, .payee, .category, .memo, .amount]
        let content: [RegisterColumn: CGFloat] = [.date: 92, .frequency: 130, .amount: 90]
        let layout = RegisterColumnLayout(
            gridWidth: 1000, visibleColumns: columns, settings: RegisterScheduler.defaultColumnSettings,
            contentWidths: content)
        for (column, width) in content { #expect(layout.frame(of: column)?.width == width) }
        let text = [RegisterColumn.payee, .category, .memo].compactMap { layout.frame(of: $0)?.width }
        let rest: CGFloat = 980 - RegisterMetrics.leadingInset - 92 - 130 - 90
        #expect(abs(text.reduce(0, +) - rest) <= 1)
    }

    @Test func aColumnFitsItsHeaderWhenItsCellsAreShorter() {
        let header: CGFloat = RegisterGridStyle.headerFont.width(of: "Häufigkeit")
        let expected: CGFloat = header + 2 * RegisterGridStyle.cellInset + RegisterGridStyle.sortIndicatorWidth
        #expect(RegisterColumn.frequency.contentWidth(fitting: []) == max(RegisterColumn.frequency.minWidth, expected))
    }
}
