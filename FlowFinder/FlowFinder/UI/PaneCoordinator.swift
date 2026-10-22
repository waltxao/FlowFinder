import Foundation

/// 面板状态协调器：持有两块面板的单一真值与活动面板焦点。
final class PaneCoordinator {

    let focus: WindowFocusModel
    let leftStore: PaneStore
    let rightStore: PaneStore

    init(leftState: PaneState,
         rightState: PaneState,
         focus: WindowFocusModel = WindowFocusModel()) {
        self.focus = focus
        self.leftStore = PaneStore(initial: leftState)
        self.rightStore = PaneStore(initial: rightState)
    }

    var activePane: PaneSide {
        get { focus.activePane }
        set { focus.activate(newValue) }
    }

    func store(for side: PaneSide) -> PaneStore {
        side == .left ? leftStore : rightStore
    }
}
