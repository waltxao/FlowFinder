import AppKit

/// 工具执行上下文：只读活动面板真值，不直接读视图。
final class FFToolContext {
    let activePane: PaneSide
    let currentPath: String
    let selection: [FileEntry]
    weak var window: MainWindowController?
    /// 是否有任务记录；任务中心圆只在此为 true 时可用/出现。
    var hasTasks: Bool

    init(activePane: PaneSide,
         currentPath: String,
         selection: [FileEntry],
         window: MainWindowController?,
         hasTasks: Bool = false) {
        self.activePane = activePane
        self.currentPath = currentPath
        self.selection = selection
        self.window = window
        self.hasTasks = hasTasks
    }

    var selectionSummary: String {
        if selection.isEmpty { return "未选择项目" }
        if selection.count == 1 { return selection[0].name }
        return "\(selection.count) 项已选"
    }
}

enum FFToolAvailability: Equatable {
    case available
    case needsSelection
    case needsFolder
    case disabled(String)

    var isAvailable: Bool { self == .available }

    var reason: String? {
        switch self {
        case .available: return nil
        case .needsSelection: return "先选择文件"
        case .needsFolder: return "先进入文件夹"
        case .disabled(let reason): return reason
        }
    }
}

enum FFToolGroup: Int, CaseIterable {
    case organize
    case task
    case system

    var title: String {
        switch self {
        case .organize: return "整理"
        case .task: return "任务"
        case .system: return "系统"
        }
    }
}

protocol FFTool {
    var id: String { get }
    var title: String { get }
    var icon: FFIconName { get }
    var keywords: [String] { get }
    var group: FFToolGroup { get }
    /// 可用状态下给用户的上下文提示（不写左/右面板）。
    var contextHint: String? { get }
    func availability(in context: FFToolContext) -> FFToolAvailability
    func run(in context: FFToolContext)
}

extension FFTool {
    var group: FFToolGroup { .organize }
    var contextHint: String? { nil }
}
