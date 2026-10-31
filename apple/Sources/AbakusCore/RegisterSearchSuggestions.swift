import Foundation

public enum SearchSuggestionIcon: Hashable, Sendable {
    case calendarMonth, calendarSelect, calendarSpan, outflow, inflow
    case cleared(ClearedStatus)
}

public struct RegisterSearchSuggestion: Hashable, Sendable, Identifiable {
    public var id: String
    public var prefix: String
    /// HTML; only `<b>` and `<i>` are used.
    public var description: String
    public var icon: SearchSuggestionIcon?
    public var indent: Int
    public var isBlank: Bool
    /// What picking the row puts into the search box; empty for hint rows.
    public var searchText: String

    init(
        id: String, prefix: String, description: String, icon: SearchSuggestionIcon? = nil, indent: Int = 0,
        isBlank: Bool = false, searchText: String
    ) {
        self.id = id
        self.prefix = prefix
        self.description = description
        self.icon = icon
        self.indent = indent
        self.isBlank = isBlank
        self.searchText = searchText
    }
}

public struct RegisterSearchSuggestions {
    public static let blank = "<Leer>"

    let budget: Budget
    let formatter: BudgetFormatter
    let isAllAccounts: Bool
    let today: DateWithoutTime

    public init(budget: Budget, isAllAccounts: Bool, today: DateWithoutTime) {
        self.budget = budget
        self.isAllAccounts = isAllAccounts
        self.today = today
        formatter = BudgetFormatter(metaData: budget.budgetMetaData)
    }

    public func suggestions(for typed: String) -> [RegisterSearchSuggestion] {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        var groups = [dates(text)]
        if isAllAccounts { groups.append(accounts(text)) }
        groups += [
            amounts(text), income(text), approved(text), cleared(text), payees(text), categories(text), freeText(text),
        ]
        return groups.flatMap { $0 }
    }

    private func dates(_ text: String) -> [RegisterSearchSuggestion] {
        var items: [RegisterSearchSuggestion] = []
        let lower = text.lowercased()
        let mentionsPrefix = ["am:", "ab:", "bis:"].contains { lower.contains($0) }
        if !mentionsPrefix && formatter.parseDate(text, today: today) == nil {
            items.append(
                RegisterSearchSuggestion(
                    id: "dates", prefix: "Datum",
                    description: "(<i>Datum als \(formatter.shortDatePattern) eingeben</i>)",
                    icon: .calendarMonth, searchText: ""))
        }
        let typed: [(String, String, SearchSuggestionIcon)] = [
            ("Am:", "Am <b>{0}</b>", .calendarSelect), ("Bis:", "Am oder vor dem <b>{0}</b>", .calendarSpan),
            ("Ab:", "Am oder nach dem <b>{0}</b>", .calendarSpan),
        ]
        for (prefix, template, icon) in typed {
            guard let value = typedValue(prefix: prefix, text: text) else { continue }
            if value.isEmpty {
                items.append(
                    RegisterSearchSuggestion(
                        id: prefix, prefix: prefix, description: Self.substitute(template, formatter.shortDatePattern),
                        icon: icon, searchText: ""))
            } else if let date = formatter.parseDate(value, today: today) {
                items.append(
                    RegisterSearchSuggestion(
                        id: prefix, prefix: prefix, description: Self.substitute(template, formatter.dateShort(date)),
                        icon: icon, searchText: prefix + value))
            }
        }
        return items
    }

    private func amounts(_ text: String) -> [RegisterSearchSuggestion] {
        let kinds: [(SearchAmountKind, String, String, String?)] = [
            (.outflowEquals, "Ausgang:", "Ausgang gleich <b>{0}</b>", nil),
            (.outflowMore, "Ausgang:", "Ausgang mindestens <b>{0}</b>", ">"),
            (.outflowLess, "Ausgang:", "Ausgang höchstens <b>{0}</b>", "<"),
            (.inflowEquals, "Eingang:", "Eingang gleich <b>{0}</b>", nil),
            (.inflowMore, "Eingang:", "Eingang mindestens <b>{0}</b>", ">"),
            (.inflowLess, "Eingang:", "Eingang höchstens <b>{0}</b>", "<"),
        ]
        return kinds.compactMap { kind, prefix, template, operation in
            let icon: SearchSuggestionIcon = prefix == "Ausgang:" ? .outflow : .inflow
            let id = "\(kind)"
            guard var value = typedValue(prefix: prefix, text: text) else { return nil }
            if value.isEmpty {
                return RegisterSearchSuggestion(
                    id: id, prefix: prefix, description: Self.substitute(template, formatter.currencyNoSymbol(0)),
                    icon: icon, searchText: prefix + (operation.map { " \($0)" } ?? "") + "0")
            }
            if value.hasPrefix(">") || value.hasPrefix("<") {
                guard String(value.prefix(1)) == operation else { return nil }
                value = String(value.dropFirst())
            }
            guard let number = SearchText.number(value) else { return nil }
            return RegisterSearchSuggestion(
                id: id, prefix: prefix, description: Self.substitute(template, formatter.currency(number)), icon: icon,
                searchText: prefix + (operation.map { " \($0)" } ?? "") + value)
        }
    }

