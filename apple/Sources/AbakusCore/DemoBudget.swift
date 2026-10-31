import Foundation

public enum DemoBudget {
    public static let name = "Demo-Budget"

    static let categories: [(master: String, subs: [String])] = [
        ("🏠 Wohnen", ["🏠 Miete", "💡 Strom", "📱 Handy"]),
        ("🛒 Alltag", ["🛒 Lebensmittel", "⛽ Tanken", "🍕 Restaurant", "🧴 Haushalt", "🎧 Abos", "👕 Kleidung"]),
        ("🛟 Rücklagen", ["🛟 Notgroschen", "🔧 Instandhaltung", "🎄 Weihnachten"]),
        ("🎯 Sparziele", ["🏖️ Urlaub", "📈 ETF-Sparplan"]),
    ]

    public static func make(today: DateWithoutTime) -> Budget {
        var builder = Builder(today: today)
        builder.build()
        return builder.budget
    }

    private struct Builder {
        let today: DateWithoutTime
        let start: DateWithoutTime
        var budget = Budget(
            budgetName: DemoBudget.name, categoryGroups: DefaultCategories.categoryGroups(DemoBudget.categories))
        var ids: [String: String] = [:]
        let scheduledSpotifyId = EntityID.createUID()

        init(today: DateWithoutTime) {
            self.today = today
            self.start = today.addingMonths(-3)
        }

        mutating func build() {
            addAccounts()
            addGirokonto()
            addKreditkarte()
            addBargeld()
            addSavings()
            addScheduled()
            applyClearedStates()
            closeOldAccount()
            addMonthlyBudgets()
            addTargets()
            budgetAhead()
        }

        private mutating func addAccounts() {
            let accounts: [(String, AccountKind, Decimal)] = [
                ("Girokonto", .checking, 2450),
                ("Tagesgeld", .savings, 5000),
                ("Kreditkarte", .checking, -1240),
                ("Bargeld", .cash, 80),
                ("Altes Sparbuch", .savings, 600),
                ("Depot", .tracking, 12500),
                ("Bausparvertrag", .tracking, 4200),
            ]
            for (name, type, balance) in accounts {
                let new = NewAccount(name: name, kind: type, startingBalance: balance, startDate: start)
                ids[name] = new.id
                run(.addAccount(new))
            }
        }

        private mutating func addGirokonto() {
            for date in monthly(day: 28) {
                add("Girokonto", date, "Nordlicht Software GmbH", 3180, ("", "Zu verteilen"), memo: "Gehalt")
            }
            for date in monthly(day: 1) {
                add("Girokonto", date, "Wohnbau Lindenhof eG", -950, ("🏠 Wohnen", "🏠 Miete"), memo: "Miete")
                transfer("Girokonto", "Bausparvertrag", date, -50, category: ("🛟 Rücklagen", "🔧 Instandhaltung"))
            }
            for date in monthly(day: 5) {
                add("Girokonto", date, "Stadtwerke", -68, ("🏠 Wohnen", "💡 Strom"), memo: "Abschlag Strom")
            }
            for date in monthly(day: 12) {
                add("Girokonto", date, "Telekom", -39.95, ("🏠 Wohnen", "📱 Handy"))
            }
            let groceries: [(Int, Decimal)] = [(3, -42.18), (10, -67.35), (17, -23.90), (24, -88.12)]
            for (day, amount) in groceries {
                for date in monthly(day: day) {
                    add("Girokonto", date, "REWE", amount, ("🛒 Alltag", "🛒 Lebensmittel"))
                }
            }
            for date in monthly(day: 8) {
                add("Girokonto", date, "Aral", -62.40, ("🛒 Alltag", "⛽ Tanken"))
            }
            for date in monthly(day: 15) {
                add("Girokonto", date, "Pizzeria Da Marco", -34.50, ("🛒 Alltag", "🍕 Restaurant"))
                transfer(
                    "Girokonto", "Depot", date, -150, memo: "ETF-Sparplan",
                    category: ("🎯 Sparziele", "📈 ETF-Sparplan"))
            }
            for date in monthly(day: 2) { transfer("Girokonto", "Tagesgeld", date, -200, memo: "Sparen") }
            for date in monthly(day: 6) { transfer("Girokonto", "Bargeld", date, -100, memo: "Geldautomat") }
            for date in monthly(day: 20) { transfer("Girokonto", "Kreditkarte", date, -300) }
            addSplit()
            add("Girokonto", latest(today.addingDays(-2)), "Kleinanzeigen", 45, nil, memo: "Fahrradanhänger verkauft")
        }

        private mutating func addSplit() {
            let date = latest(today.addingDays(-9))
            let parentId = EntityID.createUID()
            let subs = [
                Subtransaction(
                    transactionId: parentId, amount: -54.30,
                    categoryId: category("🛒 Alltag", "🛒 Lebensmittel")),
                Subtransaction(
                    transactionId: parentId, amount: -23.50,
                    categoryId: category("🛒 Alltag", "🧴 Haushalt"), memo: "Waschmittel"),
            ]
            run(
                .addTransaction(
                    Transaction(
                        id: parentId, accountId: ids["Girokonto"]!, date: date, amount: -77.80,
                        subtransactions: subs),
                    payeeName: "Kaufland"))
        }

