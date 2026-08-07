import AppKit

// MARK: - FFPaneViewHost 协议

/// 文件面板视图协议：列表视图、网格视图及未来新增视图均实现此协议，
/// 将视图特有的信息（选中项、右键点击项、重命名文本框等）提供给 FFPaneActionsController。
/// 控制器通过此协议访问视图上下文，所有操作逻辑（删除、重命名、复制粘贴、键盘处理等）
/// 由控制器统一实现，视图只需实现协议方法即可获得完整的操作能力，新增视图零重复、零重测。
protocol FFPaneViewHost: AnyObject {

    /// 当前面板的 ViewModel（提供文件列表、选中状态、路径等）
    var viewModel: PaneViewModel? { get }

    /// 宿主窗口（用于弹窗、sheet 等）
    var hostWindow: NSWindow? { get }

    /// 面板方向（左/右），可能为 nil（初始化阶段尚未注入）
    var panelSide: PaneSide? { get }

    /// 双击回调（打开文件/文件夹）
    var doubleClickHandler: ((FileEntry) -> Void)? { get }

    /// 当前选中的文件列表（来自 viewModel.selectedFiles）
    var selectedEntries: [FileEntry] { get }

    /// 右键点击的文件（nil 表示无右键点击或点击在空白处）
    var clickedEntry: FileEntry? { get }

    /// 获取当前单选项的重命名文本框（用于内联重命名）。
    /// 返回 nil 表示无法获取（如 cell 尚未实例化）。
    func renameTextFieldForSelection() -> NSTextField?

    /// 选中右键点击的项（用于右键菜单"重命名"——需单选后进入编辑模式）
    func selectClickedItemForRename()

    /// 重命名结束后的焦点恢复目标（列表视图为 tableView，网格视图为 collectionView）
    var focusRestoreTarget: NSResponder? { get }

    /// 刷新面板数据（标签变更、AI 标签生成后调用）
    func reloadPaneData()

    /// 标签二级菜单（动态构建，由控制器在 menuNeedsUpdate 中重建内容）
    var tagsSubmenu: NSMenu { get }
}

// MARK: - FFPaneActionsController

/// 文件面板统一操作控制器。
///
/// 架构目的：将 FileListView 与 FileGridView 中完全重复的操作逻辑提取到单一控制器，
/// 视图只需实现 `FFPaneViewHost` 协议即可获得完整的右键菜单操作、键盘操作、内联重命名、
/// AI 标签生成等能力。新增视图类型时无需复制任何操作代码，只需实现协议。
///
/// 控制器同时充当：
/// - 右键菜单 action 的 target（所有 @objc 方法）
/// - NSMenuDelegate（动态更新菜单项图标/可见性/标签子菜单）
/// - NSTextFieldDelegate（内联重命名编辑事件）
final class FFPaneActionsController: NSObject {

    weak var host: FFPaneViewHost?

    // MARK: - 内联重命名状态

    private var isRenaming = false
    private var renamingOriginalName: String = ""
    private var renamingPath: String = ""
    private weak var renamingTextField: NSTextField?
    private var renameCancelled = false

    // MARK: - 初始化

    init(host: FFPaneViewHost) {
        self.host = host
        super.init()
    }

    // MARK: - 辅助方法

    /// 获取面板方向字符串（"left" / "right"），用于通知 userInfo
    private func sideString() -> String {
        if let side = host?.panelSide {
            return side == .right ? "right" : "left"
        }
        return "left"
    }

    /// 当前面板是否为左面板（用于菜单箭头方向）
    private var isLeftPane: Bool {
        host?.panelSide != .right
    }

