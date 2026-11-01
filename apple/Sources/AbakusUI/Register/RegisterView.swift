import AppKit
import SwiftUI

public struct RegisterView: View {
    let model: RegisterViewModel

    public init(model: RegisterViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            RegisterHeader(model: model)
            RegisterToolbar(model: model)
            GeometryReader { proxy in
                RegisterSplit(model: model, size: proxy.size)
            }
        }
        .background(ThemeColor.windowBackground)
        // The header holds the title and the toolbar's controls, so the window has no toolbar of its own.
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .overlayPreferenceValue(IncomeCheckAnchorKey.self) { anchor in
            if let check = model.incomeCheck, let anchor {
                IncomeCheckLayer(model: model, check: check, anchor: anchor)
            }
        }
        .overlayPreferenceValue(AdjustmentHelpAnchorKey.self) { anchor in
            if let help = model.adjustmentHelp, let anchor {
                AdjustmentHelpLayer(model: model, help: help, anchor: anchor)
            }
        }
        .overlayPreferenceValue(EditorAnchorKey.self) { anchors in
            if let editor = model.editor ?? model.scheduler.editor {
                EditorPopupsLayer(editor: editor, anchors: anchors)
            }
        }
        .overlayPreferenceValue(RegisterAnchorKey.self) { anchors in
            RegisterOverlayLayer(model: model, anchors: anchors)
        }
        // Edit › Select All reaches the register when no text field takes it first.
        .onCommand(#selector(NSResponder.selectAll(_:))) { _ = model.selectAllKeyPressed() }
    }
}

/// The scheduled section only exists while it is shown.
private struct RegisterSplit: View {
    let model: RegisterViewModel
    let size: CGSize

    var body: some View {
        let isVisible = model.isSchedulerVisible
        let schedulerHeight = SchedulerMetrics.height(saved: model.scheduler.savedHeight, available: size.height)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                RegisterPanelContent(model: model, size: proxy.size)
            }
            if isVisible {
                SchedulerDivider(currentHeight: schedulerHeight, available: size.height) {
                    model.scheduler.setHeight($0)
                }
                SchedulerSection(model: model, size: CGSize(width: size.width, height: schedulerHeight))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(SchedulerMetrics.animation, value: isVisible)
    }
}

private struct RegisterPanelContent: View {
    let model: RegisterViewModel
    let size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            // Shown at once: animating its height while the search field edits sends the grid into a layout loop.
            if let info = model.search.info {
                RegisterSearchInfoBar(info: info, onClear: model.search.clearClicked)
            }
            Divider()
            GeometryReader { proxy in
                RegisterGridView(owner: model, size: proxy.size)
                    .id(model.accountKey)
            }
            if model.isReconciling {
                ReconciliationFooterView(reconciliation: model.reconciliation)
            } else {
                RegisterStatusBar(model: model)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// A neutral inline banner: the search or reconciliation message and its clear button.
private struct RegisterSearchInfoBar: View {
    let info: RegisterSearchInfo
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ThemeColor.secondaryText)
                .accessibilityHidden(true)
            Text(verbatim: info.message)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(info.message)
            Spacer(minLength: 8)
            if let title = info.clearButtonTitle {
                Button(title, action: onClear)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .font(ThemeFont.caption.font)
        .padding(.horizontal, 10)
        .frame(height: RegisterMetrics.searchInfoBarHeight - 4)
        .background(ThemeColor.groupFill, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding - 6)
        .padding(.bottom, 4)
    }
}
