import AbakusCore
import SwiftUI

/// The cover list in grouped cards: Zu verteilen first, then the categories with money. A tap or click covers.
package struct BudgetCoverList: View {
    package static let readyToAssignSymbol = "tray.and.arrow.down"
    package static let fineRowHeight: CGFloat = 30
    package static let touchRowHeight: CGFloat = 44

    let controller: BudgetCalloutController
    let form: BudgetAvailableForm
    let rowHeight: CGFloat
    @ScaledMetric(relativeTo: .body) private var slotWidth: CGFloat = 24

    package init(controller: BudgetCalloutController, form: BudgetAvailableForm, rowHeight: CGFloat) {
        self.controller = controller
        self.form = form
        self.rowHeight = rowHeight
    }

    private var rowPadding: CGFloat { rowHeight < Self.touchRowHeight ? 10 : 16 }
    private var slotSpacing: CGFloat { 8 }
    private var textInset: CGFloat { rowPadding + (hasLeadingSlot ? slotWidth + slotSpacing : 0) }

    private var hasLeadingSlot: Bool {
        form.readyToAssign != nil || form.categories.contains { $0.name.leadingEmoji != nil }
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: rowHeight < Self.touchRowHeight ? 8 : 12) {
            Text(verbatim: controller.coverTitle)
                .fontWeight(.semibold)
                .foregroundStyle(ThemeColor.secondaryText)
                .padding(.leading, textInset)
                .accessibilityAddTraits(.isHeader)
            if form.sources.isEmpty {
                Text(verbatim: BudgetCalloutController.noSources)
                    .foregroundStyle(ThemeColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, textInset)
            }
            if let readyToAssign = form.readyToAssign {
                card {
                    row(readyToAssign, name: readyToAssign.name, amountStyle: ThemeColor.positive) {
                        Image(systemName: Self.readyToAssignSymbol).foregroundStyle(ThemeColor.positive)
                    }
                }
            }
            if !form.categories.isEmpty {
                card {
                    ForEach(Array(form.categories.enumerated()), id: \.element.categoryId) { index, source in
                        if index > 0 {
                            Rectangle().fill(ThemeColor.separator).frame(height: 0.5).padding(.leading, textInset)
                        }
                        let parts = source.name.leadingEmoji
                        row(source, name: parts?.name ?? source.name, amountStyle: ThemeColor.text) {
                            Text(verbatim: parts?.emoji ?? "")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(ThemeColor.groupedRowBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row<Leading: View>(
        _ source: BudgetFundsSource, name: String, amountStyle: Color, @ViewBuilder leading: () -> Leading
    ) -> some View {
        Button {
            controller.cover(from: source.categoryId)
        } label: {
            HStack(spacing: slotSpacing) {
                if hasLeadingSlot {
                    leading()
                        .frame(width: slotWidth)
                        .accessibilityHidden(true)
                }
                Text(verbatim: name)
                    .foregroundStyle(ThemeColor.text)
                    .lineLimit(1)
                Spacer(minLength: 16)
                Text(verbatim: controller.formatter.currency(source.available))
                    .monospacedDigit()
                    .foregroundStyle(amountStyle)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, rowPadding)
            .frame(minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(BudgetCoverRowStyle())
    }
}

private struct BudgetCoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background {
                    if configuration.isPressed || isHovered {
                        Rectangle().fill(ThemeColor.groupFill)
                    }
                }
                .onHover { isHovered = $0 }
        }
    }
}
