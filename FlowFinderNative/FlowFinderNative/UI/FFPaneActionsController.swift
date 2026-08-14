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

    /// v0.7.4 修订 2：右键菜单撤销/重做（转发到窗口 UndoManager）
    @objc func undoFromMenu(_ sender: Any?) {
        host?.hostWindow?.undoManager?.undo()
    }

    @objc func redoFromMenu(_ sender: Any?) {
        host?.hostWindow?.undoManager?.redo()
    }

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
        guard let viewModel = host?.viewModel else { return }
        // 任务 T12: 删除进行中禁用重复触发（后台 I/O 期间拒绝再次删除，避免冲突操作）
        guard !viewModel.state.isDeleting else { return }
        // 任务 T12: 统一走 DeleteConfirmDialog.confirmDelete（全应用唯一确认入口），
        // 替换原 NSAlert 确认（第二套确认流程），"不再询问"语义与主菜单/重复扫描一致。
        DeleteConfirmDialog.confirmDelete(fileCount: entries.count, window: host?.hostWindow) { [weak self] in
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

    /// v0.7.4 项 6：用所选项目新建文件夹（创建新文件夹并把选中项移入，冲突弹窗询问）
    @objc func createFolderFromSelection(_ sender: Any?) {
        guard let window = host?.hostWindow else { return }
        host?.viewModel?.createFolderFromSelection(window: window)
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
    /// 空格 -> QuickLook，Enter -> 内联重命名，Del -> 移到废纸篓。
    @discardableResult
    func handlePaneKey(_ keyCode: UInt16) -> Bool {
        if keyCode == 49 {  // 空格
            NotificationCenter.default.post(name: .fileListRequestQuickLook, object: nil, userInfo: ["side": sideString()])
            return true
        }
        if keyCode == 36 || keyCode == 76 {  // Enter
            FFDebug.log("[RENAME-DIAG] handlePaneKey: 收到 Enter(keyCode=\(keyCode)), isRenaming=\(isRenaming), 将调用 beginInlineRename")
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
        guard !isRenaming else {
            FFDebug.log("[RENAME-DIAG] beginInlineRename: 跳过（已在重命名中）")
            return
        }
        guard let viewModel = host?.viewModel else {
            FFDebug.log("[RENAME-DIAG] beginInlineRename: 跳过（无 viewModel）")
            return
        }
        guard let textField = host?.renameTextFieldForSelection() else {
            FFDebug.log("[RENAME-DIAG] beginInlineRename: 跳过（无法获取 textField）")
            return
        }

        // 获取单选文件
        guard viewModel.selectedFiles.count == 1 else {
            FFDebug.log("[RENAME-DIAG] beginInlineRename: 跳过（选中数量=\(viewModel.selectedFiles.count)，需单选）")
            return
        }
        let entry = viewModel.selectedFiles[0]
        FFDebug.log("[RENAME-DIAG] beginInlineRename: 开始编辑 path=\(entry.path) originalName=\(entry.name)")

        // 记录重命名上下文
        isRenaming = true
        renamingOriginalName = entry.name
        renamingPath = entry.path
        renamingTextField = textField
        renameCancelled = false

        // 进入编辑模式：先用完整文件名（含后缀）填充编辑框--
        // cell 显示名可能不含后缀（showFileExtensions=false 时），直接用显示名编辑
        // 会在提交时丢失后缀。与 Finder 一致：编辑框显示完整名，仅默认选中不含后缀部分。
        textField.stringValue = entry.name
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self

        guard host?.hostWindow?.makeFirstResponder(textField) == true else {
            FFDebug.log("[RENAME-DIAG] beginInlineRename: makeFirstResponder 失败，清理状态返回")
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
        FFDebug.log("[RENAME-DIAG] beginInlineRename: 已进入编辑模式，textField 成为 firstResponder")

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
        guard isRenaming else {
            FFDebug.log("[RENAME-DIAG] endInlineRename: 跳过（isRenaming=false，可能已被处理）")
            return
        }
        let textField = renamingTextField
        let originalName = renamingOriginalName
        let path = renamingPath
        let cancelled = renameCancelled
        FFDebug.log("[RENAME-DIAG] endInlineRename: 进入 path=\(path) originalName=\(originalName) cancelled=\(cancelled)")

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
            FFDebug.log("[RENAME-DIAG] endInlineRename: 已取消，不重命名")
            restoreFocus()
            return
        }

        // 提交重命名
        guard let tf = textField else {
            FFDebug.log("[RENAME-DIAG] endInlineRename: textField 为 nil，无法重命名")
            restoreFocus()
            return
        }

        // 关键诊断：在清理状态/关闭编辑框之前，先记录此时 field editor 和 stringValue 的原始值
        let editorBefore = tf.currentEditor()?.string
        let stringValueBefore = tf.stringValue
        FFDebug.log("[RENAME-DIAG] endInlineRename: 读取时刻 [清理状态后/关闭编辑框前] hasEditor=\(tf.currentEditor() != nil) editor.string=\(editorBefore ?? "nil") tf.stringValue=\(stringValueBefore)")

        // Bug 修复：优先从 field editor 读取最新文本。
        // control(_:doCommandBy:) 调用本方法时 field editor 仍活跃，
        // tf.stringValue 尚未同步为用户输入的最新值。
        let newName: String
        if let editor = tf.currentEditor() {
            newName = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        FFDebug.log("[RENAME-DIAG] endInlineRename: 最终 newName=\(newName) (trimmed) 是否与原名相同=\(newName == originalName)")
        guard !newName.isEmpty, newName != originalName else {
            FFDebug.log("[RENAME-DIAG] endInlineRename: 名字为空或未变，不重命名 -> 这就是'名字变回旧值'的断点")
            restoreFocus()
            return
        }

        // 后缀变更提醒（与 Finder 一致）：原文件有后缀且新名后缀不同 -> 弹确认框
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
                FFDebug.log("[RENAME-DIAG] endInlineRename: 用户在扩展名确认框点了取消")
                tf.stringValue = originalName
                restoreFocus()
                return
            }
            FFDebug.log("[RENAME-DIAG] endInlineRename: 用户在扩展名确认框点了使用新名称")
        }

        FFDebug.log("[RENAME-DIAG] endInlineRename: 调用 renameFile path=\(path) newName=\(newName)")
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
            FFDebug.log("[RENAME-DIAG] control:doCommandBy cancelOperation(Esc): 触发，设 cancelled=true 调 endInlineRename")
            renameCancelled = true
            endInlineRename()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Enter/Return：直接提交重命名。
            // 不依赖 makeFirstResponder 转移焦点触发 controlTextDidEndEditing--
            // 焦点转移失败时编辑不结束、无法提交（历史 Bug 根因）。
            // endInlineRename 内部会从 field editor 读取最新文本并恢复焦点。
            FFDebug.log("[RENAME-DIAG] control:doCommandBy insertNewline(Enter确认): 触发，调 endInlineRename (isRenaming=\(isRenaming))")
            endInlineRename()
            return true
        default:
            return false
        }
    }

    /// 编辑结束（失焦自动确认 / Esc 取消）
    public func controlTextDidEndEditing(_ obj: Notification) {
        FFDebug.log("[RENAME-DIAG] controlTextDidEndEditing: 触发 (isRenaming=\(isRenaming))")
        guard isRenaming else {
            FFDebug.log("[RENAME-DIAG] controlTextDidEndEditing: isRenaming=false，跳过（防止双重调用）")
            return
        }
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
        // v0.7.4 修订 3：判断是否"空白处右键"（未点击任何文件且无选中项）
        let isBlankArea = host?.clickedEntry == nil && (host?.selectedEntries.isEmpty ?? true)

        // 空白处右键：精简菜单，只保留不需要选中文件的操作
        // 保留：粘贴 / 新建文件夹 / 查重扫描 / 撤销(动态) / 重做(动态)
        // 隐藏：打开 / 复制 / 剪切 / 移动与复制到另一面板 / 重命名 / 移到废纸篓 /
        //       添加到收藏 / 标签 / AI打标 / 显示简介 / 用所选新建文件夹
        if isBlankArea {
            // 固定保留的项（标题不变）
            let keepTitles = Set(["粘贴", "新建文件夹", "查重扫描"])
            for item in menu.items {
                if item.isSeparatorItem { continue }
                // 撤销/重做项用 tag 识别（100=撤销, 101=重做），单独按 canUndo/canRedo 判断
                if item.tag == 100 || item.tag == 101 { continue }
                item.isHidden = !keepTitles.contains(item.title)
            }
            // 撤销/重做项在空白处也按 canUndo/canRedo 独立判断
            updateUndoRedoMenuItems(menu)
            return
        }

        // 非空白处（点击了文件或有选中）：全部恢复可见，再按需动态调整
        for item in menu.items {
            if item.isSeparatorItem { continue }
            item.isHidden = false
        }
        // 撤销/重做项始终动态显示（不随"恢复可见"无条件显示）
        updateUndoRedoMenuItems(menu)

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

        // v0.7.4 项 6："用所选 X 个项目新建文件夹" 动态标题与显隐
        // 选中 2 个及以上项目时显示（标题带数量）；单选/无选中时隐藏
        if let folderFromSelItem = menu.items.first(where: { $0.title.contains("用所选") }) {
            let selectedCount = host?.selectedEntries.count ?? 0
            if selectedCount >= 2 {
                folderFromSelItem.title = "用所选 \(selectedCount) 个项目新建文件夹"
                folderFromSelItem.isHidden = false
            } else {
                folderFromSelItem.isHidden = true
            }
        }
    }

    // MARK: - v0.7.4 修订 2: 撤销/重做动态菜单项

    /// 动态更新右键菜单的撤销/重做项（用 tag 100/101 识别，避免标题变化后匹配失败）：
    /// - canUndo 为 true 时显示"撤销 X"（X 为操作名，如"撤销删除"），否则隐藏
    /// - canRedo 为 true 时显示"重做 X"，否则隐藏
    /// - 两者独立判断、互不影响
    private func updateUndoRedoMenuItems(_ menu: NSMenu) {
        guard let window = host?.hostWindow, let um = window.undoManager else { return }
        let canUndo = um.canUndo
        let canRedo = um.canRedo
        let undoName = um.undoActionName.isEmpty ? "" : um.undoActionName
        let redoName = um.redoActionName.isEmpty ? "" : um.redoActionName

        // tag 100 = 撤销项，tag 101 = 重做项
        for item in menu.items {
            if item.tag == 100 {
                item.title = canUndo ? "撤销\(undoName)" : "撤销"
                item.isHidden = !canUndo
            } else if item.tag == 101 {
                item.title = canRedo ? "重做\(redoName)" : "重做"
                item.isHidden = !canRedo
            }
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
            // 移除前先找到该标签（用于撤销时恢复）
            let tag = currentTags.first(where: { $0.id == tagId || $0.name == tagName })
            _ = TagBridge.shared.removeTag(tagId, path: path)
            if let tag = tag {
                host?.viewModel?.registerUndoRemoveTag(tag: tag, path: path)
            }
        } else {
            let tag = Tag(id: tagId, name: tagName, color: tagColor)
            _ = TagBridge.shared.addTag(tag, path: path)
            host?.viewModel?.registerUndoAddTag(tag: tag, path: path)
        }

        host?.reloadPaneData()
        let updatedTags = TagBridge.shared.getTags(path: path)
        NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil,
                                        userInfo: ["tags": updatedTags])
    }

    /// 新建标签对话框（创建后同时添加到当前右键目标文件）
    /// v0.7.4 项 1：统一改用共享模块 FFCreateTagDialog（预设色块 + 自定义系统颜色选择器）
    @objc private func showCreateTagDialog(_ sender: Any?) {
        guard let window = host?.hostWindow else { return }
        let targetPath = host?.clickedEntry?.path ?? host?.viewModel?.selectedFiles.first?.path

        FFCreateTagDialog.showCreateTagDialogAndSave(on: window) { [weak self] tag in
            guard let self = self else { return }
            if let path = targetPath {
                _ = TagBridge.shared.addTag(tag, path: path)
                self.host?.reloadPaneData()
            }
            NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil,
                                            userInfo: ["tags": FFCreateTagDialog.loadAllSidebarTags()])
        }
    }
}
