import AbakusCore
import Foundation

public enum DropDownKind: Hashable, Sendable {
    case payee, category, account, subCategory

    public var rowCount: Int { 9 }
    public var minWidth: CGFloat {
        switch self {
        case .payee, .account: 200
        case .category, .subCategory: 210
        }
    }
    public var headerTitle: String? {
        switch self {
        case .payee: "Empfänger"
        case .category, .subCategory: "Kategorien"
        case .account: "Konten"
        }
    }
    public var footerTitle: String? {
        switch self {
        case .payee: "Empfänger verwalten …"
        case .category, .subCategory: "Kategorie hinzufügen …"
        case .account: nil
        }
    }
}

public struct DropDownItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case prompt
        case payee(name: String)
        case transfersHeader
        case transfer(accountName: String)
        case split
        case masterHeader(name: String, isIncome: Bool)
        case category(id: String, masterName: String, name: String, isIncome: Bool)
        case accountHeader
        case account(id: String)
    }

    public static let emptyPayeesPrompt =
        "Noch keine Empfänger. Eingegebene Empfänger werden gemerkt und hier angeboten."
    public static let transfersHeader = "Umbuchung mit Konto:"

    public var id: String
    public var kind: Kind
    public var label: String
    /// Text the field gets when the row is chosen (the list's label function).
    public var value: String
    public var group: String?
    public var drawTopBorder = false
    public var balance: Decimal?

    public var isEnabled: Bool {
        switch kind {
        case .prompt, .transfersHeader, .masterHeader, .accountHeader: false
        default: true
        }
    }
}

struct DropDownCatalog {
    let budget: Budget
    let formatter: BudgetFormatter
    let today: DateWithoutTime

    func payeeItems(excludingAccount accountId: String?) -> [DropDownItem] {
        let payees = budget.payees.filter { !$0.isTransferPayee && !$0.hidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var items: [DropDownItem] = []
        if payees.isEmpty {
            items.append(
                DropDownItem(
                    id: "prompt", kind: .prompt, label: DropDownItem.emptyPayeesPrompt, value: ""))
        }
        items += payees.map {
            DropDownItem(id: $0.id, kind: .payee(name: $0.name), label: $0.name, value: $0.name)
        }
        let transfers = transferItems(excludingAccount: accountId)
        if !transfers.isEmpty {
            items.append(
                DropDownItem(
                    id: "transfers", kind: .transfersHeader, label: DropDownItem.transfersHeader, value: "",
                    group: "transfers"))
            items += transfers
        }
        return items
    }

    /// The list shows only the account name.
    private func transferItems(excludingAccount accountId: String?) -> [DropDownItem] {
        budget.sortedAccounts.filter { !$0.closed && $0.id != accountId }.map { account in
            DropDownItem(
                id: "transfer:" + account.id, kind: .transfer(accountName: account.name),
                label: account.name, value: account.transferPayeeName, group: "transfers")
        }
    }

    func categoryItems(includeSplit: Bool) -> [DropDownItem] {
        var items: [DropDownItem] = []
        if includeSplit {
            items.append(
                DropDownItem(
                    id: "split", kind: .split, label: DefaultCategories.splitCategoryName,
                    value: DefaultCategories.splitCategoryName))
        }
        let income = budget.incomeGroupListing
        items.append(
            DropDownItem(
                id: income.id, kind: .masterHeader(name: income.name, isIncome: true), label: income.name + ":",
                value: "", group: income.id, drawTopBorder: true))
        let id = budget.readyToAssignCategoryId
        let name = DefaultCategories.readyToAssignName
        items.append(
            DropDownItem(
                id: id, kind: .category(id: id, masterName: income.name, name: name, isIncome: true), label: name,
                value: name, group: income.id))
        let balances = budget.categoryBalances(today: today)
        for (index, master) in budget.budgetCategoryGroups.enumerated() {
            items.append(
                DropDownItem(
                    id: master.id, kind: .masterHeader(name: master.name, isIncome: false),
                    label: master.name + ":", value: "", group: master.id, drawTopBorder: index == 0))
            for sub in master.categories {
                items.append(
                    DropDownItem(
                        id: sub.id,
                        kind: .category(id: sub.id, masterName: master.name, name: sub.name, isIncome: false),
                        label: sub.name, value: "\(master.name): \(sub.name)", group: master.id,
                        balance: balances[sub.id] ?? 0))
            }
        }
        return items
    }

    func accountItems(for transaction: Transaction) -> [DropDownItem] {
        let excluded = transaction.transferTransactionId.flatMap(budget.transaction(withId:))?.accountId
        let accounts = budget.sortedAccounts.filter { $0.id != excluded }
        func item(_ account: Account, group: String) -> DropDownItem {
            DropDownItem(
                id: account.id, kind: .account(id: account.id), label: account.name,
                value: account.name, group: group)
        }
        func header(_ title: String, group: String) -> DropDownItem {
            DropDownItem(id: "header:" + group, kind: .accountHeader, label: title, value: "", group: group)
        }
        var items = accounts.filter { !$0.closed && $0.onBudget }.map { item($0, group: "onBudget") }
        let offBudget = accounts.filter { !$0.closed && !$0.onBudget }
        if !offBudget.isEmpty {
            items.append(header(SidebarGroup.offBudgetAccounts.title, group: "offBudget"))
            items += offBudget.map { item($0, group: "offBudget") }
        }
        if let own = accounts.first(where: { $0.id == transaction.accountId && $0.closed }) {
            items.append(header(SidebarGroup.closedAccounts.title, group: "closed"))
            items.append(item(own, group: "closed"))
        }
        return items
    }
}

enum DropDownMatching {
    static func filter(_ items: [DropDownItem], kind: DropDownKind, text rawText: String) -> [DropDownItem] {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return items }
        let matching = items.filter { item in
            switch item.kind {
            case .prompt: true
            case .payee(let name): name.localizedCaseInsensitiveContains(text)
            case .transfer:
                transferMatches(item.value, accountName: item.transferAccountName, text: text, prefix: false)
            case .split: startsWith(item.label, text)
            case .category: categoryMatches(item, text: text)
            case .account: startsWith(item.label, text)
            case .transfersHeader, .masterHeader, .accountHeader: false
            }
        }
        let groups = Set(matching.compactMap(\.group))
        return items.filter { item in
            switch item.kind {
            case .transfersHeader, .accountHeader: return groups.contains(item.group ?? "")
            case .masterHeader(let name, _):
                let parts = text.components(separatedBy: ":")
                let headerMatches = parts.count == 1 && startsWith(name, parts[0].trimmingCharacters(in: .whitespaces))
                return headerMatches || groups.contains(item.group ?? "")
            default:
                return matching.contains(item)
            }
        }
    }

