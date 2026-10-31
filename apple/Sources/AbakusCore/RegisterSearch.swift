import Foundation

public enum SearchAmountKind: Hashable, Sendable {
    case outflowEquals, outflowMore, outflowLess, inflowEquals, inflowMore, inflowLess

    func matches(_ amount: Decimal, _ value: Decimal) -> Bool {
        switch self {
        case .outflowEquals: amount == -value
        case .outflowMore: amount <= -value
        case .outflowLess: amount >= -value
        case .inflowEquals: amount == value
        case .inflowMore: amount >= value
        case .inflowLess: amount <= value
        }
    }
}

public enum SearchDateKind: Hashable, Sendable {
    case on, after, before
}

public enum SearchItem: Hashable, Sendable {
    case anyField(String)
    case memo(String)
    case payees([String])
    case categories([String])
    case accounts([String])
    case approved(Bool)
    case errorLevel(ErrorLevel)
    case clearedOrReconciled
    case unreconciled
    case cleared(ClearedStatus)
    case expense
    case incomeOrExpense
    case date(SearchDateKind, String)
    case amount(SearchAmountKind, String)
    case incomeFor(String)
}

/// All terms must match; repeated Empfänger:, Kategorie: and Konto: terms are OR'ed in one item.
public struct RegisterSearchQuery: Hashable, Sendable {
    private static let closedBudgetAccounts = "Geschlossene Budgetkonten"
    private static let closedOffBudgetAccounts = "Geschlossene Trackingkonten"
    public static let accountGroups =
        SidebarGroup.allCases.map(\.title) + [closedBudgetAccounts, closedOffBudgetAccounts]

    public var items: [SearchItem]

    public init(items: [SearchItem]) {
        self.items = items
    }

    public init(_ text: String, decimalSeparator: String = ".") {
        var items: [SearchItem] = []
        var positions: [String: Int] = [:]
        var values: [String: [String]] = [:]
        func merge(_ key: String, _ item: SearchItem) {
            if let index = positions[key] {
                items[index] = item
            } else {
                positions[key] = items.count
                items.append(item)
            }
        }
        let prepared = Self.preprocess(text, decimalSeparator: decimalSeparator)
        for term in prepared.components(separatedBy: ",") {
            switch Self.parseTerm(term) {
            case nil: continue
            case .item(let item): items.append(item)
            case .payee(let value):
                values["payee", default: []].append(value)
                merge("payee", .payees(values["payee"] ?? []))
            case .category(let value):
                values["category", default: []].append(value)
                merge("category", .categories(values["category"] ?? []))
            case .account(let value):
                values["account", default: []].append(value)
                merge("account", .accounts(values["account"] ?? []))
            }
        }
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }

    private enum ParsedTerm {
        case item(SearchItem)
        case payee(String)
        case category(String)
        case account(String)
    }

    /// With a comma decimal separator `12,50` means 12.50.
    static func preprocess(_ text: String, decimalSeparator: String) -> String {
        guard decimalSeparator == "," else { return text }
        var characters = Array(text)
        for index in characters.indices.dropFirst().dropLast()
        where characters[index] == "," && characters[index - 1].isASCIIDigit && characters[index + 1].isASCIIDigit {
            characters[index] = "."
        }
        return String(characters)
    }

    private static func parseTerm(_ raw: String) -> ParsedTerm? {
        let term = raw.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return nil }
        let prefix: String
        let value: String
        if let colon = term.firstIndex(of: ":") {
            prefix = term[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            value = term[term.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        } else {
            prefix = ""
            value = term
        }
        switch prefix {
        case "konto": return .account(value)
        case "ist": return isTerm(value).map { .item($0) }
        case "kategorie": return .category(value)
        case "empfänger": return .payee(value)
        case "memo": return .item(.memo(value))
        case "am": return .item(.date(.on, value))
        case "ab": return .item(.date(.after, value))
        case "bis": return .item(.date(.before, value))
        case "ausgang": return .item(amountTerm(value, outflow: true))
        case "eingang": return .item(amountTerm(value, outflow: false))
        case "einnahmen": return .item(.incomeFor(value))
        default: return .item(.anyField(value))
        }
    }

    private static func isTerm(_ value: String) -> SearchItem? {
        switch value.lowercased() {
        case "bestätigt": .approved(true)
        case "unbestätigt": .approved(false)
        case "fehler": .errorLevel(.error)
        case "erinnerung": .errorLevel(.forReview)
        case "nicht kategorisiert": .errorLevel(.needsCategory)
        case "gebucht": .cleared(.cleared)
        case "vorgemerkt": .cleared(.uncleared)
        case "abgeglichen": .cleared(.reconciled)
        case "gebucht oder abgeglichen": .clearedOrReconciled
        case "nicht abgeglichen": .unreconciled
        case "ausgabe": .expense
        case "einnahme oder ausgabe": .incomeOrExpense
        default: nil
        }
    }

    private static func amountTerm(_ value: String, outflow: Bool) -> SearchItem {
        let number = value.dropFirst().trimmingCharacters(in: .whitespaces)
        if value.hasPrefix(">") { return .amount(outflow ? .outflowMore : .inflowMore, number) }
        if value.hasPrefix("<") { return .amount(outflow ? .outflowLess : .inflowLess, number) }
        return .amount(outflow ? .outflowEquals : .inflowEquals, value)
    }
}

public struct RegisterSearchMatch: Hashable, Sendable {
    public var isVisible: Bool
    public var parentMatches: Bool
    public var subMatches: [String: Bool]