    /// 弹出错误提示框
    private func showError(_ error: Error) {
        guard let window = host?.hostWindow else { return }
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window) { _ in }
    }

    // MARK: - 右键菜单 Action 方法

    @objc func openSelected(_ sender: Any?) {
        guard let entry = host?.clickedEntry else { return }
        if entry.isDirectory {
            host?.doubleClickHandler?(entry)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    @objc func copySelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidCopy, object: nil, userInfo: ["side": sideString()])
    }

    @objc func cutSelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidCut, object: nil, userInfo: ["side": sideString()])
    }

    @objc func pasteSelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidPaste, object: nil, userInfo: ["side": sideString()])
    }

    @objc func renameSelected(_ sender: Any?) {
        guard host?.clickedEntry != nil else { return }
        host?.selectClickedItemForRename()
        beginInlineRename()
    }

    @objc func deleteSelected(_ sender: Any?) {
        guard let entries = host?.selectedEntries, !entries.isEmpty else { return }
        guard let window = host?.hostWindow else { return }
        let alert = NSAlert()
        alert.messageText = entries.count == 1 ? "删除\"\(entries[0].name)\"？" : "删除 \(entries.count) 个项目？"
        alert.informativeText = "此操作可通过 ⌘Z 撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.host?.viewModel?.deleteSelected()
        }
    }

    @objc func createDirectory(_ sender: Any?) {
        guard let currentPath = host?.viewModel?.currentPath,
              let window = host?.hostWindow else { return }
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "未命名文件夹"
        textField.selectText(nil)
        alert.accessoryView = textField
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty else { return }
            let newPath = (currentPath as NSString).appendingPathComponent(folderName)
            do {
                try CoreBridge.shared.createDirectory(path: newPath)
                self?.host?.viewModel?.refresh()
            } catch {
                self?.showError(error)
            }
        }
    }

    @objc func addToFavorites(_ sender: Any?) {
        guard let entry = host?.clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListDidAddFavorite, object: nil,
                                        userInfo: ["name": entry.name, "path": entry.path])
    }

    @objc func addTagMenu(_ sender: Any?) {
        guard let entry = host?.clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListAddTag, object: nil, userInfo: ["path": entry.path])
    }

    @objc func showInfoMenu(_ sender: Any?) {
        let targetPath = host?.clickedEntry?.path ?? host?.viewModel?.selectedFiles.first?.path
        FFLog.debug("[F10-10] showInfoMenu clicked, clickedEntry=\(host?.clickedEntry?.path ?? "nil"), fallback selectedFirst=\(host?.viewModel?.selectedFiles.first?.path ?? "nil"), final=\(targetPath ?? "nil")", log: FFLog.ui)
        if targetPath == nil || (targetPath?.isEmpty ?? true) {
            guard let window = host?.hostWindow else { return }
            let alert = NSAlert()
            alert.messageText = "显示简介"
            alert.informativeText = "请先选择一个文件后再查看简介。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.beginSheetModal(for: window) { _ in }
            return
        }
        NotificationCenter.default.post(name: .fileListShowInfo, object: nil, userInfo: ["path": targetPath ?? ""])
    }

    @objc func duplicateScan(_ sender: Any?) {
        DuplicateScanWindowController.shared.showWindow()
    }

    @objc func generateAITags(_ sender: Any?) {
        triggerAITagGeneration()
    }

    // MARK: - 跨面板操作

    @objc func copyToOtherPane(_ sender: Any?) {
        FFLog.debug("[F10-10] copyToOtherPane clicked, side=\(sideString()), clickedEntry=\(host?.clickedEntry?.path ?? "nil"), selectedCount=\(host?.selectedEntries.count ?? 0)", log: FFLog.ui)
        NotificationCenter.default.post(name: .fileListDidCopyToOther, object: nil,
                                        userInfo: ["side": sideString(), "clickedPath": host?.clickedEntry?.path])
    }

    @objc func moveToOtherPane(_ sender: Any?) {
        FFLog.debug("[F10-10] moveToOtherPane clicked, side=\(sideString()), clickedEntry=\(host?.clickedEntry?.path ?? "nil"), selectedCount=\(host?.selectedEntries.count ?? 0)", log: FFLog.ui)
        NotificationCenter.default.post(name: .fileListDidMoveToOther, object: nil,
                                        userInfo: ["side": sideString(), "clickedPath": host?.clickedEntry?.path])
    }

    @objc func openInOtherPane(_ sender: Any?) {
        guard let entry = host?.clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListDidOpenInOther, object: nil,
                                        userInfo: ["side": sideString(), "path": entry.path])
    }

    // MARK: - 键盘操作

    /// 统一键盘入口（MainWindowController 全局 keyDown monitor 调用）：
    /// 空格 → QuickLook，Enter → 内联重命名，Del → 移到废纸篓。
    @discardableResult
    func handlePaneKey(_ keyCode: UInt16) -> Bool {
        if keyCode == 49 {  // 空格
            NotificationCenter.default.post(name: .fileListRequestQuickLook, object: nil, userInfo: ["side": sideString()])
            return true
        }
        if keyCode == 36 || keyCode == 76 {  // Enter
            beginInlineRename()
            return true
        }
        if keyCode == 51 {  // Del
            deleteSelected(nil)
            return true
        }
        return false
    }

    /// 打开当前选中的条目（Cmd+O / Cmd+Down 触发，与双击行为一致）
    func openSelectedEntry() {
        guard let entry = host?.viewModel?.selectedFiles.first else { return }
        host?.doubleClickHandler?(entry)
    }

    // MARK: - 内联重命名

    /// 开始内联重命名：选中单个文件时按 Enter 或右键"重命名"触发。
    /// 视图特有的操作（获取文本框、选中项）通过协议委托给视图实现。
    func beginInlineRename() {
        guard !isRenaming else { return }
        guard let viewModel = host?.viewModel else { return }
        guard let textField = host?.renameTextFieldForSelection() else { return }

        // 获取单选文件
        guard viewModel.selectedFiles.count == 1 else { return }
        let entry = viewModel.selectedFiles[0]

        // 记录重命名上下文
        isRenaming = true
        renamingOriginalName = entry.name
        renamingPath = entry.path
        renamingTextField = textField
        renameCancelled = false

        // 进入编辑模式：先用完整文件名（含后缀）填充编辑框——
        // cell 显示名可能不含后缀（showFileExtensions=false 时），直接用显示名编辑
        // 会在提交时丢失后缀。与 Finder 一致：编辑框显示完整名，仅默认选中不含后缀部分。
        textField.stringValue = entry.name
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self

        guard host?.hostWindow?.makeFirstResponder(textField) == true else {
            // 无法进入编辑模式，清理状态
            textField.isEditable = false
            textField.delegate = nil
            isRenaming = false
            renamingOriginalName = ""
            renamingPath = ""
            renamingTextField = nil
            renameCancelled = false
            return
        }

        // 选中文件名（不含扩展名），与访达行为一致
        if let editor = textField.currentEditor() {
            let name = entry.name as NSString
            let extRange = name.range(of: ".", options: .backwards)
            if entry.isDirectory || extRange.location == NSNotFound || extRange.location == 0 {
                editor.selectAll(nil)
            } else {
                editor.selectedRange = NSRange(location: 0, length: extRange.location)
            }
        }
    }

    /// 结束内联重命名，根据取消标志决定是否提交。
    ///
    /// 修复历史 Bug：此前从 `control(_:textView:doCommandBy:)` 的 `insertNewline:` 分支
    /// 直接调用本方法时，NSTextField 的 field editor 尚未将最新文本同步到 `stringValue`，
    /// 导致读到旧值、"输入框消失但名字没变"。
    /// 修复方案：优先从 field editor（`currentEditor()`）读取最新文本。
    func endInlineRename() {
        guard isRenaming else { return }
        let textField = renamingTextField
        let originalName = renamingOriginalName
        let path = renamingPath
        let cancelled = renameCancelled

        // 清理状态
        isRenaming = false
        renamingOriginalName = ""
        renamingPath = ""
        renamingTextField = nil
        renameCancelled = false

        // 恢复 textField 为非编辑状态
        textField?.delegate = nil
        if let tf = textField {
            tf.isEditable = false
            if cancelled {
                tf.stringValue = originalName
            }
        }

        // 取消则不重命名
        guard !cancelled else {
            restoreFocus()
            return
        }

        // 提交重命名
        guard let tf = textField else {
            restoreFocus()
            return
        }

        // Bug 修复：优先从 field editor 读取最新文本。
        // control(_:doCommandBy:) 调用本方法时 field editor 仍活跃，
        // tf.stringValue 尚未同步为用户输入的最新值。
        let newName: String
        if let editor = tf.currentEditor() {
            newName = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        FFDebug.log("endInlineRename: path=\(path) newName=\(newName) cancelled=\(cancelled)")
        guard !newName.isEmpty, newName != originalName else {
            restoreFocus()
            return
        }

        // 后缀变更提醒（与 Finder 一致）：原文件有后缀且新名后缀不同 → 弹确认框
        let oldExt = (originalName as NSString).pathExtension
        let newExt = (newName as NSString).pathExtension
        if !oldExt.isEmpty && oldExt != newExt {
            let alert = NSAlert()
            alert.messageText = "是否保留扩展名"
            alert.informativeText = "原文件名以 \".\(oldExt)\" 结尾，新文件名没有该扩展名。是否仍要使用 \"\(newName)\"？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "使用新名称")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn {
                tf.stringValue = originalName
                restoreFocus()
                return
            }
        }

        host?.viewModel?.renameFile(path, to: newName)
        restoreFocus()
    }

    /// 恢复焦点到面板视图（tableView / collectionView）
    private func restoreFocus() {
        guard let target = host?.focusRestoreTarget else { return }
        host?.hostWindow?.makeFirstResponder(target)
    }

    // MARK: - AI 自动打标签

    /// AI 自动打标签公共入口（供侧边栏工具面板 AI 工具入口调用）。
    /// 优先使用当前选中文件列表，无选中时回退到右键点击的文件；两者皆无则不执行。
    func triggerAITagGeneration() {
        var entries = host?.selectedEntries ?? []
        if entries.isEmpty {
            if let entry = host?.clickedEntry {
                entries = [entry]
            } else {
                return
            }
        }

        let paths = entries.map { $0.path }
        let totalCount = paths.count

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var successCount = 0
            var totalTagsAdded = 0
            var xattrFailCount = 0
            var firstError: String?

            for path in paths {
                do {
                    let generatedTags = try CoreBridge.shared.generateAITags(path: path)
                    for genTag in generatedTags {
                        let tag = Tag(name: genTag.name, color: genTag.color)
                        if TagBridge.shared.addTag(tag, path: path) {
                            totalTagsAdded += 1
                        } else {
                            xattrFailCount += 1
                        }
                    }
                    successCount += 1
                } catch {
                    if firstError == nil {
                        firstError = error.localizedDescription
                    }
                }
            }

            DispatchQueue.main.async {
                guard let self = self, let window = self.host?.hostWindow else { return }

                if successCount == 0 {
                    let alert = NSAlert()
                    alert.messageText = "AI 标签生成失败"
                    alert.informativeText = firstError ?? "未知错误"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "关闭")
                    alert.beginSheetModal(for: window)
                    return
                }

                let alert = NSAlert()
                if successCount == totalCount {
                    alert.messageText = "已为 \(successCount) 个文件生成 AI 标签"
                    if totalTagsAdded > 0 {
                        var info = "共添加 \(totalTagsAdded) 个标签。"
                        if xattrFailCount > 0 {
                            info += "\n\(xattrFailCount) 个标签写入失败（权限不足或不支持扩展属性）。"
                        }
                        alert.informativeText = info
                    } else if xattrFailCount > 0 {
                        alert.informativeText = "标签写入失败（权限不足或不支持扩展属性）。"
                    } else {
                        alert.informativeText = "未识别到可分类的文件类型。"
                    }
                } else {
                    alert.messageText = "部分文件标签生成失败"
                    alert.informativeText = "成功 \(successCount) / 总计 \(totalCount)。\n\(firstError ?? "")"
                }
                alert.alertStyle = totalTagsAdded > 0 ? .informational : .warning
                alert.addButton(withTitle: "关闭")
                alert.beginSheetModal(for: window)

                self.host?.reloadPaneData()
            }
        }
    }
}

