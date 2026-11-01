import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct SchedulerTests {
    private func fixture(frequency: ScheduledTransactionFrequency = .monthly, on date: String = "2014-06-02")
        -> RegisterFixture
    {
        var fixture = RegisterFixture()
        fixture.addSchedule(
            "S1", on: date, payee: "Farm", category: fixture.groceries, memo: "Box", frequency: frequency)
        return fixture
    }

    @Test func columnsFollowTheScheduleGrid() {
        let fixture = fixture()
        let giro = fixture.spied().model
        #expect(giro.scheduler.visibleColumns == [.date, .frequency, .payee, .category, .memo, .amount])
        let allAccounts = fixture.spied(selection: .allAccounts).model
        #expect(allAccounts.scheduler.visibleColumns.first == .account)
        let depot = fixture.spied(selection: .account(fixture.depot)).model
        #expect(!depot.scheduler.visibleColumns.contains(.category))
    }

    @Test func rowsShowTheNextDateAndTheFrequency() throws {
        let (model, _) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        #expect(row.date == "02/06/14")
        #expect(row.frequency == "Monatlich")
        #expect(row.payee == "Farm")
        #expect(row.category == "Groceries")
        #expect(row.amountText == "−25.00")
        #expect(model.scheduler.scheduledTransactions.count == 1)
    }

    @Test func splitLinesShowTheirCategoryInAnOffBudgetAccount() throws {
        var fixture = RegisterFixture()
        fixture.addSplitSchedule(account: fixture.depot)
        let (model, _) = fixture.spied(selection: .allAccounts)
        model.scheduler.grid.toggleSplit("S1")
        let rows = model.scheduler.rows
        #expect(rows.map(\.category) == ["", "Groceries", "Groceries"])
    }

    @Test func toggleShowsThePaneAtItsMinimumHeight() {
        let (model, _) = fixture().spied()
        #expect(!model.scheduler.isVisible)
        model.scheduledToggleClicked()
        #expect(model.scheduler.isVisible)
        #expect(model.scheduler.savedHeight == 185)
        model.scheduler.setHeight(120)
        #expect(model.scheduler.savedHeight == 185)
        model.scheduler.setHeight(260)
        #expect(model.scheduler.savedHeight == 260)
        #expect(SchedulerMetrics.height(saved: 600, available: 700) == CGFloat(700 - 1 - 250))
    }

    @Test func newScheduledTransactionDefaultsToMonthlyAndSavesAsSchedule() throws {
        let fixture = RegisterFixture()
        let (model, store) = fixture.spied(appliesCommands: true)
        model.scheduler.grid.beginNew()
        let editor = try #require(model.scheduler.editor)
        #expect(editor.isScheduled)
        #expect(editor.frequency == .monthly)
        #expect(editor.text(.main(.date)) == "20/05/14")
        editor.press(.tab)
        #expect(editor.focus == .field(.main(.frequency)))
        editor.press(.down)
        #expect(editor.frequency == .everyOtherMonth)
        editor.press(.tab)
        editor.type("Gym")
        editor.press(.tab, .tab, .tab)
        editor.type("30")
        editor.activate(.save)
        guard case .saveScheduledTransaction(let save) = try #require(store.commands.last) else {
            Issue.record("no schedule saved")
            return
        }
        #expect(save.isNew)
        #expect(save.frequency == .everyOtherMonth)
        #expect(save.transaction.amount == -30)
        #expect(save.payeeName == "Gym")
        #expect(model.transactions.count == 1)
        #expect(model.scheduler.selectedIds == [save.transaction.id])
    }

    @Test func saveAndAddAnotherStartsTheNextScheduleFromTheSavedOne() throws {
        let fixture = RegisterFixture()
        let (model, store) = fixture.spied(selection: .allAccounts, appliesCommands: true)
        model.scheduler.grid.beginNew()
        let editor = try #require(model.scheduler.editor)
        editor.fieldClicked(.main(.account))
        editor.retype("Ta")
        editor.press(.tab)
        editor.retype("25/05/14")
        editor.press(.tab)
        editor.press(.down)
        editor.press(.tab)
        editor.type("Gym")
        editor.press(.tab, .tab, .tab)
        editor.type("30")
        editor.activate(.saveAndAddAnother)
        #expect(store.commands.count == 1)
        guard case .saveScheduledTransaction(let save) = store.commands.first else { return }
        #expect(save.frequency == .everyOtherMonth)
        #expect(save.transaction.accountId == fixture.tagesgeld)
        let next = try #require(model.scheduler.editor)
        #expect(next !== editor)
        #expect(next.mode == .new)
        #expect(next.frequency == .monthly)
        #expect(next.clone.accountId == fixture.tagesgeld)
        #expect(next.text(.main(.date)) == "25/05/14")
        next.activate(.cancel)
        model.scheduler.grid.beginNew()
        #expect(model.scheduler.editor?.text(.main(.date)) == "25/05/14")
    }

    @Test func addingInAllAccountsStartsInTheFirstOpenAccountAndOffersTheAccountField() throws {
        var fixture = RegisterFixture()
        fixture.budget.accounts[0].closed = true
        let (model, _) = fixture.spied(selection: .allAccounts)
        model.scheduler.grid.beginNew()
        let editor = try #require(model.scheduler.editor)
        #expect(editor.clone.accountId == fixture.tagesgeld)
        #expect(model.scheduler.visibleColumns.first == .account)
        #expect(editor.mainColumns().first == .account)
    }

    @Test func frequencyListChoosesAFrequency() throws {
        let (model, store) = fixture().spied()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        editor.frequencyClicked()
        #expect(editor.isFrequencyListOpen)
        #expect(editor.focus == .field(.main(.frequency)))
        editor.frequencyChosen(.twiceAMonth)
        #expect(!editor.isFrequencyListOpen)
        #expect(editor.hasChanges)
        editor.activate(.done)
        guard case .saveScheduledTransaction(let save) = try #require(store.commands.last) else {
            Issue.record("no schedule saved")
            return
        }
        #expect(!save.isNew)
        #expect(save.transaction.id == "S1")
        #expect(save.frequency == .twiceAMonth)
    }

    @Test func aDateBeforeTodayIsRejected() throws {
        let (model, store) = fixture().spied()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        editor.retype("19/05/14")
        editor.press(.tab)
        #expect(
            editor.dateCallout?.message
                == "Datum außerhalb des Bereichs: „<b>19/05/14</b>“<br/>Geplante Buchungen beginnen frühestens heute.")
        #expect(editor.text(.main(.date)) == "02/06/14")
        #expect(store.commands.isEmpty)
    }

    @Test func theDatePickerRefusesADateBeforeTodayAsTypingDoes() throws {
        let (model, store) = fixture().spied()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        editor.toggleCalendar()
        editor.calendarDatePicked(day("2014-05-02"))
        #expect(
            editor.dateCallout?.message
                == "Datum außerhalb des Bereichs: „<b>02/05/14</b>“<br/>Geplante Buchungen beginnen frühestens heute.")
        #expect(editor.clone.date == day("2014-06-02"))
        #expect(editor.text(.main(.date)) == "02/06/14")
        #expect(!editor.isCalendarOpen)
        #expect(store.commands.isEmpty)
    }

    @Test func secondClickEditsTheSchedule() throws {
        let (model, _) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(row.transactionId, column: .memo, modifiers: [])
        #expect(model.scheduler.selectedIds == ["S1"])
        model.scheduler.grid.rowClicked(row.transactionId, column: .memo, modifiers: [])
        #expect(model.scheduler.grid.editingId == "S1")
        #expect(model.scheduler.editor?.focus == .field(.main(.memo)))
    }

    @Test func enterNowAddsAnApprovedTransactionAndSelectsIt() throws {
        let fixture = fixture(frequency: .once)
        let (model, store) = fixture.spied(appliesCommands: true)
        let row = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(row.transactionId, column: .payee, modifiers: [])
        #expect(model.scheduler.menuTitle == "1 ausgewählte geplante Buchung")
        model.scheduler.enterNowClicked()
        #expect(
            store.commands == [
                .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true))
            ])
        let entered = try #require(model.transactions.first { $0.source == .scheduled })
        #expect(model.selectedTransactionIds == [entered.id])
        #expect(model.scheduler.selection.isEmpty)
        #expect(model.grid.scrollRequest?.target == .row(entered.id))
    }

    @Test func skipAndDeleteWorkOnTheSelection() throws {
        let (model, store) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(row.transactionId, column: .payee, modifiers: [])
        model.scheduler.skipClicked()
        model.scheduler.deleteClicked()
        #expect(store.commands == [.skipScheduledTransactions(["S1"]), .deleteScheduledTransactions(["S1"])])
    }

    @Test func moveIntoTheTransferTargetIsRefused() throws {
        var fixture = RegisterFixture()
        fixture.addSchedule("S2", -50, payee: nil, target: fixture.tagesgeld)
        let (model, store) = fixture.spied()
        let row = try #require(model.scheduler.rows.first)
        model.scheduler.contextClicked(row)
        #expect(model.scheduler.moveTargets.map(\.name) == ["Depot", "Karte", "Tagesgeld"])
        store.fail(with: BudgetError.transferIntoMoveTarget("Tagesgeld"), once: true)
        model.scheduler.moveClicked(to: fixture.tagesgeld)
        #expect(
            model.dialogs.presented.last?.dialog.instruction
                == "Nicht alle diese Buchungen lassen sich nach „Tagesgeld“ verschieben.")
        model.dialogs.presented.last?.answer(MessageChoice.close)
        #expect(!model.dialogs.isPresenting)
        #expect(model.notifiers.undoSlot == nil)
        model.scheduler.moveClicked(to: fixture.karte)
        #expect(store.commands.last == .moveScheduledTransactions(["S2"], toAccount: fixture.karte))
        #expect(model.notifiers.undoSlot?.message == "Buchung nach „Karte“ verschoben")
    }

    @Test func rowMenuListsTheScheduledActionsUnderTheSelectionCount() throws {
        let (model, _) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        let items = try #require(model.scheduler.contextMenu(for: row))
        #expect(model.scheduler.selectedIds == ["S1"])
        #expect(
            items.map(\.title) == [
                "1 ausgewählte geplante Buchung", "", "Jetzt buchen", "Diesmal überspringen", "", "Löschen", "",
                "In Konto verschieben",
            ])
        #expect(items[0].kind == .title && !items[0].isEnabled)
        #expect(items.filter { $0.kind == .separator }.count == 3)
        #expect(items.dropFirst().allSatisfy { $0.isEnabled })
        #expect(items.last?.submenu?.map(\.title) == ["Depot", "Karte", "Tagesgeld"])
    }

    @Test func moveToAccountIsDisabledWithoutATarget() throws {
        var fixture = fixture()
        for index in 1..<fixture.budget.accounts.count { fixture.budget.accounts[index].closed = true }
        let (model, _) = fixture.spied()
        let row = try #require(model.scheduler.rows.first)
        let items = try #require(model.scheduler.contextMenu(for: row))
        #expect(items.item(titled: "In Konto verschieben")?.isEnabled == false)
        #expect(items.item(titled: "In Konto verschieben")?.submenu == [])
    }

    @Test func aChangedEditSwallowsTheRowMenu() throws {
        var fixture = fixture()
        fixture.addSchedule("S2", on: "2014-06-05")
        let (model, _) = fixture.spied()
        model.scheduler.beginEditing("S1", column: .memo)
        model.scheduler.editor?.type("changed")
        let other = try #require(model.scheduler.rows.first { $0.id == "S2" })
        #expect(model.scheduler.contextMenu(for: other) == nil)
        #expect(model.scheduler.editor?.glowCount == 1)
        #expect(model.scheduler.selectedIds == ["S1"])
    }

    @Test(arguments: [
        RegisterMenuAction.enterScheduledNow, .skipScheduled, .deleteScheduled, .moveScheduled(accountId: "KARTE"),
    ])
    func eachRowMenuActionReachesTheScheduler(_ action: RegisterMenuAction) throws {
        let (model, store) = fixture().spied()
        let row = try #require(model.scheduler.rows.first)
        let items = try #require(model.scheduler.contextMenu(for: row))
        func offers(_ items: [RegisterMenuItem]) -> Bool {
            items.contains { $0.kind == .action(action) || offers($0.submenu ?? []) }
        }
        #expect(offers(items))
        model.performMenuAction(action)
        let expected: BudgetCommand =
            switch action {
            case .enterScheduledNow:
                .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true))
            case .skipScheduled: .skipScheduledTransactions(["S1"])
            case .deleteScheduled: .deleteScheduledTransactions(["S1"])
            default: .moveScheduledTransactions(["S1"], toAccount: "KARTE")
            }
        #expect(store.commands == [expected])
    }

    @Test func clickingTheMainGridClearsTheSchedulerSelection() throws {
        let fixture = fixture()
        let (model, _) = fixture.spied()
        let scheduled = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(scheduled.transactionId, column: .payee, modifiers: [])
        let row = try #require(model.rows.first)
        model.rowClicked(row, column: .payee, modifiers: [])
        #expect(model.scheduler.selection.isEmpty)
        #expect(model.selectedTransactionIds == [row.transactionId])
    }

    @Test func makeRecurringSelectsTheNewScheduleWithoutOpeningThePane() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -9.99, payee: "Spotify")
        let (model, _) = fixture.spied(appliesCommands: true)
        model.updateSelection { $0.select(id) }
        model.performMenuAction(.makeRecurring)
        let scheduleId = try #require(model.lastScheduledTransactionId)
        #expect(!model.isSchedulerVisible)
        #expect(model.scheduler.selectedIds == [scheduleId])
        #expect(model.selectedTransactionIds.isEmpty)
        #expect(model.scheduler.grid.scrollRequest?.target == .row(scheduleId))
        #expect(model.popup == .scheduledCallout(.added))
        #expect(model.popup?.anchor == .schedulerTitle)
    }

    @Test func moveToSchedulerSelectsTheSchedule() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -20, on: "2014-07-01")
        let (model, _) = fixture.spied(appliesCommands: true)
        model.updateSelection { $0.select(id) }
        model.performMenuAction(.moveToScheduler)
        let scheduleId = try #require(model.lastScheduledTransactionId)
        #expect(model.scheduler.rows.map(\.transactionId) == [scheduleId])
        #expect(model.scheduler.selectedIds == [scheduleId])
        #expect(model.selection.isEmpty)
    }

    @Test func makeRecurringWhileReconcilingLeavesThePaneClosed() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -9.99, payee: "Spotify")
        let (model, _) = fixture.spied(appliesCommands: true)
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "1000"
        model.reconciliation.begin(form)
        model.updateSelection { $0.select(id) }
        model.performMenuAction(.makeRecurring)
        let scheduleId = try #require(model.lastScheduledTransactionId)
        #expect(!model.isSchedulerVisible)
        #expect(model.popup == nil)
        model.reconciliation.stopReconcilingClicked()
        #expect(!model.isSchedulerVisible)
        #expect(model.scheduler.selectedIds == [scheduleId])
    }

    @Test func thePlusMenuSchedulesANewTransactionOrATransfer() throws {
        let (model, _) = RegisterFixture().spied()
        model.scheduler.addClicked()
        let editor = try #require(model.scheduler.editor)
        #expect(editor.mode == .new)
        #expect(editor.isScheduled)
        #expect(editor.focus == .field(.main(.date)))
        editor.activate(.cancel)
        #expect(model.scheduler.editor == nil)
        model.scheduler.transferClicked()
        let transfer = try #require(model.scheduler.editor)
        #expect(transfer.focus == .field(.main(.payee)))
        #expect(transfer.text(.main(.payee)) == Payee.transferPrefix)
    }

    @Test func theFrequencyColumnFitsTheLongestFrequency() throws {
        var fixture = fixture()
        let before = fixture.spied().model
        let monthly = try #require(before.scheduler.columnLayout(gridWidth: 1000).frame(of: .frequency))
        #expect(
            monthly.width
                == RegisterColumn.frequency.contentWidth(
                    fitting: ["Monatlich"], accessory: SchedulerMetrics.popUpAccessory))
        fixture.addSchedule("S2", payee: "Gym", frequency: .everyOtherMonth)
        let after = fixture.spied().model
        let layout = after.scheduler.columnLayout(gridWidth: 1000)
        let longest = try #require(layout.frame(of: .frequency))
        #expect(
            longest.width
                == RegisterColumn.frequency.contentWidth(
                    fitting: ["Alle 2 Monate"], accessory: SchedulerMetrics.popUpAccessory))
        #expect(longest.width > monthly.width)
        let columnsWidth = layout.displayWidth - RegisterMetrics.leadingInset
        #expect(abs(layout.frames.map(\.width).reduce(0, +) - columnsWidth) <= 1)
    }

    @Test func amountColumnsWidenForLargeAmountsAndKeepTheirMinimum() throws {
        var fixture = fixture()
        let before = fixture.spied().model
        let small = before.scheduler.columnLayout(gridWidth: 1000)
        #expect(small.frame(of: .amount)?.width == RegisterColumn.signedAmountWidth)
        #expect(small.frame(of: .date)?.width == RegisterColumn.date.minWidth)
        fixture.addSchedule("S2", -1_234_567.89, payee: "House")
        let after = fixture.spied().model
        let large = after.scheduler.columnLayout(gridWidth: 1000)
        let amount = try #require(large.frame(of: .amount))
        #expect(
            amount.width
                == RegisterColumn.amount.contentWidth(
                    fitting: ["−1,234,567.89", "−25.00"], accessory: EditCellStyle.accessoryWidth))
        #expect(amount.width > RegisterColumn.signedAmountWidth)
    }
}
