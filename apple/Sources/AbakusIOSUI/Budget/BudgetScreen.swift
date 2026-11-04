#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct BudgetScreen: View {
        static let summary = PresentationDetent.fraction(0.72)

        let model: BudgetViewModel
        let dialogs: [PresentedDialog]
        @Environment(\.horizontalSizeClass) private var sizeClass
        @State private var width: CGFloat = 0
        @ScaledMetric private var minimumMonthWidth = BudgetTouchLayout.minimumMonthWidth

        private var layout: BudgetTouchLayout {
            BudgetTouchLayout(isCompact: sizeClass == .compact, width: width, minimumMonthWidth: minimumMonthWidth)
        }

        var body: some View {
            Group {
                switch layout {
                case .phone: BudgetPhoneView(model: model)
                case .wide(_, let categoryWidth):
                    BudgetWideView(model: model, dialogs: dialogs, categoryWidth: categoryWidth)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .onChange(of: layout, initial: true) {
                if layout == .phone { model.commitEdit() }
                model.touchLayout = layout
            }
            .onChange(of: model.isHeaderExpanded, initial: true) { _, expanded in
                withAnimation(.motion(BudgetStyle.headerResize)) { model.headerProgress = expanded ? 1 : 0 }
            }
            .navigationTitle(model.shownMonthsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { BudgetTitleMenu(model: model) }
            }
            .sheet(isPresented: isSheetShown) {
                BudgetSheet(model: model)
                    .modifier(DialogAlert(dialogs: dialogs))
                    .modifier(BudgetSheetDetents(callouts: model.callouts))
                    .presentationDragIndicator(.visible)
            }
        }

        private var isSheetShown: Binding<Bool> {
            Binding(get: { model.showsTouchSheet }, set: { if !$0 { model.touchSheetSwipedAway() } })
        }
    }

    private struct BudgetSheetDetents: ViewModifier {
        let callouts: BudgetCalloutController
        @State private var detent: PresentationDetent

        init(callouts: BudgetCalloutController) {
            self.callouts = callouts
            _detent = State(initialValue: callouts.availableForm?.isOverspent == true ? .large : BudgetScreen.summary)
        }

        func body(content: Content) -> some View {
            if callouts.availableForm == nil {
                content.presentationDetents([.large])
            } else {
                content.presentationDetents([BudgetScreen.summary, .large], selection: $detent)
            }
        }
    }

#endif