// MARK: - NSTextFieldDelegate（内联重命名编辑事件）

extension FFPaneActionsController: NSTextFieldDelegate {

    /// 处理编辑中的特殊按键（Enter 确认 / Esc 取消）
    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc：取消重命名
            renameCancelled = true
            endInlineRename()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Enter/Return：直接提交重命名。
            // 不依赖 makeFirstResponder 转移焦点触发 controlTextDidEndEditing——
            // 焦点转移失败时编辑不结束、无法提交（历史 Bug 根因）。
            // endInlineRename 内部会从 field editor 读取最新文本并恢复焦点。
            endInlineRename()
            return true
        default:
            return false
        }
    }

    /// 编辑结束（失焦自动确认 / Esc 取消）
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard isRenaming else { return }
        endInlineRename()
    }
}

// MARK: - NSMenuDelegate（动态更新右键菜单）

extension FFPaneActionsController: NSMenuDelegate {

    /// 菜单即将显示时更新：
    /// - 主菜单："打开"项图标根据选中项是文件夹还是文件动态切换
    ///           "标签"项仅当选中单个文件或右键单击时显示
    ///           "移动/复制到另一面板"箭头方向随面板方向同步
    ///           "在对侧面板打开"仅当右键点击项为文件夹时显示
    /// - 标签子菜单：每次显示前重建
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let isMainMenu = (menu !== host?.tagsSubmenu)
        if isMainMenu {
            updateMainMenu(menu)
        } else {
            rebuildTagsSubmenu(menu)
        }
    }

    /// 更新主右键菜单的动态项
    private func updateMainMenu(_ menu: NSMenu) {
        // "打开"项图标：文件夹用 folder，文件用 doc
        if let openItem = menu.items.first(where: { $0.title == "打开" }) {
            let isOpenFolder = host?.clickedEntry?.isDirectory == true
            openItem.image = NSImage(systemSymbolName: isOpenFolder ? "folder" : "doc",
                                     accessibilityDescription: "打开")
        }

        // "标签"项：仅当选中单个文件或右键单击时显示
        if let tagsItem = menu.items.first(where: { $0.title == "标签" }) {
            let selectedCount = host?.selectedEntries.count ?? 0
            let singleSelected = selectedCount == 1
            let hasClickedSingle = selectedCount == 0 && host?.clickedEntry != nil
            tagsItem.isHidden = !(singleSelected || hasClickedSingle)
        }

        // "移动/复制到另一面板"箭头方向
        let left = isLeftPane
        if let moveItem = menu.items.first(where: { $0.title == "移动到另一面板" }) {
            moveItem.image = NSImage(systemSymbolName: left ? "arrow.right" : "arrow.left",
                                     accessibilityDescription: "移动到另一面板")
        }
        if let copyOtherItem = menu.items.first(where: { $0.title == "复制到另一面板" }) {
            copyOtherItem.image = NSImage(systemSymbolName: left ? "arrow.right.square" : "arrow.left.square",
                                          accessibilityDescription: "复制到另一面板")
        }

        // "在对侧面板打开"仅当右键点击项为文件夹时显示
        if let openOtherItem = menu.items.first(where: { $0.title == "在对侧面板打开" }) {
            openOtherItem.isHidden = !(host?.clickedEntry?.isDirectory ?? false)
        }
    }

    // MARK: - 标签子菜单

    /// 重建标签二级子菜单
    /// - 顶部：列出现有所有标签（彩色圆点 + 名称，当前文件已有的显示 ✓）
    /// - 分隔线
    /// - "新建标签..." 项
    private func rebuildTagsSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let targetEntry = host?.clickedEntry ?? host?.viewModel?.selectedFiles.first
        guard let entry = targetEntry else {
            let createItem = NSMenuItem(title: "新建标签...", action: #selector(showCreateTagDialog(_:)), keyEquivalent: "")
            createItem.target = self
            createItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
            menu.addItem(createItem)
            return
        }

        let currentTags = TagBridge.shared.getTags(path: entry.path)
        let currentTagIds = Set(currentTags.map { $0.id })
        let currentTagNames = Set(currentTags.map { $0.name })

        let allTags = loadAllSidebarTags()
        for tag in allTags {
            let item = NSMenuItem(title: tag.name, action: #selector(toggleTagOnFile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["tagId": tag.id, "tagName": tag.name,
                                      "tagColor": tag.color, "path": entry.path]
            item.image = makeDotImage(colorHex: tag.color)
            if currentTagIds.contains(tag.id) || currentTagNames.contains(tag.name) {
                item.state = .on
            }
            menu.addItem(item)
        }

        if !allTags.isEmpty {
            menu.addItem(.separator())
        }

        let createItem = NSMenuItem(title: "新建标签...", action: #selector(showCreateTagDialog(_:)), keyEquivalent: "")
        createItem.target = self
        createItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
        menu.addItem(createItem)
    }

    /// 创建带颜色的圆点 NSImage（用于标签子菜单项图标）
    private func makeDotImage(colorHex: String) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let color = NSColor(hex: colorHex) ?? .systemBlue
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 8, height: 8)).fill()
        image.unlockFocus()
        return image
    }
}