    public static let full = RegisterSearchMatch(isVisible: true, parentMatches: true, subMatches: [:])

    public func subMatches(_ subId: String) -> Bool { subMatches[subId] ?? true }

    public var expandsSplit: Bool { isVisible && (!parentMatches || subMatches.values.contains(false)) }

    /// A split counts only with its matching rows.
    public func searchAmount(of transaction: Transaction) -> Decimal {
        guard transaction.isSplit else { return transaction.amount }
        return Amount.sum(transaction.subtransactions.filter { subMatches($0.id) }.map(\.amount))
    }
}

public struct RegisterSearchEnvironment {
    let lookup: BudgetLookup
    let formatter: BudgetFormatter
    let today: DateWithoutTime
    let knownPayees: Set<String>
    let knownCategories: Set<String>

    public init(budget: Budget, today: DateWithoutTime) {
        self.init(lookup: BudgetLookup(budget), today: today)
    }

    public init(lookup: BudgetLookup, today: DateWithoutTime) {
        let budget = lookup.budget
        self.lookup = lookup
        self.today = today
        formatter = BudgetFormatter(metaData: budget.budgetMetaData)
        knownPayees = Set(budget.payees.map(\.name.lookupKey))
        let subIds = budget.categoryGroups.flatMap(\.categories).map(\.id)
        knownCategories = Set(subIds.map { lookup.categoryDisplayName($0).lookupKey })
    }

    var budget: Budget { lookup.budget }

    func account(_ accountId: String?) -> Account? {
        accountId.flatMap(lookup.account(withId:))
    }

    func payee(of transaction: Transaction) -> String {
        lookup.payeeName(of: transaction)
    }

    func payee(of sub: Subtransaction) -> String {
        lookup.payeeName(of: sub)
    }

    func category(of transaction: Transaction) -> String? {
        transaction.isSplit ? DefaultCategories.splitCategoryName : category(transaction.categoryId)
    }

    func category(_ categoryId: String?) -> String? {
        guard let categoryId, EntityID.isCategorized(categoryId) else { return nil }
        let name = lookup.categoryDisplayName(categoryId)
        return name.isEmpty ? nil : name
    }
}

extension RegisterSearchQuery {
    public func match(_ transaction: Transaction, in environment: RegisterSearchEnvironment) -> RegisterSearchMatch {
        let subs = transaction.subtransactions
        var parentFlag: Bool?
        var subFlags = [Bool?](repeating: nil, count: subs.count)
        for item in items {
            let result = evaluate(item, transaction, environment)
            if !(result.parent ?? false) && !result.subs.contains(true) {
                return RegisterSearchMatch(isVisible: false, parentMatches: false, subMatches: [:])
            }
            if let parent = result.parent { parentFlag = (parentFlag ?? true) && parent }
            for index in subs.indices {
                if let sub = result.subs[index] { subFlags[index] = (subFlags[index] ?? true) && sub }
            }
        }
        guard transaction.isSplit else { return .full }
        let resolvedSubs = subFlags.map { $0 ?? false }
        let parent = (parentFlag ?? false) || resolvedSubs.allSatisfy { $0 }
        let subMatches = Dictionary(uniqueKeysWithValues: zip(subs.map(\.id), resolvedSubs))
        return RegisterSearchMatch(
            isVisible: parent || resolvedSubs.contains(true), parentMatches: parent, subMatches: subMatches)
    }

    private struct ItemResult {
        var parent: Bool?
        var subs: [Bool?]
    }

