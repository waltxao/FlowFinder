import AppKit

/// 侧栏协调器：持有侧栏视图并注入工具上下文来源。
final class SidebarCoordinator {

    let view: SidebarView

    init(view: SidebarView = SidebarView()) {
        self.view = view
    }

    func bindToolContext(_ provider: @escaping () -> FFToolContext?) {
        view.toolContextProvider = provider
    }
}