// MARK: - 标签数据读写 + 对话框

extension FFPaneActionsController {

    /// 读取所有现有标签（从 UserDefaults "SidebarTags" 读取，与 SidebarView 共享存储）
    private func loadAllSidebarTags() -> [Tag] {
        guard let data = UserDefaults.standard.data(forKey: "SidebarTags"),
              let tags = try? JSONDecoder().decode([Tag].self, from: data) else {
            return []
        }
        return tags
    }

    /// 写回所有标签到 UserDefaults
    private func saveAllSidebarTags(_ tags: [Tag]) {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: "SidebarTags")
        }
    }

    /// 切换文件标签：已有则移除，没有则添加
    @objc private func toggleTagOnFile(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let tagId = info["tagId"],
              let tagName = info["tagName"],
              let path = info["path"] else { return }
        let tagColor = info["tagColor"] ?? "#007AFF"

        let currentTags = TagBridge.shared.getTags(path: path)
        if currentTags.contains(where: { $0.id == tagId || $0.name == tagName }) {
            _ = TagBridge.shared.removeTag(tagId, path: path)
        } else {
            let tag = Tag(id: tagId, name: tagName, color: tagColor)
            _ = TagBridge.shared.addTag(tag, path: path)
        }

        host?.reloadPaneData()
        let updatedTags = TagBridge.shared.getTags(path: path)
        NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil,
                                        userInfo: ["tags": updatedTags])
    }

    /// 新建标签对话框（创建后同时添加到当前右键目标文件）
    @objc private func showCreateTagDialog(_ sender: Any?) {
        guard let window = host?.hostWindow else { return }
        let alert = NSAlert()
        alert.messageText = "新建标签"
        alert.informativeText = "输入标签名称并选择颜色："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let containerWidth: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 64))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 36, width: containerWidth, height: 24))
        nameField.placeholderString = "标签名称"
        container.addSubview(nameField)

        let presetColors: [String] = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#5856D6"]
        let dotSize: CGFloat = 22
        let spacing: CGFloat = 8
        let totalDotsWidth = CGFloat(presetColors.count) * dotSize + CGFloat(presetColors.count - 1) * spacing
        let startX = (containerWidth - totalDotsWidth) / 2

        let colorHolder = FFCreateTagColorHolder(colors: presetColors)

        for (i, hex) in presetColors.enumerated() {
            let x = startX + CGFloat(i) * (dotSize + spacing)
            let dot = NSView(frame: NSRect(x: x, y: 4, width: dotSize, height: dotSize))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = (NSColor(hex: hex) ?? .systemBlue).cgColor
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.borderColor = NSColor.labelColor.cgColor
            dot.layer?.borderWidth = (i == 0) ? 2 : 0
            let click = NSClickGestureRecognizer(target: colorHolder,
                                                  action: #selector(FFCreateTagColorHolder.selectDot(_:)))
            dot.addGestureRecognizer(click)
            colorHolder.dotDots.append(dot)
            container.addSubview(dot)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        let targetPath = host?.clickedEntry?.path ?? host?.viewModel?.selectedFiles.first?.path

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let tag = Tag(name: name, color: colorHolder.selectedHex)

            var allTags = self?.loadAllSidebarTags() ?? []
            if !allTags.contains(where: { $0.name == tag.name }) {
                allTags.append(tag)
                self?.saveAllSidebarTags(allTags)
            }

            if let path = targetPath {
                _ = TagBridge.shared.addTag(tag, path: path)
                self?.host?.reloadPaneData()
            }

            var notifyTags = allTags
            if !notifyTags.contains(where: { $0.name == tag.name }) {
                notifyTags.append(tag)
            }
            NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil,
                                            userInfo: ["tags": notifyTags])
        }
    }
}
