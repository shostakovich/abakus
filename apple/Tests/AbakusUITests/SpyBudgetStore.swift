import AbakusCore
import Foundation

@testable import AbakusUI

/// The budget changes only where a test asks for it: by `appliesCommands` or `budgetAfterNextCommand`.
@MainActor
final class SpyBudgetStore: BudgetStoring {
    var budget: Budget
    let today: () -> DateWithoutTime
    private(set) var commands: [BudgetCommand] = []
    var appliesCommands = false
    var budgetAfterNextCommand: Budget?
    private var failure: (error: any Error, once: Bool)?

    init(budget: Budget, today: DateWithoutTime = editDay, appliesCommands: Bool = false) {
        self.budget = budget
        self.today = { today }
        self.appliesCommands = appliesCommands
    }

    func fail(with error: any Error, once: Bool = false) {
        failure = (error, once)
    }

    func perform(_ command: BudgetCommand) throws {
        commands.append(command)
        if let failure {
            if failure.once { self.failure = nil }
            throw failure.error
        }
        if let next = budgetAfterNextCommand {
            budgetAfterNextCommand = nil
            budget = next
        } else if appliesCommands {
            budget = try budget.applying(command)
        }
    }

    var transactionSaves: [TransactionSave] {
        commands.compactMap {
            guard case .saveTransaction(let save) = $0 else { return nil }
            return save
        }
    }
}

extension RegisterFixture {
    @MainActor
    func spied(selection: SidebarSelection? = nil, appliesCommands: Bool = false)
        -> (model: RegisterViewModel, store: SpyBudgetStore)
    {
        let store = SpyBudgetStore(budget: budget, appliesCommands: appliesCommands)
        let model = RegisterViewModel(store: store, navigation: NavigationState(selection: selection ?? .account(giro)))
        return (model, store)
    }
}