        private mutating func addKreditkarte() {
            for date in monthly(day: 9) {
                add("Kreditkarte", date, "Amazon", -49.99, ("🛒 Alltag", "🧴 Haushalt"))
            }
            for date in monthly(day: 14) {
                add("Kreditkarte", date, "Deutsche Bahn", -89.90, ("🎯 Sparziele", "🏖️ Urlaub"), memo: "Bahncard")
            }
            let spotify = monthly(day: 18)
            for date in spotify.dropLast() {
                add("Kreditkarte", date, "Spotify", -10.99, ("🛒 Alltag", "🎧 Abos"))
            }
            if let date = monthly(day: 22).first {
                add("Kreditkarte", date, "Zalando", -59.90, ("🛒 Alltag", "👕 Kleidung"), memo: "Winterjacke")
            }
            if let last = spotify.last {
                let entered = Transaction(
                    id: EntityID.enteredTransaction(scheduledId: scheduledSpotifyId, date: last),
                    accountId: ids["Kreditkarte"]!, date: last,
                    categoryId: category("🛒 Alltag", "🎧 Abos"), amount: -10.99, approved: false, source: .scheduled,
                    scheduledTransactionId: scheduledSpotifyId, scheduledDate: last)
                run(.addTransaction(entered, payeeName: "Spotify"))
            }
        }

        private mutating func addBargeld() {
            for day in [4, 11, 18, 25] {
                for date in monthly(day: day) {
                    add("Bargeld", date, "Bäckerei Krume", -6.80, ("🛒 Alltag", "🛒 Lebensmittel"))
                }
            }
            for date in monthly(day: 13) {
                add("Bargeld", date, "Wochenmarkt", -23.40, ("🛒 Alltag", "🛒 Lebensmittel"))
            }
        }

        private mutating func addSavings() {
            for date in monthly(day: 30) {
                add("Tagesgeld", date, "Zinsen", 4.12, ("", "Zu verteilen"))
            }
            transfer("Altes Sparbuch", "Tagesgeld", start.addingDays(3), -600, memo: "Konto aufgelöst")
            add("Depot", latest(today.addingDays(-20)), "Dividende", 38.40, nil)
        }

        private mutating func addScheduled() {
            budget.scheduledTransactions = [
                ScheduledTransaction(
                    accountId: ids["Girokonto"]!, nextDate: today.firstOfMonth.addingMonths(1), frequency: .monthly,
                    payeeId: payeeId("Wohnbau Lindenhof eG"), categoryId: category("🏠 Wohnen", "🏠 Miete"),
                    memo: "Miete", amount: -950),
                ScheduledTransaction(
                    id: scheduledSpotifyId, accountId: ids["Kreditkarte"]!,
                    nextDate: nextAfterToday(day: 18), frequency: .monthly, payeeId: payeeId("Spotify"),
                    categoryId: category("🛒 Alltag", "🎧 Abos"), amount: -10.99),
            ]
        }

        private mutating func applyClearedStates() {
            let girokonto = ids["Girokonto"]!
            let reconciledThrough = today.addingDays(-35)
            for index in budget.transactions.indices {
                let transaction = budget.transactions[index]
                guard transaction.approved else { continue }
                if transaction.accountId == girokonto && transaction.date <= reconciledThrough {
                    budget.transactions[index].cleared = .reconciled
                } else if transaction.date <= today.addingDays(-5) {
                    budget.transactions[index].cleared = .cleared
                } else {
                    budget.transactions[index].cleared = .uncleared
                }
            }
            if var account = budget.account(withId: girokonto) {
                account.lastReconciledAt = reconciledThrough.noon()
                run(.editAccount(account))
            }
        }

        private mutating func closeOldAccount() {
            guard var account = budget.account(withId: ids["Altes Sparbuch"]!) else { return }
            account.closed = true
            run(.editAccount(account))
        }

        /// The first month is assigned with what was spent in it; the rent rose this month and is overspent.
        private mutating func addMonthlyBudgets() {
            let plan: [(String, String, Decimal)] = [
                ("🏠 Wohnen", "🏠 Miete", 950), ("🏠 Wohnen", "💡 Strom", 70), ("🏠 Wohnen", "📱 Handy", 40),
                ("🛒 Alltag", "🛒 Lebensmittel", 340), ("🛒 Alltag", "⛽ Tanken", 65),
                ("🛒 Alltag", "🍕 Restaurant", 40), ("🛒 Alltag", "🧴 Haushalt", 80), ("🛒 Alltag", "🎧 Abos", 15),
                ("🛒 Alltag", "👕 Kleidung", 30), ("🛟 Rücklagen", "🛟 Notgroschen", 100),
                ("🛟 Rücklagen", "🔧 Instandhaltung", 50), ("🛟 Rücklagen", "🎄 Weihnachten", 25),
                ("🎯 Sparziele", "🏖️ Urlaub", 100), ("🎯 Sparziele", "📈 ETF-Sparplan", 150),
            ]
            let firstMonth = budget.budgetSheet(today: today).month(months[0])
            for (master, sub, amount) in plan {
                guard let id = category(master, sub) else { continue }
                var spent = firstMonth?.category(id)?.spent ?? 0
                var wholeEuros = Decimal()
                NSDecimalRound(&wholeEuros, &spent, 0, .up)
                if wholeEuros > 0 { run(.setAssigned(month: months[0], categoryId: id, amount: wholeEuros)) }
                for month in months.dropFirst() { run(.setAssigned(month: month, categoryId: id, amount: amount)) }
            }
            if let rent = category("🏠 Wohnen", "🏠 Miete") {
                run(.setAssigned(month: thisMonth, categoryId: rent, amount: 900))
            }
        }