    private func evaluate(_ item: SearchItem, _ transaction: Transaction, _ env: RegisterSearchEnvironment)
        -> ItemResult
    {
        let subs = transaction.subtransactions
        func perNode(parent: Bool, sub: (Subtransaction) -> Bool) -> ItemResult {
            ItemResult(parent: parent, subs: subs.map(sub))
        }
        func parentOnly(_ value: Bool) -> ItemResult {
            ItemResult(parent: value, subs: subs.map { _ in value })
        }
        switch item {
        case .anyField(let text):
            return perNode(
                parent: SearchText.containsInFields(Self.parentFields(transaction, env), text),
                sub: { SearchText.containsInFields(Self.subFields($0, env), text) })
        case .memo(let text):
            return perNode(
                parent: SearchText.containsInFields([.text(transaction.memo ?? "")], text),
                sub: { SearchText.containsInFields([.text($0.memo ?? "")], text) })
        case .payees(let values):
            let matcher = NameMatcher(values: values, known: env.knownPayees)
            let payee = env.payee(of: transaction)
            return perNode(
                parent: matcher.matches(payee),
                sub: {
                    let own = env.payee(of: $0)
                    return matcher.matches(own.isEmpty ? payee : own)
                })
        case .categories(let values):
            let matcher = NameMatcher(values: values, known: env.knownCategories)
            return perNode(
                parent: matcher.matches(env.category(of: transaction) ?? ""),
                sub: { matcher.matches(env.category($0.categoryId) ?? "") })
        case .accounts(let values):
            return parentOnly(Self.accountMatches(env.account(transaction.accountId), values))
        case .approved(let approved):
            return parentOnly(transaction.needsApproval != approved)
        case .errorLevel(.forReview):
            return parentOnly(env.lookup.errorState(of: transaction).level == .forReview)
        case .errorLevel(let level):
            return perNode(
                parent: env.lookup.errorState(of: transaction).level == level,
                sub: { env.lookup.errorState(of: $0, inAccount: transaction.accountId).level == level })
        case .clearedOrReconciled:
            return parentOnly(transaction.cleared != .uncleared)
        case .unreconciled:
            return parentOnly(transaction.cleared != .reconciled)
        case .cleared(let status):
            return parentOnly(transaction.cleared == status)
        case .expense, .incomeOrExpense:
            let expenseOnly = item == .expense
            let account = env.account(transaction.accountId)
            return perNode(
                parent: Self.isIncomeOrExpense(
                    account: account, target: env.account(env.lookup.transferAccountId(of: transaction)),
                    isIncome: env.budget.isReadyToAssign(transaction.categoryId), expenseOnly: expenseOnly),
                sub: {
                    Self.isIncomeOrExpense(
                        account: account, target: env.account(env.lookup.transferAccountId(of: $0)),
                        isIncome: env.budget.isReadyToAssign($0.categoryId), expenseOnly: expenseOnly)
                })
        case .date(let kind, let text):
            guard let date = env.formatter.parseDate(text, today: env.today) else { return parentOnly(false) }
            switch kind {
            case .on: return parentOnly(transaction.date == date)
            case .after: return parentOnly(transaction.date >= date)
            case .before: return parentOnly(transaction.date <= date)
            }
        case .amount(let kind, let text):
            guard let value = SearchText.number(text) else { return parentOnly(false) }
            return perNode(parent: kind.matches(transaction.amount, value), sub: { kind.matches($0.amount, value) })
        case .incomeFor(let text):
            guard let month = SearchText.incomeMonth(text, formatter: env.formatter, today: env.today) else {
                return parentOnly(false)
            }
            if transaction.isSplit {
                return ItemResult(
                    parent: nil,
                    subs: subs.map {
                        env.budget.isReadyToAssign($0.categoryId) && Self.isIn(month, transaction.date)
                    })
            }
            return parentOnly(env.budget.isReadyToAssign(transaction.categoryId) && Self.isIn(month, transaction.date))
        }
    }

    private static func parentFields(_ transaction: Transaction, _ env: RegisterSearchEnvironment) -> [SearchField] {
        [
            .text(env.payee(of: transaction)), .text(env.category(of: transaction) ?? ""),
            .text(transaction.memo ?? ""), .amount(transaction.outflow), .amount(transaction.inflow),
        ]
    }

    private static func subFields(_ sub: Subtransaction, _ env: RegisterSearchEnvironment) -> [SearchField] {
        [
            .text(env.payee(of: sub)), .text(env.category(sub.categoryId) ?? ""),
            .text(sub.memo ?? ""), .amount(sub.outflow), .amount(sub.inflow),
        ]
    }

