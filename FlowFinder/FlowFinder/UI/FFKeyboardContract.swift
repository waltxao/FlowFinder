import AppKit

enum FFShortcutAction: String, CaseIterable, Hashable {
    case newWindow, newFolder, newTab, closeTab, closeWindow
    case moveToTrash, rename, quickLook, duplicate, getInfo
    case back, forward, up, focusLeft, focusRight
    case nextTab, previousTab, search, globalSearch, duplicateScan
    case copyToOther, moveToOther, settings
}

struct FFShortcut: Equatable {
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let display: String
}

enum FFKeyboardContract {
    static func shortcut(for action: FFShortcutAction) -> FFShortcut {
        switch action {
        case .newWindow:
            return .init(key: "n", modifiers: [.command], display: "⌘N")
        case .newFolder:
            return .init(key: "n", modifiers: [.command, .shift], display: "⌘⇧N")
        case .newTab:
            return .init(key: "t", modifiers: [.command], display: "⌘T")
        case .closeTab:
            return .init(key: "w", modifiers: [.command], display: "⌘W")
        case .closeWindow:
            return .init(key: "w", modifiers: [.command, .shift], display: "⌘⇧W")
        case .moveToTrash:
            return .init(key: String(UnicodeScalar(0x08)!), modifiers: [.command], display: "⌘⌫")
        case .rename:
            return .init(key: String(UnicodeScalar(0x0D)!), modifiers: [], display: "Return")
        case .quickLook:
            return .init(key: " ", modifiers: [], display: "Space")
        case .duplicate:
            return .init(key: "d", modifiers: [.command], display: "⌘D")
        case .getInfo:
            return .init(key: "i", modifiers: [.command], display: "⌘I")
        case .back:
            return .init(key: "[", modifiers: [.command], display: "⌘[")
        case .forward:
            return .init(key: "]", modifiers: [.command], display: "⌘]")
        case .up:
            return .init(key: String(UnicodeScalar(0xF700)!), modifiers: [.command], display: "⌘↑")
        case .focusLeft:
            return .init(key: "1", modifiers: [.command], display: "⌘1")
        case .focusRight:
            return .init(key: "2", modifiers: [.command], display: "⌘2")
        case .nextTab:
            return .init(key: String(UnicodeScalar(0x09)!), modifiers: [.control], display: "⌃Tab")
        case .previousTab:
            return .init(key: String(UnicodeScalar(0x09)!), modifiers: [.control, .shift], display: "⌃⇧Tab")
        case .search:
            return .init(key: "f", modifiers: [.command], display: "⌘F")
        case .globalSearch:
            return .init(key: "f", modifiers: [.command, .shift], display: "⌘⇧F")
        case .duplicateScan:
            return .init(key: "d", modifiers: [.command, .shift], display: "⌘⇧D")
        case .copyToOther:
            return .init(key: "c", modifiers: [.command, .shift], display: "⌘⇧C")
        case .moveToOther:
            return .init(key: "x", modifiers: [.command, .shift], display: "⌘⇧X")
        case .settings:
            return .init(key: ",", modifiers: [.command], display: "⌘,")
        }
    }

    static func conflicts(overrides: [FFShortcutAction: FFShortcut] = [:]) -> [FFShortcutAction: [FFShortcutAction]] {
        var effective: [FFShortcutAction: FFShortcut] = [:]
        for action in FFShortcutAction.allCases {
            effective[action] = overrides[action] ?? shortcut(for: action)
        }
        var result: [FFShortcutAction: [FFShortcutAction]] = [:]
        for (a, sa) in effective {
            for (b, sb) in effective where a != b {
                if sa.key == sb.key && sa.modifiers == sb.modifiers {
                    result[a, default: []].append(b)
                }
            }
        }
        return result
    }
}
