import AbakusCore
import SwiftUI

struct SidebarRowAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The non-modal "Konto bearbeiten" popover at its sidebar row; a click outside is Cancel.
struct AccountEditLayer: View {
    let controller: AccountsController
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        if let form = controller.editForm {
            GeometryReader { proxy in
                let anchor = anchors[form.accountId].map { proxy[$0] } ?? SidebarView.fallbackAnchor(in: proxy)
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: controller.editCancelled)
                    AnchoredPopover(side: .below, anchor: anchor, container: proxy.size) {
                        AccountEditPopover(controller: controller, form: form)
                    }
                }
            }
        }
    }
}

struct AccountEditPopover: View {
    static let fieldWidth: CGFloat = 260

    let controller: AccountsController
    @Bindable var form: EditAccountForm
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(EditAccountForm.title).font(ThemeFont.headline.font)
            fields
            Divider()
            footer
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .onAppear { nameFocused = true }
        .onKeyPress(.escape) {
            controller.editCancelled()
            return .handled
        }
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
            GridRow {
                label("Name")
                TextField("Name", text: $form.name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(controller.editDoneClicked)
                    .frame(width: Self.fieldWidth, alignment: .leading)
            }
            GridRow {
                label("Art")
                typeField.frame(width: Self.fieldWidth, alignment: .leading)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Button("Saldo anpassen …", action: controller.adjustBalanceClicked).fixedSize()
            }
        }
    }

    @ViewBuilder private var typeField: some View {
        if form.typeChoices.count > 1 {
            Picker("Art", selection: $form.type) {
                ForEach(form.typeChoices, id: \.self) { type in
                    Text(verbatim: type.label).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } else {
            Text(verbatim: form.type.label)
        }
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text).gridColumnAlignment(.trailing)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(
                controller.isClosed(form) ? "Wieder öffnen" : "Konto schließen",
                action: controller.closeOrReopenClicked)
            Spacer(minLength: 0)
            Button("Abbrechen", action: controller.editCancelled)
            Button("Fertig", action: controller.editDoneClicked).buttonStyle(.borderedProminent)
        }
    }
}
