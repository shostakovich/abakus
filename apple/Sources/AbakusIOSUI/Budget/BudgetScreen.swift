#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct BudgetScreen: View {
        static let summary = PresentationDetent.fraction(0.72)

        let model: BudgetViewModel
        let dialogs: [PresentedDialog]
        @Environment(\.horizontalSizeClass) private var sizeClass
        @Environment(\.dock) private var dock
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
            .onChange(of: layout, initial: true) { model.touchLayout = layout }
            .onChange(of: model.isHeaderExpanded, initial: true) { _, expanded in
                withAnimation(.motion(BudgetStyle.headerResize)) { model.headerProgress = expanded ? 1 : 0 }
            }
            .navigationTitle(model.shownMonthsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { BudgetTitleMenu(model: model) }
                if layout == .phone, let month = model.shownMonths.first {
                    ToolbarItem(placement: .topBarTrailing) { BudgetMonthMenu(model: model, month: month) }
                }
            }
            .sheet(isPresented: isSheetShown) {
                BudgetSheet(model: model)
                    .modifier(DialogAlert(dialogs: dialogs))
                    .modifier(BudgetSheetDetents(callouts: model.callouts))
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: isCoverSheetShown) {
                BudgetCoverSheet(model: model)
            }
            .overlay(alignment: .bottom) {
                // An open sheet or popover shows the notice itself, where one tap reaches it.
                if !model.showsTouchCallout, let notice = model.undoNotice {
                    BudgetUndoBanner(model: model, notice: notice)
                        .padding(.bottom, dock?.clearance ?? 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: model.undoNotice?.id)
            .sensoryFeedback(.success, trigger: model.undoNotice?.id) { _, new in new != nil }
            .task(id: model.undoNotice?.id) {
                if let notice = model.undoNotice { await model.undoNoticeShown(notice) }
            }
        }

        private var isSheetShown: Binding<Bool> {
            Binding(get: { model.showsTouchSheet }, set: { if !$0 { model.touchSheetSwipedAway() } })
        }

        private var isCoverSheetShown: Binding<Bool> {
            Binding(get: { model.showsCoverSheet }, set: { if !$0 { model.coverDismissed() } })
        }
    }

    /// The phone's cover list on its own, at half height.
    private struct BudgetCoverSheet: View {
        let model: BudgetViewModel

        var body: some View {
            ScrollView {
                if let form = model.callouts.availableForm {
                    BudgetCoverList(controller: model.callouts, form: form, rowHeight: BudgetCoverList.touchRowHeight)
                        .padding(16)
                }
            }
            .background(ThemeColor.groupedBackground)
            .presentationBackground(ThemeColor.groupedBackground)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// What covering, filling or Zuweisen moved, with its way back.
    struct BudgetUndoBanner: View {
        let model: BudgetViewModel
        let notice: BudgetUndoNotice

        var body: some View {
            HStack(spacing: 12) {
                Text(verbatim: notice.message)
                    .font(.subheadline)
                    .foregroundStyle(ThemeColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(BudgetUndoNotice.undoTitle, action: model.undoNoticeClicked)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 4)
            // Glass alone lets the table's figures show through the sentence.
            .background(ThemeColor.contentBackground.opacity(0.94), in: .rect(cornerRadius: 24))
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .frame(maxWidth: 440)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
        }
    }

    private struct BudgetSheetDetents: ViewModifier {
        let callouts: BudgetCalloutController
        @State private var detent: PresentationDetent

        init(callouts: BudgetCalloutController) {
            self.callouts = callouts
            _detent = State(initialValue: BudgetScreen.summary)
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
