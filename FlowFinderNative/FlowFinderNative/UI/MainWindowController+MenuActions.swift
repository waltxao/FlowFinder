//
//  MainWindowController+MenuActions.swift
//  FlowFinderNative
//
//  T14: Menu Actions 扩展从 MainWindowController.swift 拆出（约 800 行）。
//  跨文件扩展访问的类成员已改为 fileprivate（activePaneViewModel/ffUndoManager/
//  showError/taskProgressBar/taskProgressBarHeightConstraint）。
//

import Cocoa

// MARK: - Menu Actions

extension MainWindowController {
    @objc func menuNewFolder(_ sender: Any?) {
        activePaneViewModel.createDirectory()
    }

    @objc func menuOpen(_ sender: Any?) {
        guard let entry = activePaneViewModel.selectedFiles.first else { return }
        if entry.isDirectory {
            activePaneViewModel.navigate(to: entry.path)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    @objc func menuMoveToTrash(_ sender: Any?) {
        let selectedFiles = activePaneViewModel.selectedFiles
        // 任务 T12: 删除进行中禁用重复触发（后台 I/O 期间拒绝再次删除）
        guard !activePaneViewModel.state.isDeleting else { return }
        // 任务 T12: 统一走 DeleteConfirmDialog.confirmDelete（全应用唯一确认入口）
        DeleteConfirmDialog.confirmDelete(fileCount: selectedFiles.count, window: window) { [weak self] in
            self?.activePaneViewModel.deleteSelected()
        }
    }

    @objc func menuAddTag(_ sender: Any?) {
        let selectedFiles = activePaneViewModel.selectedFiles
        guard let firstFile = selectedFiles.first else { return }
        // 获取当前文件的标签，并传入侧边栏标签供选择
        let currentTags = TagBridge.shared.getTags(path: firstFile.path)
        let allTags = sidebarView.allSidebarTags()
        let dialog = TagSelectorDialog(filePath: firstFile.path, currentTags: currentTags, allTags: allTags)
        if let window = window {
            dialog.beginSheetModal(for: window)
        }
    }

    @objc func menuGetInfo(_ sender: Any?) {
        // F9-C: 弹出独立 FileInfoWindow（仿访达 Get Info）。
        // 访达行为：显示选中项的第一个文件信息；无选中则不弹窗。
        guard let path = activePaneViewModel.selectedFiles.first?.path else { return }
        showFileInfo(forPath: path)
    }

    /// F9-C: 显示独立 FileInfoWindow（仿访达 Get Info）。
    /// 复用已有控制器并切换文件路径；窗口关闭后由 ARC 释放。
    /// - Parameter path: 文件绝对路径
    func showFileInfo(forPath path: String) {
        if let controller = fileInfoWindowController, controller.window != nil {
            controller.showInfoWindow(filePath: path)
        } else {
            let controller = FileInfoWindowController(filePath: path)
            fileInfoWindowController = controller
            controller.showWindow(nil)
        }
    }

    @objc func menuCopy(_ sender: Any?) {
        clipboardItems = activePaneViewModel.selectedFiles.map { $0.path }
        clipboardOperation = .copy
    }

    @objc func menuCut(_ sender: Any?) {
        clipboardItems = activePaneViewModel.selectedFiles.map { $0.path }
        clipboardOperation = .cut
    }

    @objc func menuPaste(_ sender: Any?) {
        guard !clipboardItems.isEmpty,
              let operation = clipboardOperation else { return }
        let destPath = activePaneViewModel.currentPath
        let srcs = clipboardItems

        // 任务 10：冲突预检与解决（替换/保留两者/跳过）
        let conflictPlan = ConflictResolver.resolveConflicts(
            srcPaths: srcs,
            destDir: destPath,
            window: window
        )
        guard !conflictPlan.isEmpty else { return }

        // 任务 F11-9：粘贴也属于复制/移动操作，展示底部进度栏反馈
        let operationName: String
        switch operation {
        case .copy: operationName = "复制"
        case .cut: operationName = "移动"
        }
        let totalCount = conflictPlan.count
        taskProgressBar.startDirectProgress(operation: operationName, totalCount: totalCount)
        showProgressBar(animated: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let total = conflictPlan.count
                let srcs = conflictPlan.normalSrcs
                let allSrcs = srcs + conflictPlan.keepBoth.map { $0.src }
                var success: Int
                let isMove: Bool
                switch operation {
                case .copy:
                    isMove = false
                    // 任务 F11-9：传入 progress 回调，实时更新底部进度栏
                    success = try CoreBridge.shared.parallelCopy(srcs: srcs, dstDir: destPath) { completed, total in
                        let opName = operationName
                        DispatchQueue.main.async { [weak self] in
                            self?.taskProgressBar.updateDirectProgress(
                                operation: opName,
                                currentFileName: nil,
                                completed: completed,
                                total: total
                            )
                        }
                    }
                case .cut:
                    isMove = true
                    success = try CoreBridge.shared.parallelMove(srcs: srcs, dstDir: destPath) { completed, total in
                        let opName = operationName
                        DispatchQueue.main.async { [weak self] in
                            self?.taskProgressBar.updateDirectProgress(
                                operation: opName,
                                currentFileName: nil,
                                completed: completed,
                                total: total
                            )
                        }
                    }
                }

                // 保留两者：逐项以改名后的目标名复制/移动（批量接口目标名取 lastPathComponent，无法表达改名）
                // 仅记录成功项为 (src, dst) 对，保持 src/dst 严格对齐，避免部分失败时 zip 静默截断
                var keepBothPairs: [(src: String, dst: String)] = []
                for pair in conflictPlan.keepBoth {
                    let dstFull = (destPath as NSString).appendingPathComponent(pair.dstName)
                    do {
                        switch operation {
                        case .copy:
                            try CoreBridge.shared.copyFile(src: pair.src, dst: dstFull)
                        case .cut:
                            try CoreBridge.shared.moveFile(src: pair.src, dst: dstFull)
                        }
                        success += 1
                        keepBothPairs.append((src: pair.src, dst: dstFull))
                    } catch {
                        // 单项失败：不计入 success，下方按 partial failure 统一提示
                    }
                }

                // I2: invalidate cache so the refresh sees the new state.
                // Destination always changes; for a move each source parent
                // directory also changes (items left those dirs). Best-effort.
                try? CoreBridge.shared.invalidateCache(path: destPath)
                if isMove {
                    let sourceDirs = Set(allSrcs.map { ($0 as NSString).deletingLastPathComponent })
                    for dir in sourceDirs where !dir.isEmpty {
                        try? CoreBridge.shared.invalidateCache(path: dir)
                    }
                }

                // I3: capture the detailed partial-failure message now
                // (getLastError is read-once) before the async UI refresh -
                // refresh -> listDirectory would otherwise consume it on its
                // own failure path. Appended to the user-facing alert.
                let partialDetail = (success < total) ? CoreBridge.shared.getLastError() : ""

                // 计算 dst 路径用于撤销注册（best-effort：假设都成功）。
                // 保留两者项仅计入成功者，normalDstPaths 与 keepBothPairs 顺序对齐，
                // undoPairs 由 src 列表 + 成功项组成，避免单项失败时 zip 错配 src↔dst
                let normalDstPaths = srcs.map { src -> String in
                    let name = (src as NSString).lastPathComponent
                    return (destPath as NSString).appendingPathComponent(name)
                }
                let undoPairs = zip(srcs, normalDstPaths).map { (src: $0, dst: $1) } + keepBothPairs

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.activePaneViewModel.refresh()

                    // 任务 F11-9：标记粘贴进度完成，2 秒后淡出收起
                    self.taskProgressBar.completeDirectProgress(operation: operationName, count: success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                        self?.hideProgressBar(animated: true)
                    }

                    // 注册撤销（仅当至少一个成功；best-effort）
                    // 问题 9：粘贴操作注册撤销（复制→删除目标；移动→移回源）
                    if success > 0 {
                        if isMove {
                            let pairs = undoPairs
                            let actionName = "移动 \(success) 个项目"
                            self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                                // undo: 移回原位。undoMoveBack 会同步注册 redo（redoMove），
                                // 而 redoMove 处理器内又会注册反向 undo（= undoMoveBack），
                                // 从而形成无限撤销/重做闭环。
                                ctrl.undoMoveBack(pairs: pairs, actionName: actionName)
                            }
                            self.ffUndoManager.setActionName(actionName)
                        } else {
                            let pairs = undoPairs
                            let actionName = "复制 \(success) 个项目"
                            self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                                // undo: 删除复制项。undoDeleteCopied 会同步注册 redo（redoCopy），
                                // 而 redoCopy 处理器内又会注册反向 undo（= undoDeleteCopied），
                                // 从而形成无限撤销/重做闭环。
                                ctrl.undoDeleteCopied(pairs: pairs, actionName: actionName)
                            }
                            self.ffUndoManager.setActionName(actionName)
                        }
                    }

                    if success < total {
                        self.showError(error: NSError(
                            domain: "FlowFinder", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "\(total - success) 个项目粘贴失败：\(partialDetail)"])
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showError(error: error)
                    // 任务 F11-9：失败时也收起进度栏
                    self?.taskProgressBar.hide()
                    self?.hideProgressBar(animated: true)
                }
            }
        }
    }

    // MARK: - 撤销辅助（问题 9）

    /// 撤销"移动"：把文件移回源位置，并同步注册 redo（redoMove）。
    /// redoMove 处理器内又会注册反向 undo（= undoMoveBack），从而形成无限撤销/重做闭环：
    /// 撤销→重做→撤销→重做…可无限进行。文件操作经 undoRedoQueue 串行化，排队在上一操作之后，避免竞态。
    func undoMoveBack(pairs: [(src: String, dst: String)], actionName: String) {
        // 必须先注册 redo 再排队文件操作：registerUndo 在撤销会话内（isUndoing）会路由到 redo 栈，
        // 而文件操作异步执行，需先建立 redo 栈再排队，否则重做栈可能为空。
        undoManager?.registerUndo(withTarget: self) { ctrl in
            ctrl.redoMove(pairs: pairs, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        Self.undoRedoQueue.async { [weak self] in
            for pair in pairs {
                try? CoreBridge.shared.moveFile(src: pair.dst, dst: pair.src)
            }
            DispatchQueue.main.async {
                self?.refreshPane(.left)
                self?.refreshPane(.right)
            }
        }
    }

    /// 重做"移动"：把文件再次移动到目标位置（与初始移动相同）。
    /// 处理器内同步注册反向 undo（undoMoveBack，路由到 undo 栈，isRedoing == true），
    /// 从而形成无限撤销/重做闭环。
    func redoMove(pairs: [(src: String, dst: String)], actionName: String) {
        // 先注册反向 undo 再排队文件操作：registerUndo 在重做会话内（isRedoing）路由到 undo 栈。
        undoManager?.registerUndo(withTarget: self) { ctrl in
            ctrl.undoMoveBack(pairs: pairs, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        Self.undoRedoQueue.async { [weak self] in
            for (src, dst) in pairs {
                try? CoreBridge.shared.moveFile(src: src, dst: dst)
            }
            DispatchQueue.main.async {
                self?.refreshPane(.left)
                self?.refreshPane(.right)
            }
        }
    }

    /// 撤销"复制"：删除刚粘贴的目标文件，并同步注册 redo（redoCopy）。
    /// redoCopy 处理器内又会注册反向 undo（= undoDeleteCopied），从而形成无限撤销/重做闭环：
    /// 撤销→重做→撤销→重做…可无限进行。文件操作经 undoRedoQueue 串行化，排队在上一操作之后，避免竞态。
    func undoDeleteCopied(pairs: [(src: String, dst: String)], actionName: String) {
        // 必须先注册 redo 再排队文件操作：registerUndo 在撤销会话内（isUndoing）会路由到 redo 栈，
        // 而文件操作异步执行，需先建立 redo 栈再排队，否则重做栈可能为空。
        undoManager?.registerUndo(withTarget: self) { ctrl in
            ctrl.redoCopy(pairs: pairs, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        Self.undoRedoQueue.async { [weak self] in
            for pair in pairs {
                try? CoreBridge.shared.deleteFile(path: pair.dst)
            }
            DispatchQueue.main.async {
                self?.refreshPane(.left)
                self?.refreshPane(.right)
            }
        }
    }

    /// 重做"复制"：重新复制目标文件（与初始复制相同）。
    /// 处理器内同步注册反向 undo（undoDeleteCopied，路由到 undo 栈，isRedoing == true），
    /// 从而形成无限撤销/重做闭环。
    func redoCopy(pairs: [(src: String, dst: String)], actionName: String) {
        // 先注册反向 undo 再排队文件操作：registerUndo 在重做会话内（isRedoing）路由到 undo 栈。
        undoManager?.registerUndo(withTarget: self) { ctrl in
            ctrl.undoDeleteCopied(pairs: pairs, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        Self.undoRedoQueue.async { [weak self] in
            for (src, dst) in pairs {
                try? CoreBridge.shared.copyFile(src: src, dst: dst)
            }
            DispatchQueue.main.async {
                self?.refreshPane(.left)
                self?.refreshPane(.right)
            }
        }
    }

    // MARK: - FileListView 右键菜单通知处理

    @objc func handleFileListCopy(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        let vm = side == "left" ? leftPaneViewModel : rightPaneViewModel
        clipboardItems = vm.selectedFiles.map { $0.path }
        clipboardOperation = .copy
        activatePane(side == "left" ? .left : .right)
    }

    @objc func handleFileListCut(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        let vm = side == "left" ? leftPaneViewModel : rightPaneViewModel
        clipboardItems = vm.selectedFiles.map { $0.path }
        clipboardOperation = .cut
        activatePane(side == "left" ? .left : .right)
    }

    @objc func handleFileListPaste(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        activatePane(side == "left" ? .left : .right)
        menuPaste(self)
    }

    @objc func handleFileListAddFavorite(_ notification: Notification) {
        guard let name = notification.userInfo?["name"] as? String,
              let path = notification.userInfo?["path"] as? String else { return }
        sidebarView.addFavorite(name: name, path: path)
    }

    // MARK: - Cross-Pane Operations

    @objc func handleFileListCopyToOther(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        // 问题12修复：取出右键点击文件路径，传入操作方法做空选兜底
        let clickedPath = notification.userInfo?["clickedPath"] as? String
        performCrossPaneOperation(side: side, isMove: false, clickedPath: clickedPath)
    }

    @objc func handleFileListMoveToOther(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String else { return }
        // 问题12修复：取出右键点击文件路径，传入操作方法做空选兜底
        let clickedPath = notification.userInfo?["clickedPath"] as? String
        performCrossPaneOperation(side: side, isMove: true, clickedPath: clickedPath)
    }

    @objc func handleFileListOpenInOther(_ notification: Notification) {
        guard let side = notification.userInfo?["side"] as? String,
              let path = notification.userInfo?["path"] as? String else { return }
        let destVM: PaneViewModel = side == "left" ? rightPaneViewModel : leftPaneViewModel
        destVM.navigate(to: path)
        let destSide: PaneSide = side == "left" ? .right : .left
        activatePane(destSide)
    }

    /// 执行跨面板复制/移动操作
    /// 任务 F11-9（问题1）：增加底部进度栏反馈，避免大文件复制/移动时"无提示"误以为不生效
    /// 问题12修复：
    ///   1. 空选兜底——无选中时使用右键点击的文件（clickedPath）作为操作对象，不再静默返回
    ///   2. 同目录保护——源与目标为同一目录时提示并返回
    ///   3. 改用 parallelMove/parallelCopy 批量接口，解决跨卷 move 失败问题
    ///      （parallelMove 内部对跨卷移动自动回退为复制+删除）
    private func performCrossPaneOperation(side: String, isMove: Bool, clickedPath: String? = nil) {
        let sourceVM: PaneViewModel = side == "left" ? leftPaneViewModel : rightPaneViewModel
        let destVM: PaneViewModel = side == "left" ? rightPaneViewModel : leftPaneViewModel
        let destPath = destVM.currentPath

        // 问题12修复：同目录保护——源与目标为同一目录，操作无意义
        if sourceVM.currentPath == destPath {
            let alert = NSAlert()
            alert.messageText = "无法操作"
            alert.informativeText = "目标目录与源目录相同，请先切换对侧面板到其他目录。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }

        // 问题12修复：空选兜底——无选中文件时使用右键点击的文件作为操作对象
        var selectedFiles = sourceVM.selectedFiles
        if selectedFiles.isEmpty, let path = clickedPath, !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            let isDir = (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory
            selectedFiles = [FileEntry(path: path, name: name, isDirectory: isDir, isFile: !isDir)]
        }
        guard !selectedFiles.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无选中文件"
            alert.informativeText = "请先选择要\(isMove ? "移动" : "复制")的文件，或在文件上右键选择操作。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }

        // 修复问题4：跨面板移动/复制重名时不再自动"副本N"后缀，改为弹出冲突对话框
        // （替换/保留两者/跳过，与拖拽/粘贴路径一致，走 ConflictResolver）。
        let operationName = isMove ? "移动" : "复制"
        let srcPaths = selectedFiles.map { $0.path }
        let conflictPlan = ConflictResolver.resolveConflicts(
            srcPaths: srcPaths,
            destDir: destPath,
            window: window
        )
        guard !conflictPlan.isEmpty else { return }

        let totalCount = conflictPlan.count
        taskProgressBar.startDirectProgress(operation: operationName, totalCount: totalCount)
        showProgressBar(animated: true)

        // 无冲突/替换项走批量接口；保留两者项逐项改名复制/移动（与 menuPaste 一致）
        let batchSrcs = conflictPlan.normalSrcs
        let keepBothPairs = conflictPlan.keepBoth

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var successCount = 0
            var failedFiles: [(String, Error)] = []
            // 记录每个成功操作的 (src, dst) 用于撤销注册
            var movedOrCopied: [(src: String, dst: String)] = []
            var completed = 0

            // 跨卷安全移动：moveFile 跨卷会失败，失败时回退 copyFile + deleteFile
            func safeMove(src: String, dst: String) throws {
                do {
                    try CoreBridge.shared.moveFile(src: src, dst: dst)
                } catch {
                    try CoreBridge.shared.copyFile(src: src, dst: dst)
                    try CoreBridge.shared.deleteFile(path: src)
                }
            }

            // 1) 批量处理无冲突/替换文件（parallel 接口，跨卷移动自动回退复制+删除）
            if !batchSrcs.isEmpty {
                let batchSrcList = batchSrcs
                let batchCount = batchSrcList.count
                let progressHandler: ((Int, Int) -> Void)? = { done, _ in
                    let displayDone = done
                    DispatchQueue.main.async { [weak self] in
                        self?.taskProgressBar.updateDirectProgress(
                            operation: operationName,
                            currentFileName: "正在\(operationName)…",
                            completed: displayDone,
                            total: totalCount
                        )
                    }
                }
                do {
                    let ok = isMove
                        ? try CoreBridge.shared.parallelMove(srcs: batchSrcList, dstDir: destPath, progress: progressHandler)
                        : try CoreBridge.shared.parallelCopy(srcs: batchSrcList, dstDir: destPath, progress: progressHandler)
                    successCount += ok
                    for src in batchSrcList {
                        movedOrCopied.append((src: src, dst: (destPath as NSString).appendingPathComponent((src as NSString).lastPathComponent)))
                    }
                } catch {
                    // 批量失败：将每个文件记为失败
                    for src in batchSrcList {
                        failedFiles.append(((src as NSString).lastPathComponent, error))
                    }
                }
                completed += batchCount
                let c = completed
                DispatchQueue.main.async { [weak self] in
                    self?.taskProgressBar.updateDirectProgress(
                        operation: operationName,
                        currentFileName: "正在\(operationName)…",
                        completed: min(c, totalCount),
                        total: totalCount
                    )
                }
            }

            // 2) 逐个处理"保留两者"文件（按用户选择的副本名复制/移动）
            for pair in keepBothPairs {
                let dstPath = (destPath as NSString).appendingPathComponent(pair.dstName)
                let preCompleted = completed
                DispatchQueue.main.async { [weak self] in
                    self?.taskProgressBar.updateDirectProgress(
                        operation: operationName,
                        currentFileName: pair.dstName,
                        completed: preCompleted,
                        total: totalCount
                    )
                }
                do {
                    if isMove {
                        try safeMove(src: pair.src, dst: dstPath)
                    } else {
                        try CoreBridge.shared.copyFile(src: pair.src, dst: dstPath)
                    }
                    movedOrCopied.append((src: pair.src, dst: dstPath))
                    successCount += 1
                } catch {
                    failedFiles.append((pair.dstName, error))
                }
                completed += 1
                let c = completed
                DispatchQueue.main.async { [weak self] in
                    self?.taskProgressBar.updateDirectProgress(
                        operation: operationName,
                        currentFileName: pair.dstName,
                        completed: min(c, totalCount),
                        total: totalCount
                    )
                }
            }

            // 失效缓存：跨面板操作改变了源目录和目标目录的文件列表，
            // 必须在 refresh 之前失效缓存，否则 refresh 会命中过期缓存
            try? CoreBridge.shared.invalidateCache(path: destPath)
            if isMove {
                let sourceDir = (selectedFiles.first?.path as NSString?)?.deletingLastPathComponent ?? ""
                if !sourceDir.isEmpty {
                    try? CoreBridge.shared.invalidateCache(path: sourceDir)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 刷新双方面板
                sourceVM.refresh()
                destVM.refresh()

                // 任务 F11-9：标记进度完成，显示"复制/移动完成：N 个项目"，2 秒后淡出收起
                self.taskProgressBar.completeDirectProgress(operation: operationName, count: successCount)
                // 延迟 2.2 秒收起进度栏（比 TaskProgressBar 内部 2.0s 淡出稍晚，确保淡出动画完成后再收起高度）
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    self?.hideProgressBar(animated: true)
                }

                // 注册撤销（仅对成功的操作）
                if !movedOrCopied.isEmpty {
                    let undoItems = movedOrCopied
                    if isMove {
                        let actionName = "移动 \(undoItems.count) 个项目"
                        self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                            // undo: 移回原位。undoMoveBack 会同步注册 redo（redoMove），
                            // 而 redoMove 处理器内又会注册反向 undo（= undoMoveBack），
                            // 从而形成无限撤销/重做闭环。
                            ctrl.undoMoveBack(pairs: undoItems, actionName: actionName)
                        }
                        self.ffUndoManager.setActionName(actionName)
                    } else {
                        let actionName = "复制 \(undoItems.count) 个项目"
                        self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                            // undo: 删除复制项。undoDeleteCopied 会同步注册 redo（redoCopy），
                            // 而 redoCopy 处理器内又会注册反向 undo（= undoDeleteCopied），
                            // 从而形成无限撤销/重做闭环。
                            ctrl.undoDeleteCopied(pairs: undoItems, actionName: actionName)
                        }
                        self.ffUndoManager.setActionName(actionName)
                    }
                }

                // 显示错误（如果有）
                if !failedFiles.isEmpty {
                    let fileNames = failedFiles.map { $0.0 }.joined(separator: ", ")
                    self.showError(error: NSError(domain: "FlowFinder", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "\(failedFiles.count) 个文件操作失败: \(fileNames)"]))
                }
            }
        }
    }

    // MARK: - Menu Bar Cross-Pane Actions

    @objc func menuCopyToOther(_ sender: Any?) {
        let side = activePane == .left ? "left" : "right"
        performCrossPaneOperation(side: side, isMove: false)
    }

    @objc func menuMoveToOther(_ sender: Any?) {
        let side = activePane == .left ? "left" : "right"
        performCrossPaneOperation(side: side, isMove: true)
    }

    @objc func menuOpenInOther(_ sender: Any?) {
        guard let entry = activePaneViewModel.selectedFiles.first,
              entry.isDirectory else { return }
        let destVM: PaneViewModel = activePane == .left ? rightPaneViewModel : leftPaneViewModel
        destVM.navigate(to: entry.path)
        activatePane(activePane == .left ? .right : .left)
    }

    @objc func menuSelectAll(_ sender: Any?) {
        activePaneViewModel.selectAll()
    }

    @objc func menuRename(_ sender: Any?) {
        guard let entry = activePaneViewModel.selectedFiles.first else { return }
        let alert = NSAlert()
        alert.messageText = "重命名 \"\(entry.name)\""
        alert.informativeText = "输入新名称："
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = entry.name
        alert.accessoryView = textField
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !newName.isEmpty, newName != entry.name else { return }
                self?.activePaneViewModel.renameFile(entry.path, to: newName)
            }
        }
    }

    @objc func menuBatchRename(_ sender: Any?) {
        let selected = activePaneViewModel.selectedFiles
        guard selected.count >= 2 else { return }
        BatchRenameWindowController.shared.showWindow(selectedFiles: selected, paneViewModel: activePaneViewModel)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Bug 8 修复：先 guard action 非 nil（separator 等无 action 项不会进入此回调，
        // 但仍做防御性检查），避免后续比较中误访问
        guard let action = item.action else { return false }

        let hasSelection = !activePaneViewModel.selectedFiles.isEmpty

        switch action {
        case #selector(menuBatchRename(_:)):
            return activePaneViewModel.selectedFiles.count >= 2
        // Bug 8 修复：对需要选中文本才能生效的菜单项做防御性校验，避免无选中时误触导致后续 nil 访问
        case #selector(menuOpen(_:)),
             #selector(menuMoveToTrash(_:)),
             #selector(menuCopy(_:)),
             #selector(menuCut(_:)),
             #selector(menuRename(_:)),
             #selector(menuCopyToOther(_:)),
             #selector(menuMoveToOther(_:)):
            return hasSelection
        case #selector(menuOpenInOther(_:)):
            // 仅当选中项为目录时可用
            return activePaneViewModel.selectedFiles.first?.isDirectory ?? false
        default:
            return true
        }
    }

    @objc func menuListView(_ sender: Any?) {
        activePaneViewModel.setViewMode(.list)
        updateViewMode(side: activePane, mode: .list)
    }

    @objc func menuGridView(_ sender: Any?) {
        activePaneViewModel.setViewMode(.grid)
        updateViewMode(side: activePane, mode: .grid)
    }

    @objc func menuToggleHiddenFiles(_ sender: Any?) {
        // Phase 4 实现
    }

    @objc func menuRefresh(_ sender: Any?) {
        activePaneViewModel.refresh()
    }

    @objc func menuGoBack(_ sender: Any?) {
        _ = activePaneViewModel.goBack()
    }

    @objc func menuGoForward(_ sender: Any?) {
        _ = activePaneViewModel.goForward()
    }

    @objc func menuGoUp(_ sender: Any?) {
        activePaneViewModel.goUp()
    }

    @objc func menuGoDesktop(_ sender: Any?) {
        let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop")
        activePaneViewModel.navigate(to: path)
    }

    @objc func menuGoDocuments(_ sender: Any?) {
        let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Documents")
        activePaneViewModel.navigate(to: path)
    }

    @objc func menuGoDownloads(_ sender: Any?) {
        let path = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
        activePaneViewModel.navigate(to: path)
    }

    @objc func menuGoHome(_ sender: Any?) {
        activePaneViewModel.navigate(to: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @objc func menuConnectServer(_ sender: Any?) {
        guard let window = window else { return }
        let dialog = ConnectServerDialog { result in
            guard let url = result.smbURL() else { return }
            SMBBridge.shared.mount(url: url.absoluteString) { mountResult in
                DispatchQueue.main.async {
                    switch mountResult {
                    case .success:
                        break
                    case .failure(let error):
                        let alert = NSAlert()
                        alert.messageText = "连接失败"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "好")
                        alert.runModal()
                    }
                }
            }
        }
        dialog.beginSheetModal(for: window)
    }

    @objc func menuSearch(_ sender: Any?) {
        let path = activePaneViewModel.currentPath
        SearchPanelController.shared.onNavigateToPath = { [weak self] resultPath in
            self?.activePaneViewModel.navigate(to: (resultPath as NSString).deletingLastPathComponent)
        }
        SearchPanelController.shared.showPanel(initialQuery: "", searchPath: path)
    }

    @objc func menuDuplicateScan(_ sender: Any?) {
        DuplicateScanWindowController.shared.showWindow()
    }

    @objc func menuTaskPanel(_ sender: Any?) {
        TaskPanelWindowController.shared.showWindow()
    }

    @objc func menuSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow()
    }

    // MARK: - Helpers

    var activePaneViewModel: PaneViewModel {
        activePane == .left ? leftPaneViewModel : rightPaneViewModel
    }

    // MARK: - 底部进度栏（任务 F11-9）

    /// 展开底部进度栏（高度从 0 动画到 28pt 并显示）
    /// - Parameter animated: 是否使用动画展开
    private func showProgressBar(animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.taskProgressBar.isHidden = false
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = FFMotion.animationDuration(0.2)
                    context.allowsImplicitAnimation = true
                    self.taskProgressBarHeightConstraint.animator().constant = TaskProgressBar.height
                    self.taskProgressBar.layoutSubtreeIfNeeded()
                }, completionHandler: nil)
            } else {
                self.taskProgressBarHeightConstraint.constant = TaskProgressBar.height
            }
        }
    }

    /// 收起底部进度栏（高度从 28 动画回 0 并隐藏）
    /// - Parameter animated: 是否使用动画收起
    private func hideProgressBar(animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = FFMotion.animationDuration(0.2)
                    context.allowsImplicitAnimation = true
                    self.taskProgressBarHeightConstraint.animator().constant = 0
                    self.taskProgressBar.layoutSubtreeIfNeeded()
                }, completionHandler: {
                    self.taskProgressBar.isHidden = true
                })
            } else {
                self.taskProgressBarHeightConstraint.constant = 0
                self.taskProgressBar.isHidden = true
            }
        }
    }

    func showError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        if let window = window { alert.beginSheetModal(for: window) { _ in } }
    }
}

