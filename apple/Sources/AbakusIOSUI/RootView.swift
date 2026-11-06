#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct RootView: View {
        let model: AppModel
        let navigation: TouchNavigation
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Group {
                if model.showsSignIn, let syncSettings = model.syncSettings {
                    SignInScreen(model: syncSettings)
                } else {
                    budgetScreens
                }
            }
            // A sheet shows the dialogs over itself.
            .modifier(DialogAlert(dialogs: navigation.showsSheet ? [] : model.presentedDialogs))
        }

        private var budgetScreens: some View {
            AppTabs(model: model, navigation: navigation)
                .sheet(item: sheet) { sheet in
                    TouchSheetView(model: model, sheet: sheet)
                }
                .modifier(TransactionSheetPresenter(model: model))
                .tint(ThemeColor.accent)
                .task { await model.runDateTimer() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        model.sync?.start()
                        model.sync?.syncNow()
                    case .background: model.enteredBackground()
                    default: break
                    }
                }
        }

        private var sheet: Binding<TouchSheet?> {
            Binding {
                TouchSheet(model, navigation: navigation)
            } set: { sheet in
                if sheet == nil { TouchSheet(model, navigation: navigation)?.cancel(in: model) }
            }
        }
    }

    /// The transaction sheet comes up over whichever screen asked for it, the budget's "+" too.
    private struct TransactionSheetPresenter: ViewModifier {
        let model: AppModel

        func body(content: Content) -> some View {
            let register = model.register
            content
                .sheet(isPresented: isEditorShown) {
                    if let editor = register.editor {
                        TransactionSheet(editor: editor, dialogs: model.presentedDialogs).id(ObjectIdentifier(editor))
                    }
                }
                .alert(RegisterIncomeCheck.title, isPresented: isIncomeCheckShown) {
                    Button(RegisterIncomeCheck.swapTitle) { register.incomeCheckAnswered(swap: true) }
                    Button(RegisterIncomeCheck.keepTitle, role: .cancel) { register.incomeCheckAnswered(swap: false) }
                } message: {
                    Text(TextMarkup.plain(RegisterIncomeCheck.message))
                }
        }

        private var isEditorShown: Binding<Bool> {
            let register = model.register
            return Binding {
                register.editor != nil
            } set: { shown in
                if !shown { register.editor?.cancel() }
            }
        }

        private var isIncomeCheckShown: Binding<Bool> {
            let register = model.register
            return Binding(get: { register.incomeCheck != nil && register.editor == nil }, set: { _ in })
        }
    }

    struct RegisterDetail: View {
        let model: AppModel

        var body: some View {
            RegisterScreen(register: model.register, dialogs: model.presentedDialogs)
                .id(model.register.accountKey)
        }
    }
#endif
