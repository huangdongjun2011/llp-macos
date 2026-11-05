public enum ListeningTextShortcutAction: Equatable {
    case selectAll
    case copy
    case paste
    case suppressSystemTextCommand
    case passThrough
}

public struct ListeningTextShortcutResolver {
    public init() {}

    public func action(
        for key: String?,
        hasOption: Bool,
        hasCommand: Bool,
        hasControl: Bool,
        hasShift: Bool
    ) -> ListeningTextShortcutAction {
        guard let shortcutAction = shortcutAction(for: key) else {
            return .passThrough
        }

        if hasCommand && !hasOption && !hasControl && !hasShift {
            return shortcutAction
        }

        return .passThrough
    }

    private func shortcutAction(for key: String?) -> ListeningTextShortcutAction? {
        switch key?.lowercased() {
        case "a":
            .selectAll
        case "c":
            .copy
        case "v":
            .paste
        default:
            nil
        }
    }
}