    private func income(_ text: String) -> [RegisterSearchSuggestion] {
        let prefix = "Einnahmen:"
        let template = "(<i>Monat eingeben, etwa „Einnahmen: {0}“</i>)"
        guard let value = typedValue(prefix: prefix, text: text) else { return [] }
        if value.isEmpty {
            return [
                RegisterSearchSuggestion(
                    id: "income", prefix: prefix, description: Self.substitute(template, formatter.monthHeader(today)),
                    icon: .calendarSelect, searchText: "")
            ]
        }
        guard let month = SearchText.incomeMonth(value, formatter: formatter, today: today) else { return [] }
        return [
            RegisterSearchSuggestion(
                id: "income", prefix: prefix, description: Self.substitute(template, formatter.monthHeader(month)),
                icon: .calendarSelect, searchText: prefix + " " + value)
        ]
    }

    private func approved(_ text: String) -> [RegisterSearchSuggestion] {
        ["Bestätigt", "Unbestätigt"].compactMap { plain("is:\($0)", prefix: "Ist: ", description: $0, text: text) }
    }

    private func cleared(_ text: String) -> [RegisterSearchSuggestion] {
        let entries: [(String, SearchSuggestionIcon?)] = [
            ("Gebucht", .cleared(.cleared)), ("Vorgemerkt", .cleared(.uncleared)),
            ("Abgeglichen", .cleared(.reconciled)), ("Gebucht oder abgeglichen", nil), ("Nicht abgeglichen", nil),
        ]
        return entries.compactMap { plain("is:\($0.0)", prefix: "Ist: ", description: $0.0, icon: $0.1, text: text) }
    }

    private func payees(_ text: String) -> [RegisterSearchSuggestion] {
        var items: [RegisterSearchSuggestion] = []
        if let blank = plain("payee:", prefix: "Empfänger: ", description: "", text: text) {
            items.append(withBlank(blank))
        }
        let payees = budget.payees.filter(budget.isSuggested).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for payee in payees {
            if let item = plain("payee:\(payee.id)", prefix: "Empfänger: ", description: payee.name, text: text) {
                items.append(item)
            }
        }
        return items
    }

    private func categories(_ text: String) -> [RegisterSearchSuggestion] {
        let prefix = "Kategorie: "
        var items: [RegisterSearchSuggestion] = []
        if let blank = plain("category:", prefix: prefix, description: "", text: text) {
            items.append(withBlank(blank))
        }
        let split = DefaultCategories.splitCategoryName
        if let item = plain("category:split", prefix: prefix, description: split, text: text) {
            var bold = item
            bold.description = "<b>\(Self.escape(split))</b>"
            items.append(bold)
        }
        for master in [budget.incomeGroupListing] + budget.budgetCategoryGroups {
            let subs = master.categories
            if categoryFilter(master: master.name, sub: nil, siblings: subs.map(\.name), text: text) {
                items.append(
                    RegisterSearchSuggestion(
                        id: "category:\(master.id)", prefix: prefix,
                        description: "<b>\(Self.escape(master.name))</b>",
                        searchText: prefix + master.name))
            }
            for sub in subs {
                let displayName = budget.categoryDisplayName(sub.id)
                guard categoryFilter(master: master.name, sub: sub.name, siblings: [], text: text) else { continue }
                items.append(
                    RegisterSearchSuggestion(
                        id: "category:\(sub.id)", prefix: prefix, description: Self.escape(sub.name), indent: 15,
                        searchText: prefix + displayName))
            }
        }
        return items
    }

