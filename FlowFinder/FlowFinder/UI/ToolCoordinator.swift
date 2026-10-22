import AppKit

/// 工具协调器：唯一持有工具注册表并把窗口状态转成工具上下文。
final class ToolCoordinator {

    let registry: FFToolRegistry

    init(registry: FFToolRegistry = .shared) {
        self.registry = registry
        FFToolRegistry.registerBuiltInsIfNeeded()
    }

    func context(activePane: PaneSide,
                 currentPath: String,
                 selection: [FileEntry],
                 window: MainWindowController?) -> FFToolContext {
        FFToolContext(activePane: activePane,
                      currentPath: currentPath,
                      selection: selection,
                      window: window)
    }

    func tools(for context: FFToolContext) -> [(FFTool, FFToolAvailability)] {
        registry.availableTools(for: context)
    }
}
