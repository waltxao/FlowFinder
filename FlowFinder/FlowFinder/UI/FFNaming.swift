import Foundation

/// R4-06（docs/AUDIT-2026-10-23-UIUX-R4.md）：同一功能在侧栏、菜单栏、右键菜单
/// 与窗口标题里的唯一叫法。
///
/// 侧栏/工具页的标题取自 `FFToolRegistry`，其余入口必须引用这里的常量——
/// 之前「任务中心 / 任务面板」「重复文件扫描 / 查重扫描」「移动到废纸篓 / 移到废纸篓」
/// 各叫一套，用户在同一功能的不同入口间认不出它。
enum FFNaming {
    static let taskCenterBase = "任务中心"
    static let duplicateScanBase = "重复文件扫描"
    static let batchRenameBase = "批量重命名"
    static let batchOrganizeBase = "批量整理"
    static let moveToTrashBase = "移动到废纸篓"
    static let connectServerBase = "连接服务器"
    static let editTagsBase = "编辑标签"
    /// ⇧⌘N 新建文件夹的默认名（重名时由 PaneViewModel.untitledFolderName 追加序号）
    static let untitledFolderBase = "未命名文件夹"
    static let detailsBarTitle = "显示/隐藏详情栏"

    /// 需要后续输入的菜单项统一以排版省略号结尾（R4-09：不再混用 ASCII `...`）。
    static let duplicateScanTitle = duplicateScanBase + "…"
    static let batchRenameTitle = batchRenameBase + "…"
    static let connectServerTitle = connectServerBase + "…"
    static let editTagsTitle = editTagsBase + "…"

    /// R4-11：禁用态必须说清阈值，否则用户只看到一个灰掉的入口。
    static let batchRenameRequires = "需要至少选择 2 个文件"

    /// R4-14：网络存储页的添加按钮（此前是「+ 添加服务器...」通栏灰底，
    /// 看起来像一行被禁用的列表项）。
    static let addServerBase = "添加服务器"
    static let addServerTitle = addServerBase + "…"

    /// R4-13：永久删除没有开关（产品上不允许关掉），所以它不该排成设置行，
    /// 只作为分区脚注存在。原句「跳过废纸篓的永久删除始终二次确认」缺谓语中心词。
    static let permanentDeleteNotice = "跳过废纸篓的永久删除需二次确认，且无法撤销。"
}

/// R4-26：设置页分区前导图标。集中一处，避免与分区内选项图标撞形——
/// 「主题」分区原先和「深色」选项都用月亮，同屏两个同形异义的图标。
enum FFSettingsIcons {
    static let themeSection: FFIconName = .wandSparkles
}
