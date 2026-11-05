import AbakusCore
import AbakusUI
import SwiftUI

/// An overspent Verfügbar's cover list: a click on a source covers from it.
struct BudgetAvailablePopover: View {
    let controller: BudgetCalloutController
    let form: BudgetAvailableForm

    var body: some View {
        BudgetCoverList(controller: controller, form: form, rowHeight: BudgetCoverList.fineRowHeight)
            .font(ThemeFont.body.font)
            .frame(minWidth: 280, maxWidth: 320)
    }
}
