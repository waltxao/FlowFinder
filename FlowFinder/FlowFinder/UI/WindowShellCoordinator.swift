import AppKit

/// 窗口外壳协调器：聚合面板、侧栏、工具、任务四个接缝。
/// MainWindowController 仍负责窗口生命周期与布局，但状态所有权从这里分发。
final class WindowShellCoordinator {

    weak var window: NSWindow?
    let panes: PaneCoordinator
    let sidebar: SidebarCoordinator
    let tools: ToolCoordinator
    let tasks: TaskCoordinator

    init(window: NSWindow?,
         panes: PaneCoordinator,
         sidebar: SidebarCoordinator,
         tools: ToolCoordinator,
         tasks: TaskCoordinator) {
        self.window = window
        self.panes = panes
        self.sidebar = sidebar
        self.tools = tools
        self.tasks = tasks
    }
}
