import AbakusCore
import SwiftUI

/// A callout, menu or help the budget screen was asked to show; the controls only record it here.
public enum BudgetPopup: Hashable, Sendable {
    case monthQuickBudget(month: DateWithoutTime)
    case assignToCategory(month: DateWithoutTime)
    /// `month` is the one the target shows; without it, today's if shown, else the first shown.
    case editCategory(categoryId: String, month: DateWithoutTime? = nil)
    case outflowSummary(month: DateWithoutTime, source: OutflowSummarySource)
    case incomeSummary(month: DateWithoutTime)
    case outflowHelp(month: DateWithoutTime, categoryId: String)
    case available(month: DateWithoutTime, categoryId: String)

    public var anchor: BudgetPopupAnchor {
        switch self {
        case .monthQuickBudget(let month), .assignToCategory(let month): .monthQuickBudget(month)
        case .editCategory(let id, _): .categoryRow(id)
        case .outflowSummary(let month, .category(let id)), .outflowSummary(let month, .masterCategory(let id)),
            .outflowHelp(let month, let id):
            .outflows(month, id)
        case .outflowSummary(let month, .allOutflows): .totalsOutflows(month)
        case .incomeSummary(let month): .incomeLine(month)
        case .available(let month, let id): .balance(month, id)
        }
    }
}

public enum BudgetPopupAnchor: Hashable, Sendable {
    case monthQuickBudget(DateWithoutTime)
    case incomeLine(DateWithoutTime)
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
    func budgetPopupAnchor(_ anchor: BudgetPopupAnchor, of model: BudgetViewModel) -> some View {
        modifier(BudgetPopupAnchorModifier(anchor: anchor, model: model))
    }
}
