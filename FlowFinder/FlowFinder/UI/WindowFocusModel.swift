import Combine

/// 窗口内唯一的活动面板真值。点击/Tab/⌘1/⌘2/侧栏/菜单都写这里。
final class WindowFocusModel {
    @Published private(set) var activePane: PaneSide = .left

    func activate(_ side: PaneSide) {
        guard side != activePane else { return }
        activePane = side
    }

    func toggle() {
        activePane = activePane == .left ? .right : .left
    }
}
