import Cocoa
import QuickLook
import Quartz

/// QuickLook 预览面板：使用原生 QLPreviewPanel 单例
/// 实现 QLPreviewPanelController（informal protocol）、DataSource、Delegate
///
/// QLPreviewPanel 通过 responder chain 自动查找 controller：
/// 1. 将 self 插入 responder chain
/// 2. 调用 panel.updateController() 让面板发现 controller
/// 3. 面板调用 acceptsPreviewPanelControl → beginPreviewPanelControl
public class QuickLookPreviewPanel: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    public static let shared = QuickLookPreviewPanel()

    /// 当前预览的文件路径数组
    private var previewFiles: [String] = []

    /// 当前预览的索引
    private var currentIndex: Int = 0

    /// 记录插入 responder chain 前的 nextResponder，用于退出时恢复
    private var savedNextResponder: NSResponder?

    /// v0.6.9 fix: 记录打开预览时的目标 window，避免关闭时 keyWindow 已切换导致 responder chain 残留
    private weak var targetWindow: NSWindow?

    /// QLPreviewPanel 单例引用
    private var previewPanel: QLPreviewPanel? {
        QLPreviewPanel.shared()
    }

    private override init() {
        super.init()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// 切换 QuickLook 预览显示/隐藏
    /// - Parameters:
    ///   - files: 可预览的文件路径数组
    ///   - currentIndex: 当前选中的文件索引
    ///   - targetWindow: 目标窗口（用于插入 responder chain，nil 时回退到 keyWindow）
    public func togglePreview(files: [String], currentIndex: Int, targetWindow: NSWindow? = nil) {
        self.previewFiles = files
        self.currentIndex = max(0, min(currentIndex, max(0, files.count - 1)))

        guard let panel = previewPanel else { return }

        if panel.isVisible {
            // v0.6.9 fix: 面板已可见时更新文件列表和索引，而非关闭
            panel.currentPreviewItemIndex = self.currentIndex
            panel.reloadData()
        } else {
            // 将 self 插入 responder chain，使 QLPreviewPanel 能找到 controller
            insertIntoResponderChain(targetWindow: targetWindow)

            // 强制面板重新搜索 responder chain，找到 self 作为 controller
            panel.updateController()

            // 设置数据源和代理（beginPreviewPanelControl 中也会设置并设置 currentPreviewItemIndex）
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// 关闭 QuickLook 预览
    public func close() {
        if let panel = previewPanel {
            panel.orderOut(nil)
            panel.dataSource = nil
            panel.delegate = nil
        }
        removeFromResponderChain()
    }

    /// 更新预览文件列表（不改变显示状态）
    /// - Parameters:
    ///   - files: 新的文件路径数组
    ///   - currentIndex: 当前索引
    public func updateFiles(_ files: [String], currentIndex: Int) {
        self.previewFiles = files
        self.currentIndex = max(0, min(currentIndex, max(0, files.count - 1)))
        previewPanel?.reloadData()
    }

    // MARK: - Responder Chain 管理

    /// 将 self 插入指定 window 的 responder chain
    /// - Parameter targetWindow: 目标窗口，nil 时回退到 NSApp.keyWindow
    private func insertIntoResponderChain(targetWindow: NSWindow?) {
        guard let window = targetWindow ?? NSApp.keyWindow, let firstResponder = window.firstResponder else { return }
        // 避免重复插入
        if firstResponder.nextResponder === self { return }
        // v0.6.9 fix: 记录目标 window，关闭时使用而非依赖 keyWindow（可能已切换）
        self.targetWindow = window
        // 保存当前 nextResponder，稍后恢复
        savedNextResponder = firstResponder.nextResponder
        // 插入 self：firstResponder → self → 原 nextResponder
        self.nextResponder = firstResponder.nextResponder
        firstResponder.nextResponder = self
    }

    /// 从 responder chain 中移除 self
    private func removeFromResponderChain() {
        // v0.6.9 fix: 使用记录的 targetWindow 而非 NSApp.keyWindow（可能已切换）
        guard let window = targetWindow else { return }
        // 遍历 responder chain，找到指向 self 的 responder
        var responder: NSResponder? = window.firstResponder
        while let r = responder {
            if r.nextResponder === self {
                // 跳过 self，恢复原链
                r.nextResponder = savedNextResponder ?? self.nextResponder
                self.nextResponder = nil
                savedNextResponder = nil
                targetWindow = nil
                break
            }
            responder = r.nextResponder
        }
    }

    // MARK: - QLPreviewPanelController (Informal Protocol via NSObject category)

    /// 告知 QuickLook 面板：self 愿意成为 controller
    public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    /// 开始控制 QuickLook 面板时调用：设置数据源、代理和当前预览索引
    public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        // v0.6.9 fix: 在面板就绪后设置当前预览索引（此前在 togglePreview 中过早设置导致索引不生效）
        panel.currentPreviewItemIndex = self.currentIndex
    }

    /// 结束控制 QuickLook 面板时调用：清理数据源和代理
    public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - QLPreviewPanelDataSource

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewFiles.count
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < previewFiles.count else { return nil }
        let url = URL(fileURLWithPath: previewFiles[index])
        return url as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // 处理方向键切换
        if event.type == .keyDown {
            switch event.keyCode {
            case 123:  // 左箭头
                if currentIndex > 0 {
                    currentIndex -= 1
                    panel.currentPreviewItemIndex = currentIndex
                }
                return true
            case 124:  // 右箭头
                if currentIndex < previewFiles.count - 1 {
                    currentIndex += 1
                    panel.currentPreviewItemIndex = currentIndex
                }
                return true
            case 126:  // 上箭头
                if currentIndex > 0 {
                    currentIndex -= 1
                    panel.currentPreviewItemIndex = currentIndex
                }
                return true
            case 125:  // 下箭头
                if currentIndex < previewFiles.count - 1 {
                    currentIndex += 1
                    panel.currentPreviewItemIndex = currentIndex
                }
                return true
            case 53:  // Escape
                close()
                return true
            default:
                break
            }
        }
        return false
    }

    public func previewPanel(_ panel: QLPreviewPanel!, modifierStateChangedTo modifierFlags: NSEvent.ModifierFlags) {
        // 可用于实现 Cmd+方向键等快捷操作
    }
}
