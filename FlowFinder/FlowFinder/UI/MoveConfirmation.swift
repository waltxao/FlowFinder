import AppKit

/// 批次 1 B1-05：移动前确认。
/// 删除确认走既有 DeleteConfirmDialog；这里只负责「移动到另一目录」。
enum MoveConfirmation {

    static func shouldAsk(enabled: Bool, isMove: Bool) -> Bool {
        enabled && isMove
    }

    static func message(count: Int, destinationName: String) -> String {
        "将 \(count) 个项目移动到「\(destinationName)」？可用 ⌘Z 撤销。"
    }

    /// 返回 true 表示继续移动；false 表示用户取消。
    @discardableResult
    static func confirmSynchronously(count: Int, destination: String, window: NSWindow?) -> Bool {
        guard count > 0 else { return true }
        let name = (destination as NSString).lastPathComponent
        let alert = NSAlert()
        alert.messageText = "确认移动"
        alert.informativeText = message(count: count, destinationName: name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移动")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