    private static func accountMatches(_ account: Account?, _ values: [String]) -> Bool {
        guard let account else { return false }
        let groups = Set(values.map { $0.lowercased() })
        if SidebarGroup.allCases.contains(where: { groups.contains($0.title.lowercased()) && $0.contains(account) }) {
            return true
        }
        let closedGroup = account.onBudget ? closedBudgetAccounts : closedOffBudgetAccounts
        if account.closed && groups.contains(closedGroup.lowercased()) { return true }
        let groupNames = Set(accountGroups.map { $0.lowercased() })
        return values.contains {
            !$0.isEmpty && !groupNames.contains($0.lowercased())
                && account.name.localizedCaseInsensitiveContains($0)
        }
    }

    /// Transfers count only across the budget boundary.
    private static func isIncomeOrExpense(
        account: Account?, target: Account?, isIncome: Bool, expenseOnly: Bool
    ) -> Bool {
        if expenseOnly && isIncome { return false }
        guard let target else { return true }
        return (account?.onBudget ?? false) != target.onBudget
    }

    private static func isIn(_ month: DateWithoutTime, _ date: DateWithoutTime) -> Bool {
        date.monthKey == month.monthKey
    }
}

enum SearchField {
    case text(String)
    case amount(Decimal)
}

enum SearchText {
    /// Abakus's register search: text by lookup key, amounts as written, so "48.75" and "8.7" both find 48.75.
    static func containsInFields(_ fields: [SearchField], _ text: String) -> Bool {
        let key = text.lookupKey
        let amountText = isAmountText(key) ? key : nil
        return fields.contains { field in
            switch field {
            case .amount(let value): amountText.map { self.amountText(value).contains($0) } ?? false
            case .text(let value):
                value.isEmpty ? key.isEmpty : !key.isEmpty && value.lookupKey.contains(key)
            }
        }
    }

    private static func isAmountText(_ text: String) -> Bool {
        text.contains(where: \.isASCIIDigit) && text.count(where: { $0 == "." }) <= 1
            && text.allSatisfy { $0.isASCIIDigit || $0 == "." }
    }

    static func amountText(_ value: Decimal) -> String {
        let parts = NSDecimalNumber(decimal: value).stringValue.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return parts[0] + "." + fraction.padding(toLength: max(2, fraction.count), withPad: "0", startingAt: 0)
    }

    static func number(_ text: String) -> Decimal? {
        var digits = Substring(text.trimmingCharacters(in: .whitespaces))
        let negative = digits.first == "-"
        if digits.first == "-" || digits.first == "+" { digits = digits.dropFirst() }
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard !digits.isEmpty, parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
            digits.contains(where: \.isASCIIDigit),
            let value = Decimal(string: String(digits), locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return negative ? -value : value
    }

    static let englishMonths = FormatLocale.enUS.monthNames.map { $0.lowercased() }

    /// "März", "Mär 2026" or "3 2026"; the year defaults to this year.
    static func incomeMonth(_ text: String, formatter: BudgetFormatter, today: DateWithoutTime) -> DateWithoutTime? {
        let parts = text.split(separator: " ").map(String.init)
        guard (1...2).contains(parts.count) else { return nil }
        let name = parts[0].lowercased()
        let localized = formatter.dateLocale.monthNames.map { $0.lowercased() }
        var month: Int?
        for names in [englishMonths, localized] {
            if let index = names.firstIndex(of: name)
                ?? names.firstIndex(where: { name.count >= 3 && $0.hasPrefix(name) })
            {
                month = index + 1
                break
            }
        }
        if month == nil, let number = Int(name) { month = number }
        guard let month, (1...12).contains(month) else { return nil }
        guard let typedYear = parts.count == 2 ? Int(parts[1]) : today.year else { return nil }
        let year = typedYear < 100 ? typedYear + 2000 : typedYear
        guard DateWithoutTime.supportedYears.contains(year) else { return nil }
        return DateWithoutTime(year: year, month: month, day: 1)
    }
}

private struct NameMatcher {
    var exact: [String] = []
    var partial: [String] = []

    /// A value naming an existing entry matches exactly, others partially.
    init(values: [String], known: Set<String>) {
        for key in values.map(\.lookupKey) where !key.isEmpty {
            if known.contains(key) {
                exact.append(key)
            } else {
                partial.append(key)
            }
        }
    }

    func matches(_ name: String) -> Bool {
        if exact.isEmpty && partial.isEmpty { return name.isEmpty }
        let key = name.lookupKey
        guard !key.isEmpty else { return false }
        return exact.contains(key) || partial.contains { key.contains($0) }
    }
}

extension Transaction {
    public var needsApproval: Bool {
        !approved && source != .manual
    }
}
