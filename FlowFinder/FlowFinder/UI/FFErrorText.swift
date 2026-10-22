import Foundation

/// 把底层错误文本翻成用户能懂的中文，并给出下一步。
///
/// 存在的理由：`PaneState.error` 与各处弹窗此前直接展示 `error.localizedDescription`，
/// 用户看到的是 `Permission denied (os error 13)`、`Read-only file system`、
/// `path is null` 这类英文串。产品定义 §2 明确「所有界面文案以非技术用户能读懂为准」，
/// 核心旅程 J5 要求「无权限 / 只读 / 断线，给中文说明与下一步」。
///
/// 设计约束：纯函数、不碰 UI，便于单测；识别不到时保留原始串（放在 detail 里，
/// 方便用户截图反馈），但主标题一律用中文兜底，绝不把英文当标题。
enum FFErrorText {

    struct Message: Equatable {
        /// 主标题（中文）
        let title: String
        /// 说明 + 下一步
        let detail: String
        /// 是否属于权限问题（决定是否显示「打开系统设置」）
        let isPermission: Bool
    }

    /// 判定所需的关键词表。小写匹配。
    private struct Rule {
        let needles: [String]
        let title: String
        let detail: String
        let isPermission: Bool
    }

    private static let rules: [Rule] = [
        Rule(
            needles: ["permission denied", "operation not permitted", "not authorized", "不允许", "没有权限", "权限不足"],
            title: "没有访问权限",
            detail: "这个位置需要你在「系统设置 › 隐私与安全性 › 文件和文件夹」里允许 FlowFinder 访问。点下面的按钮可以直接打开该设置页。",
            isPermission: true
        ),
        Rule(
            needles: ["no such file or directory", "file not found", "does not exist"],
            title: "找不到该项目",
            detail: "它可能已被移动、重命名或删除。刷新一下当前文件夹再试。",
            isPermission: false
        ),
        Rule(
            needles: ["read-only file system", "read only"],
            title: "这个磁盘是只读的",
            detail: "只读磁盘不能写入。请换到其他位置，或先在「磁盘工具」里改动这个磁盘的只读设置。",
            isPermission: false
        ),
        Rule(
            needles: ["no space left on device", "disk full"],
            title: "磁盘空间不足",
            detail: "目标磁盘已经放不下这些文件。清理一些空间，或换成另一个磁盘。",
            isPermission: false
        ),
        Rule(
            needles: ["directory not empty"],
            title: "文件夹不是空的",
            detail: "目标位置已有同名文件夹且里面有内容，无法直接覆盖。请改用「替换」或换一个名字。",
            isPermission: false
        ),
        Rule(
            needles: ["file name too long"],
            title: "文件名太长",
            detail: "macOS 单个文件名上限为 255 字节。把名字改短一些再试。",
            isPermission: false
        ),
        Rule(
            needles: ["not valid utf-8", "path is null", "src or dst is null", "invalid path"],
            title: "路径无效",
            detail: "这个路径含有无法识别的字符，或已不完整。重新选择一次文件再操作。",
            isPermission: false
        ),
        Rule(
            needles: ["rust core library not loaded", "core library not loaded"],
            title: "核心组件未加载",
            detail: "FlowFinder 的底层组件没有加载成功。请重新安装应用。",
            isPermission: false
        ),
        Rule(
            needles: ["no route to host", "network is down", "connection timed out", "host is down"],
            title: "连不上这台服务器",
            detail: "检查网络是否正常、服务器是否在线，然后重试。",
            isPermission: false
        )
    ]

    /// errno → 规则下标。
    /// 必须精确匹配 errno：`"os error 28"` 里含子串 `"os error 2"`，
    /// 用 contains 判断会让「磁盘满」被误判成「找不到文件」（单测实证）。
    private static let errnoToRule: [Int: Int] = [
        1: 0, 13: 0,   // EPERM / EACCES
        2: 1,         // ENOENT
        30: 2,        // EROFS
        28: 3,        // ENOSPC
        66: 4,        // ENOTEMPTY
        63: 5         // ENAMETOOLONG
    ]

    /// 从 `... (os error 13)` 里取出 errno
    private static func errno(from text: String) -> Int? {
        guard let range = text.range(of: "os error ") else { return nil }
        let digits = text[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// 是否含中日韩字符（用来判断「已经是中文，不必翻译」）
    private static func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    static func humanize(_ raw: String) -> Message {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return Message(title: "操作没有成功", detail: "请重试。", isPermission: false)
        }
        let lower = text.lowercased()
        if let code = errno(from: lower), let idx = errnoToRule[code] {
            let rule = rules[idx]
            return Message(title: rule.title, detail: rule.detail, isPermission: rule.isPermission)
        }
        for rule in rules where rule.needles.contains(where: { lower.contains($0) }) {
            return Message(title: rule.title, detail: rule.detail, isPermission: rule.isPermission)
        }
        // 已是中文：原样作为标题，不再加工
        if containsCJK(text) {
            return Message(title: text, detail: "", isPermission: false)
        }
        // 兜底：中文标题 + 原始串（供排查/截图反馈）
        return Message(
            title: "操作没有成功",
            detail: "请重试。如果一直失败，请把下面这行信息发给开发者：\n\(text)",
            isPermission: false
        )
    }
}
