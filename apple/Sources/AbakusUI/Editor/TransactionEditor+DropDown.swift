import AbakusCore
import Foundation

extension TransactionEditor {
    func dropDownKind(for field: EditorFieldID) -> DropDownKind? {
        switch (field.isSub, field.column) {
        case (_, .payee): .payee
        case (false, .category): .category
        case (false, .account): isAllAccounts ? .account : nil
        case (true, .category): .subCategory
        default: nil
        }
    }

    func allItems(_ kind: DropDownKind) -> [DropDownItem] {
        switch kind {
        case .payee: catalog.payeeItems(excludingAccount: clone.accountId)
        case .category: catalog.categoryItems(includeSplit: leader == nil)
        case .subCategory: catalog.categoryItems(includeSplit: false)
        case .account: catalog.accountItems(for: clone)
        }
    }

    /// `showDropDown(true)`: the full list; the category list also highlights the row matching the text.
    func showDropDown(for field: EditorFieldID, unfiltered: Bool) {
        guard let kind = dropDownKind(for: field) else { return }
        let current = text(field)
        let all = allItems(kind)
        let items = unfiltered ? all : DropDownMatching.filter(all, kind: kind, text: current)
        guard !items.isEmpty else { return }
        var highlighted: Int?
        if unfiltered && (kind == .category || kind == .subCategory) && !current.isEmpty {
            highlighted = items.firstIndex {
                $0.isEnabled && !DropDownMatching.filter([$0], kind: kind, text: current).isEmpty
            }
        }
        dropDown = DropDownState(
            field: field, kind: kind, items: items, highlighted: highlighted,
            scrollToken: (dropDown?.scrollToken ?? 0) + 1)
    }

    /// Filter, open unless the text got shorter, highlight, complete.
    func autoComplete(_ field: EditorFieldID, kind: DropDownKind, isDeletion: Bool) {
        let current = text(field)
        let items = DropDownMatching.filter(allItems(kind), kind: kind, text: current)
        guard !items.isEmpty else {
            dropDown = nil
            return
        }
        if dropDown?.field == field {
            if current.isEmpty || isDeletion { dropDown = nil }
        } else if !isDeletion && !current.isEmpty {
            dropDown = DropDownState(field: field, kind: kind, items: items, highlighted: nil)
        }
        guard var list = dropDown, list.field == field else { return }
        list.items = items
        list.highlighted = DropDownMatching.highlight(items, kind: kind, text: current)
        list.scrollToken += 1
        dropDown = list
        refreshCompletion(field)
    }

    func refreshCompletion(_ field: EditorFieldID) {
        guard let item = dropDown?.highlightedItem else { return }
        let caret = min(fieldSelection.location, (text(field) as NSString).length)
        let (completed, range) = DropDownMatching.completion(item, text: text(field), caret: caret)
        setText(field, completed)
        select(field, range)
    }

    func moveHighlight(by offset: Int) {
        guard var list = dropDown else { return }
        let enabled = list.items.indices.filter { list.items[$0].isEnabled }
        guard let first = enabled.first, let last = enabled.last else { return }
        let target: Int
        if let current = list.highlighted, let position = enabled.firstIndex(of: current) {
            target = enabled[min(max(position + offset, 0), enabled.count - 1)]
        } else {
            target = offset > 0 ? first : last
        }
        list.highlighted = target
        list.scrollToken += 1
        dropDown = list
        refreshCompletion(list.field)
    }

    func acceptHighlighted(_ field: EditorFieldID, backward: Bool) {
        guard let item = dropDown?.highlightedItem else { return }
        dropDown = nil
        setText(field, item.value)
        select(field, NSRange(location: (item.value as NSString).length, length: 0))
        if let move = commit(field, reason: .clickedItem(backward: backward)) { apply(move) }
    }

    public func dropDownRowClicked(_ index: Int) {
        guard var list = dropDown, list.items.indices.contains(index), list.items[index].isEnabled else { return }
        list.highlighted = index
        dropDown = list
        acceptHighlighted(list.field, backward: false)
    }

    /// Hovering highlights a row, leaving the list clears the highlight.
    public func dropDownRowHovered(_ index: Int?) {
        guard var list = dropDown else { return }
        if let index, list.items.indices.contains(index), !list.items[index].isEnabled { return }
        list.highlighted = index
        dropDown = list
    }

    public func dropDownArrowClicked(_ field: EditorFieldID) {
        if dropDown?.field == field {
            dropDown = nil
            return
        }
        if focus != .field(field) { fieldClicked(field) }
        if dropDown?.field != field { showDropDown(for: field, unfiltered: true) }
    }

    public func dropDownFooterClicked() {
        guard let list = dropDown else { return }
        dropDown = nil
        switch list.kind {
        case .payee:
            let typed = text(list.field).trimmingCharacters(in: .whitespaces)
            onEditPayees(typed.isEmpty ? nil : typed)
        case .category, .subCategory:
            pendingCategoryField = list.field
            addCategoryForm = AddCategoryForm(masterName: "", name: "")
        default:
            break
        }
    }

    func startTransfer() {
        let field = EditorFieldID.main(.payee)
        setFocus(.field(field), commitCurrent: false)
        let typed = Payee.transferPrefix
        setText(field, typed)
        select(field, NSRange(location: (typed as NSString).length, length: 0))
        let items = DropDownMatching.filter(allItems(.payee), kind: .payee, text: typed)
        dropDown = DropDownState(
            field: field, kind: .payee, items: items,
            highlighted: items.firstIndex { if case .transfer = $0.kind { true } else { false } })
    }
}
