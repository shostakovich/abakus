import AbakusCore
import AppKit
import SwiftUI
import Testing

@testable import AbakusUI

@MainActor
@Suite struct InlineEditingTests {
    @Test func cancelLeadsAndTheOtherButtonsKeepTheirPlaces() {
        #expect(
            EditButtonRow.displayOrder([.saveAndAddAnother, .save, .cancel]) == [.cancel, .saveAndAddAnother, .save])
        #expect(EditButtonRow.displayOrder([.done, .cancel]) == [.cancel, .done])
        #expect(
            EditButtonRow.displayOrder([.approveAndFindNext, .approve, .delete, .cancel])
                == [.cancel, .approveAndFindNext, .approve, .delete])
    }

    @Test func saveIsProminentWhileReturnStillSavesAndAddsAnother() throws {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied(appliesCommands: true)
        model.addTransactionClicked()
        let editor = try #require(model.editor)
        #expect(editor.prominentButton == .save)
        #expect(editor.defaultButton == .saveAndAddAnother)
        editor.press(.tab)
        editor.type("Bakery")
        editor.press(.tab, .tab, .tab)
        editor.type("3")
        editor.press(.enter)
        let next = try #require(model.editor)
        #expect(next !== editor)
        #expect(next.mode == .new)
    }

    @Test func anExistingTransactionsProminentButtonIsReturnsButton() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let model = fixture.model()
        model.beginEditing(id)
        #expect(model.editor?.prominentButton == .done)
    }

    @Test func approveAndDeleteCarrySymbols() {
        let symbols = EditorButton.allCases.filter { $0.systemImage != nil }
        #expect(symbols == [.approve, .delete])
    }

    @Test func aPickedDayClosesTheDatePickerAndAMonthStepKeepsItOpen() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, on: "2014-05-10")
        let model = fixture.model()
        model.beginEditing(id)
        let editor = try #require(model.editor)
        editor.toggleCalendar()
        editor.calendarDatePicked(day("2014-06-10"))
        #expect(editor.isCalendarOpen)
        #expect(editor.text(.main(.date)) == "10/06/14")
        editor.calendarDatePicked(day("2014-06-03"))
        #expect(!editor.isCalendarOpen)
        #expect(editor.clone.date == day("2014-06-03"))
    }

    @Test func theDatePickerKeepsToTenYearsAroundToday() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, on: "2014-05-10")
        let model = fixture.model()
        model.beginEditing(id)
        let editor = try #require(model.editor)
        editor.toggleCalendar()
        editor.calendarDatePicked(day("2030-01-10"))
        #expect(editor.dateCallout != nil)
        #expect(editor.clone.date == day("2014-05-10"))
    }

    @Test func theEditRowStacksFieldsSplitLinesAndButtons() {
        #expect(EditRowMetrics.height(subRows: nil) == 64)
        #expect(EditRowMetrics.height(subRows: 2) == CGFloat(64 + 2 * 28 + 32))
    }

    @Test func theFrequencyMenuChecksTheCurrentFrequency() {
        let items = RegisterMenuItem.frequencyMenu(selected: .monthly)
        #expect(items.map(\.title) == ScheduledTransactionFrequency.allCases.map(\.readableName))
        #expect(items.filter(\.isChecked).map(\.kind) == [.action(.frequency(.monthly))])
    }
}

/// The edit row in a window of its own: keys reach its text fields through the field editor as in the app.
@MainActor
@Suite struct InlineEditorKeyboardTests {
    @MainActor
    private struct Host {
        let model: RegisterViewModel
        let editor: TransactionEditor
        let window: NSWindow

        func type(_ text: String) async {
            for character in text { await send(String(character), keyCode: 0) }
        }

        func press(_ keyCode: UInt16, _ characters: String) async {
            await send(characters, keyCode: keyCode)
        }

        private func send(_ characters: String, keyCode: UInt16) async {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                keyCode: keyCode)!
            window.sendEvent(event)
            await settle()
        }

        /// Suspends, so the main queue runs the focus hand-offs the field schedules.
        func settle() async {
            for _ in 0..<5 {
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(15))
            }
        }

        var typesIntoAField: Bool { window.firstResponder is NSTextView }

        func views<V: NSView>(of type: V.Type) -> [V] {
            func collect(_ view: NSView) -> [V] { [view as? V].compactMap(\.self) + view.subviews.flatMap(collect) }
            return window.contentView.map(collect) ?? []
        }
    }

    private static let tab = (UInt16(48), "\t")
    private static let enter = (UInt16(36), "\r")
    private static let escape = (UInt16(53), "\u{1B}")

    private func editing(column: RegisterColumn?) async throws -> Host {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10, on: "2014-05-10")
        let model = fixture.model()
        model.beginEditing(id, column: column)
        let editor = try #require(model.editor)
        let row = try #require(model.rows.first { $0.id == id })
        let layout = model.columnLayout(gridWidth: 900)
        let content = EditRowView(editor: editor, layout: layout, row: row, main: model)
            .frame(width: 900, height: 420, alignment: .top)
            .overlayPreferenceValue(EditorAnchorKey.self) { EditorPopupsLayer(editor: editor, anchors: $0) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 420), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = NSHostingView(rootView: content)
        let host = Host(model: model, editor: editor, window: window)
        await host.settle()
        return host
    }

    @Test func theDatePickerOpensByKeyboardAndLeavesTheTypingInTheDateField() async throws {
        let host = try await editing(column: .date)
        #expect(host.typesIntoAField)
        await host.type("+")
        #expect(host.editor.isCalendarOpen)
        #expect(host.editor.text(.main(.date)) == "11/05/14")
        let picker = try #require(host.views(of: NSDatePicker.self).first)
        #expect(picker.refusesFirstResponder)
        #expect(host.typesIntoAField)
        await host.type("+")
        #expect(host.editor.text(.main(.date)) == "12/05/14")
        await host.press(Self.escape.0, Self.escape.1)
        #expect(!host.editor.isCalendarOpen)
        #expect(host.views(of: NSDatePicker.self).isEmpty)
        await host.press(Self.enter.0, Self.enter.1)
        #expect(host.model.editor == nil)
        #expect(host.model.store.budget.transactions.contains { $0.date == day("2014-05-12") })
    }

    @Test func theCalculatorWorksByKeyboard() async throws {
        let host = try await editing(column: .amount)
        await host.type("*3")
        #expect(host.editor.calculator?.calculator.display == "3")
        #expect(host.typesIntoAField)
        await host.press(Self.enter.0, Self.enter.1)
        #expect(host.editor.calculator == nil)
        #expect(host.editor.text(.main(.amount)) == "30.00")
        #expect(host.model.editor != nil)
        await host.press(Self.enter.0, Self.enter.1)
        #expect(host.model.editor == nil)
    }

    @Test func tabMovesOnAndEscapeCancelsAnUnchangedEdit() async throws {
        let host = try await editing(column: .memo)
        await host.press(Self.tab.0, Self.tab.1)
        #expect(host.editor.focusedField == .main(.amount))
        #expect(host.typesIntoAField)
        await host.press(Self.escape.0, Self.escape.1)
        #expect(host.model.editor == nil)
    }
}

@Suite struct DatePickerCalendarTests {
    @Test func aGermanBudgetStartsTheWeekOnMondayAndAnAmericanOneOnSunday() {
        #expect(FormatLocale.deDE.calendar.firstWeekday == 2)
        #expect(FormatLocale.deDE.calendar.locale?.identifier == "de_DE")
        #expect(FormatLocale.enUS.calendar.firstWeekday == 1)
    }
}