        /// One target of each kind: met, overspent, underfunded, on track by a date and snoozed this month.
        private mutating func addTargets() {
            let targets: [(String, String, Target)] = [
                ("🏠 Wohnen", "🏠 Miete", .monthly(950)),
                ("🛒 Alltag", "🛒 Lebensmittel", .monthly(300, setAside: false)),
                ("🛒 Alltag", "⛽ Tanken", .monthly(65)),
                (
                    "🛟 Rücklagen", "🎄 Weihnachten",
                    .byDate(300, due: DateWithoutTime(year: today.year, month: 12, day: 24), repeatsYearly: true)
                ),
                (
                    "🛟 Rücklagen", "🛟 Notgroschen",
                    .byDate(3000, due: thisMonth.addingMonths(12), setAside: false)
                ),
                ("🎯 Sparziele", "🏖️ Urlaub", .monthly(150)),
            ]
            for (master, sub, target) in targets {
                guard let id = category(master, sub) else { continue }
                run(.setTarget(month: months[0], categoryId: id, target: target))
            }
            if let emergency = category("🛟 Rücklagen", "🛟 Notgroschen"),
                let figures = budget.budgetSheet(today: today).month(thisMonth)?.category(emergency),
                let missing = figures.target?.underfunded, missing > 0
            {
                run(.setAssigned(month: thisMonth, categoryId: emergency, amount: figures.assigned + missing))
            }
            if let vacation = category("🎯 Sparziele", "🏖️ Urlaub") {
                run(.setTargetSnoozed(month: thisMonth, categoryId: vacation, true))
            }
        }

        /// Next month's rent is assigned already, so this month shows "Für spätere Monate".
        private mutating func budgetAhead() {
            guard let rent = category("🏠 Wohnen", "🏠 Miete") else { return }
            run(.setAssigned(month: thisMonth.addingMonths(1), categoryId: rent, amount: 950))
        }

        private var months: [DateWithoutTime] { (0...3).map { start.firstOfMonth.addingMonths($0) } }

        private var thisMonth: DateWithoutTime { today.firstOfMonth }

        private func monthly(day: Int) -> [DateWithoutTime] {
            (0...3).map { start.firstOfMonth.addingMonths($0) }
                .map { DateWithoutTime(year: $0.year, month: $0.month, day: min(day, $0.daysInMonth)) }
                .filter { $0 > start && $0 <= today }
        }

        private func latest(_ date: DateWithoutTime) -> DateWithoutTime {
            max(min(date, today), start.addingDays(1))
        }

        private func nextAfterToday(day: Int) -> DateWithoutTime {
            let thisMonth = DateWithoutTime(year: today.year, month: today.month, day: min(day, today.daysInMonth))
            return thisMonth > today ? thisMonth : thisMonth.addingMonths(1)
        }

        private func category(_ master: String, _ sub: String) -> String? {
            if master.isEmpty { return budget.readyToAssignCategoryId }
            return budget.categoryGroups.first { $0.name == master }?.categories.first { $0.name == sub }?
                .id
        }

        private func payeeId(_ name: String) -> String? {
            budget.payees.first { $0.name == name }?.id
        }

        private mutating func add(
            _ account: String, _ date: DateWithoutTime, _ payee: String, _ amount: Decimal,
            _ category: (String, String)?, memo: String? = nil
        ) {
            let transaction = Transaction(
                accountId: ids[account]!, date: date, categoryId: category.flatMap { self.category($0.0, $0.1) },
                memo: memo, amount: amount)
            run(.saveTransaction(TransactionSave(transaction: transaction, payeeName: payee, isNew: true)))
        }

        private mutating func transfer(
            _ from: String, _ to: String, _ date: DateWithoutTime, _ amount: Decimal, memo: String? = nil,
            category: (String, String)? = nil
        ) {
            let transaction = Transaction(
                accountId: ids[from]!, date: date, payeeId: EntityID.transferPayee(accountId: ids[to]!),
                categoryId: category.flatMap { self.category($0.0, $0.1) }, memo: memo, amount: amount)
            run(.addTransaction(transaction))
        }

        private mutating func run(_ command: BudgetCommand) {
            do {
                try budget.apply(command)
            } catch {
                assertionFailure("Demo budget command failed: \(error)")
            }
        }
    }
}
