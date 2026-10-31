import AbakusCore
import SwiftUI

struct EditButtonRow: View {
    let editor: TransactionEditor
    let width: CGFloat
    @State private var glow: Double = 0

    /// Cancel leads as on the Mac; the others keep the editor's order, which Tab still follows.
    static func displayOrder(_ buttons: [EditorButton]) -> [EditorButton] {
        buttons.filter { $0 == .cancel } + buttons.filter { $0 != .cancel }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.displayOrder(editor.buttons), id: \.self) { button in
                EditCommandButton(
                    button: button, isProminent: editor.prominentButton == button,
                    isFocused: editor.showsButtonFocus && editor.focus == .button(button)
                ) {
                    editor.activate(button)
                }
            }
        }
        .glow(ThemeColor.accent, intensity: glow)
        .padding(.trailing, 10)
        .frame(width: width, height: EditRowMetrics.buttonRowHeight, alignment: .trailing)
        .onChange(of: editor.glowCount) {
            withAnimation(.motion(RegisterEffects.glowPhase)) {
                glow = 1
            } completion: {
                withAnimation(.motion(RegisterEffects.glowPhase)) { glow = 0 }
            }
        }
    }
}

/// Never takes the keyboard: the editor moves the focus itself and draws the ring.
struct EditCommandButton: View {
    let button: EditorButton
    let isProminent: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        styled
            .focusable(false)
            .focusRing(isFocused, cornerRadius: 12)
    }

    @ViewBuilder
    private var styled: some View {
        let base = Button(role: button == .delete ? .destructive : nil, action: action) { label }
        if isProminent {
            base.buttonStyle(.borderedProminent)
        } else {
            base.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage = button.systemImage {
            Label(button.title, systemImage: systemImage)
        } else {
            Text(button.title)
        }
    }
}
