import AbakusCore
import Foundation

extension TransactionEditor {
    public func frequencyClicked() {
        let field = EditorFieldID.main(.frequency)
        if focus != .field(field) { setFocus(.field(field), commitCurrent: true) }
        isFrequencyListOpen.toggle()
    }

    public func frequencyChosen(_ value: ScheduledTransactionFrequency) {
        setFrequency(value)
        isFrequencyListOpen = false
    }

    public func frequencyListDismissed() {
        isFrequencyListOpen = false
    }

    func setFrequency(_ value: ScheduledTransactionFrequency?) {
        frequency = value
        texts[.main(.frequency)] = value?.readableName ?? ""
    }

    /// The arrows step through the list without opening it.
    func frequencyKey(_ key: EditorKey) -> Bool {
        let all = ScheduledTransactionFrequency.allCases
        switch key {
        case .up, .down:
            let index = frequency.flatMap { all.firstIndex(of: $0) } ?? 0
            setFrequency(all[min(all.count - 1, max(0, index + (key == .up ? -1 : 1)))])
        case .space:
            isFrequencyListOpen.toggle()
        case .enter where isFrequencyListOpen, .escape where isFrequencyListOpen:
            isFrequencyListOpen = false
        default:
            return false
        }
        return true
    }
}
