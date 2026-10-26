import AppKit

/// 工具注册表：按注册顺序返回工具与当前上下文下的可用性。
/// 内置工具通过 window 的既有入口执行，后续插件只需实现 FFTool 并注册。
final class FFToolRegistry {

    static let shared = FFToolRegistry()

    private var tools: [FFTool] = []
    private var ids = Set<String>()

    init() {}

    func register(_ tool: FFTool) {
        guard !ids.contains(tool.id) else {
            FFLog.error("FFToolRegistry: 重复工具 id \(tool.id)，保留首个注册项", log: FFLog.ui)
            return
        }
        ids.insert(tool.id)
        tools.append(tool)
    }

    var registeredTools: [FFTool] { tools }

    func availableTools(for context: FFToolContext) -> [(FFTool, FFToolAvailability)] {
        tools.map { ($0, $0.availability(in: context)) }
    }

    /// 幂等注册内置工具；多窗口初始化时重复调用不会产生重复项。
    static func registerBuiltInsIfNeeded() {
        guard shared.tools.isEmpty else { return }
        shared.register(DuplicateScanTool())
        shared.register(BatchRenameTool())
        shared.register(BatchOrganizeTool())
        shared.register(TaskCenterTool())
        shared.register(AITagTool())
        shared.register(AIOrganizeTool())
        shared.register(SettingsTool())
        shared.register(AboutTool())
    }
}

// MARK: - Built-in tools

private struct DuplicateScanTool: FFTool {
    let id = "duplicate-scan"
    let title = FFNaming.duplicateScanBase
    var icon: FFIconName { .scanSearch }
    let keywords = ["查重", "重复", "duplicate", "dedup"]
    let group = FFToolGroup.organize
    var contextHint: String? { "扫描当前文件夹" }

    func availability(in context: FFToolContext) -> FFToolAvailability {
        context.currentPath.isEmpty ? .needsFolder : .available
    }

    func run(in context: FFToolContext) {
        context.window?.menuDuplicateScan(nil)
    }
}

private struct BatchRenameTool: FFTool {
    let id = "batch-rename"
    let title = FFNaming.batchRenameBase
    var icon: FFIconName { .replace }
    let keywords = ["批量", "重命名", "rename", "batch"]
    let group = FFToolGroup.organize
    var contextHint: String? { "作用于当前选择" }

    func availability(in context: FFToolContext) -> FFToolAvailability {
        // R4-11：阈值是 2——只选 1 个时说「先选择文件」等于误导（已经选了）
        if context.selection.isEmpty { return .needsSelection }
        return context.selection.count >= 2 ? .available : .disabled(FFNaming.batchRenameRequires)
    }

    func run(in context: FFToolContext) {
        context.window?.menuBatchRename(nil)
    }
}

/// J3-10: 批量整理工具（工具页入口，作用于当前目录）
private struct BatchOrganizeTool: FFTool {
    let id = "batch-organize"
    let title = FFNaming.batchOrganizeBase
    var icon: FFIconName { .folderTree }
    let keywords = ["整理", "分类", "organize", "batch"]
    let group = FFToolGroup.organize
    var contextHint: String? { "作用于当前目录" }

    func availability(in context: FFToolContext) -> FFToolAvailability {
        context.currentPath.isEmpty ? .needsFolder : .available
    }

    func run(in context: FFToolContext) {
        context.window?.menuBatchOrganize(nil)
    }
}

private struct TaskCenterTool: FFTool {
    let id = "task-center"
    let title = FFNaming.taskCenterBase
    var icon: FFIconName { .listChecks }
    let keywords = ["任务", "进度", "task", "progress"]
    let group = FFToolGroup.task

    func availability(in context: FFToolContext) -> FFToolAvailability {
        context.hasTasks ? .available : .disabled("暂无任务")
    }

    func run(in context: FFToolContext) {
        TaskPanelWindowController.shared.showWindow()
    }
}

private struct AITagTool: FFTool {
    let id = "ai-tag"
    let title = "按类型自动打标签"
    var icon: FFIconName { .wandSparkles }
    let keywords = ["ai", "打标", "标签", "tag"]
    let group = FFToolGroup.system

    func availability(in context: FFToolContext) -> FFToolAvailability {
        .disabled("即将推出")
    }

    func run(in context: FFToolContext) {}
}

private struct AIOrganizeTool: FFTool {
    let id = "ai-organize"
    let title = "自动整理"
    var icon: FFIconName { .folderTree }
    let keywords = ["ai", "整理", "分类", "organize"]
    let group = FFToolGroup.system

    func availability(in context: FFToolContext) -> FFToolAvailability {
        .disabled("即将推出")
    }

    func run(in context: FFToolContext) {}
}

private struct SettingsTool: FFTool {
    let id = "settings"
    let title = "设置"
    var icon: FFIconName { .settings }
    let keywords = ["设置", "偏好", "settings", "preferences"]
    let group = FFToolGroup.system

    func availability(in context: FFToolContext) -> FFToolAvailability { .available }

    func run(in context: FFToolContext) {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}

private struct AboutTool: FFTool {
    let id = "about"
    let title = "关于 FlowFinder"
    var icon: FFIconName { .info }
    let keywords = ["关于", "版本", "about", "version"]
    let group = FFToolGroup.system

    func availability(in context: FFToolContext) -> FFToolAvailability { .available }

    func run(in context: FFToolContext) {
        NotificationCenter.default.post(name: .openSettings, object: nil,
                                        userInfo: ["section": "about"])
    }
}
