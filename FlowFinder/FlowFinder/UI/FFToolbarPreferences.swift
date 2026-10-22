import Foundation

enum FFToolbarRow2Item: String, CaseIterable, Hashable {
    case search
    case sort
    case group
    case viewMode
}

extension Notification.Name {
    static let toolbarRow2PreferencesChanged =
        Notification.Name("FFToolbarRow2PreferencesChanged")
}

enum FFToolbarRow2Preferences {
    static let storageKey = "toolbar_row2_items"
    static let defaultItems = Set(FFToolbarRow2Item.allCases)

    static func visibleItems(from raw: String?) -> Set<FFToolbarRow2Item> {
        guard let raw else { return defaultItems }
        return Set(raw.split(separator: ",").compactMap {
            FFToolbarRow2Item(rawValue: String($0))
        })
    }

    static func encode(_ items: Set<FFToolbarRow2Item>) -> String {
        items.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func toggled(_ item: FFToolbarRow2Item,
                        in items: Set<FFToolbarRow2Item>) -> Set<FFToolbarRow2Item> {
        items.contains(item) ? items.subtracting([item]) : items.union([item])
    }
}