    private func accounts(_ text: String) -> [RegisterSearchSuggestion] {
        let prefix = "Konto: "
        var items: [RegisterSearchSuggestion] = []
        for (index, group) in RegisterSearchQuery.accountGroups.enumerated() {
            guard var item = plain("account:\(group)", prefix: prefix, description: group, text: text) else { continue }
            item.description = "<b>\(group)</b>"
            item.indent = index >= 3 ? 7 : 0
            items.append(item)
        }
        let accounts = budget.accounts.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for account in accounts {
            guard
                var item = plain(
                    "account:\(account.id)", prefix: prefix, description: account.name, text: text)
            else { continue }
            item.indent = 15
            items.append(item)
        }
        return items
    }

    private func freeText(_ text: String) -> [RegisterSearchSuggestion] {
        let escaped = Self.escape(text)
        let finds: [(String, String)] = [
            ("", "in allen Feldern"), ("Empfänger: ", "im Empfänger"), ("Kategorie: ", "in der Kategorie"),
            ("Memo: ", "im Memo"),
        ]
        var items = finds.map { prefix, field in
            RegisterSearchSuggestion(
                id: "find:\(prefix)", prefix: prefix, description: "„<b>\(escaped)</b>“ \(field) suchen",
                searchText: prefix + text)
        }
        for name in ["Fehler", "Nicht kategorisiert", "Erinnerung"] {
            if let item = plain("is:\(name)", prefix: "Ist:", description: name, text: text) { items.append(item) }
        }
        return items
    }

    private func plain(
        _ id: String, prefix: String, description: String, icon: SearchSuggestionIcon? = nil, text: String
    ) -> RegisterSearchSuggestion? {
        guard Self.baseFilter(prefix: prefix, description: description, text: text) else { return nil }
        return RegisterSearchSuggestion(
            id: id, prefix: prefix, description: Self.escape(description), icon: icon, searchText: prefix + description)
    }

    private func withBlank(_ item: RegisterSearchSuggestion) -> RegisterSearchSuggestion {
        var blank = item
        blank.isBlank = true
        blank.description = Self.blank
        return blank
    }

    static func baseFilter(prefix: String, description: String, text: String) -> Bool {
        if prefixMatches(prefix, text) {
            let parts = text.components(separatedBy: ":")
            if parts.count == 1 || parts[1].trimmingCharacters(in: .whitespaces).isEmpty { return true }
            if parts.count == 2 && description.localizedCaseInsensitiveContains(parts[1].trimmed) { return true }
        }
        return (prefix + description).localizedCaseInsensitiveContains(text)
    }

    static func prefixMatches(_ prefix: String, _ text: String) -> Bool {
        let head = (text.components(separatedBy: ":").first ?? "").trimmed
        return !head.isEmpty && prefix.lowercased().hasPrefix(head.lowercased())
    }

    /// The value typed for a `Prefix:` item: "" right after the prefix, nil when the text names another prefix.
    private func typedValue(prefix: String, text: String) -> String? {
        guard Self.prefixMatches(prefix, text) else { return text }
        let parts = text.components(separatedBy: ":")
        if parts.count == 1 { return "" }
        guard parts.count == 2 else { return nil }
        return parts[1].trimmed
    }

    private func categoryFilter(master: String, sub: String?, siblings: [String], text: String) -> Bool {
        let description = sub.map { "\(master): \($0)" } ?? master
        if Self.baseFilter(prefix: "Kategorie: ", description: description, text: text) { return true }
        let parts = text.components(separatedBy: ":").map(\.trimmed)
        if Self.prefixMatches("Kategorie: ", text) && parts.count == 1 { return true }
        var masterPart = ""
        var subPart = ""
        var alternative = ""
        if parts.count == 2 {
            (masterPart, subPart, alternative) = (parts[0], parts[1], parts[1])
        } else if parts.count == 3 {
            (masterPart, subPart) = (parts[1], parts[2])
        }
        if !masterPart.isEmpty {
            if let sub {
                if master.localizedCaseInsensitiveContains(masterPart) {
                    return subPart.isEmpty || sub.localizedCaseInsensitiveContains(subPart)
                }
                return !alternative.isEmpty && master.localizedCaseInsensitiveContains(alternative)
            }
            return master.localizedCaseInsensitiveContains(masterPart)
                || (!alternative.isEmpty && master.localizedCaseInsensitiveContains(alternative))
        }
        return sub == nil && siblings.contains { $0.localizedCaseInsensitiveContains(text) }
    }

    static func substitute(_ template: String, _ value: String) -> String {
        template.replacingOccurrences(of: "{0}", with: escape(value))
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
