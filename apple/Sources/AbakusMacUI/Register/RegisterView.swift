import AbakusUI
import AppKit
import SwiftUI

public struct RegisterView: View {
    let model: RegisterViewModel

    public init(model: RegisterViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            RegisterToolbar(model: model)
            GeometryReader { proxy in
                RegisterSplit(model: model, size: proxy.size)
            }
        }
        .background(ThemeColor.windowBackground)
        .navigationTitle(model.accountName)
        .navigationSubtitle(model.reconciledLabel ?? "")
        .toolbar { RegisterHeader(model: model) }
        .overlayPreferenceValue(IncomeCheckAnchorKey.self) { anchor in
            if let check = model.incomeCheck, let anchor {
                IncomeCheckLayer(model: model, check: check, anchor: anchor)
            }
        }
        .overlayPreferenceValue(EditorAnchorKey.self) { anchors in
            if let editor = model.editor {
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

/// The scheduled section only exists while it is shown or something is planned.
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
            } else if model.scheduledSummary != nil {
                Divider()
                SchedulerTitleBar(model: model)
                    .frame(height: SchedulerMetrics.titleHeight)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(SchedulerMetrics.animation, value: isVisible)
    }
}

struct RegisterPanelContent: View {
    enum InfoBar: Hashable {
        case approvals(String)
        case search(RegisterSearchInfo)
    }

    let model: RegisterViewModel
    let size: CGSize

    /// What waits for approval, then the search's hits or the reconciliation.
    static func infoBars(of model: RegisterViewModel) -> [InfoBar] {
        [model.approvalsLine.map(InfoBar.approvals), model.search.info.map(InfoBar.search)].compactMap(\.self)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Shown at once: animating its height while the search field edits sends the grid into a layout loop.
            if let banner = model.banner {
                RegisterInfoBar(
                    message: banner.message, buttonTitle: banner == .closed ? RegisterBanner.reopenTitle : nil,
                    action: model.reopenClicked)
            }
            ForEach(Self.infoBars(of: model), id: \.self) { bar in
                switch bar {
                case .approvals(let line):
                    RegisterInfoBar(
                        message: line, buttonTitle: RegisterViewModel.approveAllTitle, action: model.approveAllClicked)
                case .search(let info):
                    RegisterInfoBar(
                        message: info.message, buttonTitle: info.clearButtonTitle, action: model.search.clearClicked)
                }
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

/// A neutral inline banner: what waits for approval, the search or the reconciliation, and its button.
private struct RegisterInfoBar: View {
    let message: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ThemeColor.secondaryText)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(message)
            Spacer(minLength: 8)
            if let buttonTitle {
                Button(buttonTitle, action: action)
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
