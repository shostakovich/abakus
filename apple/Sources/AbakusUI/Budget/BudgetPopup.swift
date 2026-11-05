import AbakusCore
import SwiftUI

/// A callout, menu or help the budget screen was asked to show; the controls only record it here.
public enum BudgetPopup: Hashable, Sendable {
    case monthMenu(month: DateWithoutTime)
    /// `month` is the one the target shows; without it, today's if shown, else the first shown.
    case editCategory(categoryId: String, month: DateWithoutTime? = nil)
    /// The touch sheet of a category or group in one month: Verfügbar and assigning beside what `editCategory` has.
    case category(month: DateWithoutTime, categoryId: String)
    case outflowSummary(month: DateWithoutTime, source: OutflowSummarySource)
    case available(month: DateWithoutTime, categoryId: String)

    public var anchor: BudgetPopupAnchor {
        switch self {
        case .monthMenu(let month): .monthMenu(month)
        case .editCategory(let id, _), .category(_, let id): .categoryRow(id)
        case .outflowSummary(let month, .category(let id)), .outflowSummary(let month, .masterCategory(let id)):
            .outflows(month, id)
        case .outflowSummary(let month, .allOutflows): .totalsOutflows(month)
        case .available(let month, let id): .balance(month, id)
        }
    }
}

public enum BudgetPopupAnchor: Hashable, Sendable {
    case monthMenu(DateWithoutTime)
    case totalsOutflows(DateWithoutTime)
    case categoryRow(String)
    case outflows(DateWithoutTime, String)
    case balance(DateWithoutTime, String)
}

/// Carries the bounds of the control the presented popup belongs to; only that control publishes.
public struct BudgetPopupAnchorKey: PreferenceKey {
    public static let defaultValue: Anchor<CGRect>? = nil

    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct BudgetPopupAnchorModifier: ViewModifier {
    let anchor: BudgetPopupAnchor
    let model: BudgetViewModel

    func body(content: Content) -> some View {
        let isAnchor = model.popupAnchor == anchor
        content.transformAnchorPreference(key: BudgetPopupAnchorKey.self, value: .bounds) { value, bounds in
            if isAnchor { value = bounds }
        }
    }
}

extension View {
    package func budgetPopupAnchor(_ anchor: BudgetPopupAnchor, of model: BudgetViewModel) -> some View {
        modifier(BudgetPopupAnchorModifier(anchor: anchor, model: model))
    }
}

/// The bounds of the edited cell while it refuses what was typed, so its reason can stand beside it.
public struct BudgetAmountErrorAnchorKey: PreferenceKey {
    public static let defaultValue: Anchor<CGRect>? = nil

    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    package func budgetAmountErrorAnchor(_ isShown: Bool) -> some View {
        anchorPreference(key: BudgetAmountErrorAnchorKey.self, value: .bounds) { isShown ? $0 : nil }
    }
}