    static func highlight(_ items: [DropDownItem], kind: DropDownKind, text: String) -> Int? {
        switch kind {
        case .payee: payeeHighlight(items, text: text)
        case .category, .subCategory: categoryHighlight(items, text: text)
        case .account: items.firstIndex { $0.isEnabled }
        }
    }

    static func completion(_ item: DropDownItem, text: String, caret: Int) -> (String, NSRange) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let typed = text as NSString
        let prefix = typed.substring(to: min(caret, typed.length))
        /// Folding can change the length, so the rest starts where the folded match ends.
        func keep(_ name: String) -> (String, NSRange) {
            let typedPrefix = prefix.drop { $0 == " " }
            let rest: String
            if let match = name.range(of: typedPrefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) {
                rest = String(name[match.upperBound...])
            } else {
                rest = (name as NSString).length > caret ? (name as NSString).substring(from: caret) : ""
            }
            let result = prefix + rest
            return (result, NSRange(location: caret, length: (result as NSString).length - caret))
        }
        func whole(_ value: String, from start: Int = 0) -> (String, NSRange) {
            (value, NSRange(location: start, length: (value as NSString).length - start))
        }
        switch item.kind {
        case .transfer(let account):
            if trimmed.hasSuffix(":"),
                startsWith("Transfer", String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces))
            {
                let colon = (item.value as NSString).range(of: ":").location
                return whole(item.value, from: colon + 2)
            }
            if startsWith(account, trimmed) { return keep(account) }
            if startsWith(item.value, trimmed) { return keep(item.value) }
        case .payee(let name):
            if startsWith(name, trimmed) { return keep(name) }
        case .category(_, let master, let name, _):
            if trimmed.hasSuffix(":"),
                startsWith(master, String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces))
            {
                let colon = (item.value as NSString).range(of: ":").location
                if colon != NSNotFound { return whole(item.value, from: colon + 2) }
            }
            if startsWith(name, trimmed) { return keep(name) }
        default:
            break
        }
        return startsWith(item.value, text) ? keep(item.value) : whole(item.value)
    }

    private static func payeeHighlight(_ items: [DropDownItem], text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(":") {
            let before = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            if !before.isEmpty && startsWith("Transfer", before) {
                return items.firstIndex { if case .transfer = $0.kind { true } else { false } }
            }
        }
        return items.firstIndex { item in
            guard item.isEnabled else { return false }
            switch item.kind {
            case .payee(let name): return startsWith(name, text)
            case .transfer:
                return transferMatches(item.value, accountName: item.transferAccountName, text: text, prefix: true)
            default: return false
            }
        }
    }

    private static func categoryHighlight(_ items: [DropDownItem], text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(":") {
            let before = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            guard !before.isEmpty else { return nil }
            return items.firstIndex { item in
                guard case .category(_, let master, _, _) = item.kind else { return false }
                return startsWith(master, before)
            }
        }
        var fullNameMatch: Int?
        var splitMatch: Int?
        for (index, item) in items.enumerated() where item.isEnabled {
            switch item.kind {
            case .category(_, _, let name, let isIncome):
                if startsWith(isIncome ? item.value : name, text) { return index }
                if fullNameMatch == nil && startsWith(item.value, text) { fullNameMatch = index }
            default:
                if splitMatch == nil && startsWith(item.label, text) { splitMatch = index }
            }
        }
        return fullNameMatch ?? splitMatch
    }

    static func transferMatches(_ payeeName: String, accountName: String, text: String, prefix: Bool) -> Bool {
        let parts = text.components(separatedBy: ":")
        let before = parts[0].trimmingCharacters(in: .whitespaces)
        let after = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        if startsWith("Transfer", before) {
            if after.isEmpty { return true }
            if prefix ? startsWith(accountName, after) : accountName.localizedCaseInsensitiveContains(after) {
                return true
            }
        }
        return prefix ? startsWith(payeeName, text) : payeeName.localizedCaseInsensitiveContains(text)
    }

    private static func categoryMatches(_ item: DropDownItem, text: String) -> Bool {
        guard case .category(_, let master, let name, let isIncome) = item.kind else { return false }
        let parts = text.components(separatedBy: ":")
        if parts.count == 1 {
            return isIncome ? startsWith(item.value, text) : startsWith(name, text) || startsWith(item.value, text)
        }
        let before = parts[0].trimmingCharacters(in: .whitespaces)
        let after = parts[1].trimmingCharacters(in: .whitespaces)
        return startsWith(master, before) && startsWith(name, after)
    }

    static func startsWith(_ text: String, _ prefix: String) -> Bool {
        guard !prefix.isEmpty else { return true }
        return text.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension DropDownItem {
    var transferAccountName: String {
        if case .transfer(let name) = kind { return name }
        return ""
    }
}
