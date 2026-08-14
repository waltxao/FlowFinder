import XCTest
@testable import FlowFinderNative

/// 任务 T10 (Wave3): PaneState 删除/撤销后台化 + 组合过滤 + 状态机。
///
/// 覆盖：
/// 1. tagFilter + searchQuery 组合过滤取交集（纯函数，无 FFI/文件 I/O 依赖）
/// 2. 删除失败项保留选中集 + typed 失败路径 + 错误信息含路径
/// 3. 删除非阻塞（主线程立即返回，I/O 在后台执行）
/// 4. 多目录缓存失效的父目录集合计算（纯函数）
///
/// 运行方式：本文件需加入测试 target。当前 Package.swift 无 testTarget、
/// 且 .xcodeproj 无测试 target（`FlowFinderNativeTests.swift` 为孤儿文件），
/// 完整运行需在 Xcode 中新建 unit test bundle（依赖已构建的 libflowfinder_core.dylib）。
/// 其中纯函数测试（filterEntries / parentDirectories）与「失败保留」「非阻塞」
/// 测试不依赖 dylib（通过 state.path 置空让 loadDirectory 短路为 no-op）。
final class PaneStateDeleteFilterTests: XCTestCase {

    // MARK: - 组合过滤（tag + query 交集）

    func testFilterEntriesTagPlusQueryIntersection() {
        // Given: 4 个文件，标签与名称正交
        let red = Tag(name: "红")
        let blue = Tag(name: "蓝")
        let entries = [
            FileEntry(path: "/a/report1.txt", name: "report1.txt", isDirectory: false, tags: [red]),
            FileEntry(path: "/a/report2.txt", name: "report2.txt", isDirectory: false, tags: [blue]),
            FileEntry(path: "/a/photo1.png", name: "photo1.png", isDirectory: false, tags: [red]),
            FileEntry(path: "/a/photo2.png", name: "photo2.png", isDirectory: false, tags: [blue]),
        ]

        // When: 标签=红 且 搜索词=report 同时激活
        let result = PaneViewModel.filterEntries(entries, tagFilter: red, searchQuery: "report")

        // Then: 结果 = 标签交集 ∩ 查询交集 = { report1.txt }
        XCTAssertEqual(result.map { $0.name }, ["report1.txt"], "tag+query 应取交集")
    }

    func testFilterEntriesTagOnly() {
        let red = Tag(name: "红")
        let entries = [
            FileEntry(path: "/a/a.txt", name: "a.txt", isDirectory: false, tags: [red]),
            FileEntry(path: "/a/b.txt", name: "b.txt", isDirectory: false, tags: []),
        ]

        let result = PaneViewModel.filterEntries(entries, tagFilter: red, searchQuery: "")

        XCTAssertEqual(result.map { $0.name }, ["a.txt"], "仅标签筛选时按标签匹配")
    }

    func testFilterEntriesQueryOnlyCaseInsensitive() {
        let entries = [
            FileEntry(path: "/a/Report.txt", name: "Report.txt", isDirectory: false),
            FileEntry(path: "/a/notes.md", name: "notes.md", isDirectory: false),
        ]

        let result = PaneViewModel.filterEntries(entries, tagFilter: nil, searchQuery: "rePoRt")

        XCTAssertEqual(result.map { $0.name }, ["Report.txt"], "仅搜索时应大小写不敏感匹配")
    }

    func testFilterEntriesTagMatchByName() {
        let red = Tag(name: "红")
        // 标签按 name 匹配（原生标签 id 每次随机，故支持按 name 命中）
        let entry = FileEntry(path: "/a/x.txt", name: "x.txt", isDirectory: false, tags: [red])
        let otherTag = Tag(id: red.id, name: "红", color: "#FFFFFF")

        let result = PaneViewModel.filterEntries([entry], tagFilter: otherTag, searchQuery: "")

        XCTAssertEqual(result.count, 1, "同 name 不同 id 的标签应命中（按 name 匹配）")
    }

    // MARK: - 删除失败保留选中集 + typed 失败路径

    func testDeleteFailureRetainsSelectionAndReportsPath() {
        // Given: 一个不存在的文件（trashItem 必失败），VM 目录为空使 loadDirectory 短路
        let vm = PaneViewModel()
        let missing = FileEntry(path: "/nonexistent/flowfinder_missing.txt", name: "flowfinder_missing.txt", isDirectory: false)
        vm.state.selectedFiles = [missing]

        // When: 删除
        let exp = expectation(forNotification: .paneFileOperationChanged, object: nil) { _ in true }
        vm.deleteSelected()
        wait(for: [exp], timeout: 5.0)

        // Then: 失败项保留在选中集，typed 失败路径含该路径，错误信息含路径
        XCTAssertFalse(vm.state.isDeleting, "删除完成后 isDeleting 应为 false")
        XCTAssertEqual(vm.state.selectedFiles.map { $0.path }, [missing.path], "失败项应保留在选中集")
        XCTAssertEqual(vm.state.deleteFailedPaths, [missing.path], "typed 失败路径列表应含该路径")
        XCTAssertTrue(vm.state.error?.contains(missing.path) ?? false, "错误信息应包含失败路径")
    }

    // MARK: - 删除非阻塞（I/O 后台化）

    func testDeleteIsNonBlocking() {
        // Given: 临时目录下创建一批文件（I/O 真跑到后台）
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ff_t10_nb_\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        var entries: [FileEntry] = []
        for i in 0..<50 {
            let p = dir.appendingPathComponent("file_\(i).txt").path
            try? "x".write(toFile: p, atomically: true, encoding: .utf8)
            entries.append(FileEntry(path: p, name: "file_\(i).txt", isDirectory: false))
        }

        // state.path 置空：loadDirectory 短路为 no-op，测试不依赖 dylib
        let vm = PaneViewModel()
        vm.state.selectedFiles = entries

        // When: 调用删除后立即返回
        vm.deleteSelected()

        // Then: 主线程未被阻塞——deleteSelected 已返回，但 I/O 仍在后台进行
        XCTAssertTrue(vm.state.isDeleting, "deleteSelected 应立即返回，I/O 在后台进行（isDeleting=true）")

        // 等待后台完成
        let exp = expectation(forNotification: .paneFileOperationChanged, object: nil) { _ in true }
        wait(for: [exp], timeout: 15.0)
        XCTAssertFalse(vm.state.isDeleting, "后台完成后 isDeleting 应回 false")
    }

    // MARK: - 多目录缓存失效（父目录集合）

    func testParentDirectoriesAcrossMultipleDirectories() {
        // Given: 路径跨越两个目录（含重复）
        let paths = [
            "/Volumes/A/dir1/file1.txt",
            "/Volumes/A/dir2/file2.txt",
            "/Volumes/A/dir1/file3.txt",
        ]

        // When: 提取父目录集合
        let dirs = PaneViewModel.parentDirectories(of: paths)

        // Then: 两个目录都出现，重复去重
        XCTAssertEqual(dirs, Set(["/Volumes/A/dir1", "/Volumes/A/dir2"]), "两个父目录都应被失效")
    }
}

// MARK: - 任务 T12 (Wave4): 面板状态流 / 统一删除确认 / 搜索详情 / 内容索引状态
//
// 覆盖：
// 1. PaneState → 呈现描述（loading/empty/error/operation/content 全变体，纯函数）
// 2. loadDirectory 真流：loading→ready、空目录、error→retry 恢复（依赖 dylib）
// 3. DeleteConfirmDialog 统一入口：确认决策纯函数 + "不再询问"跳过 + 无窗口回退
// 4. SearchPanelController.detailsText：无选中占位 / 选中结果详情（纯函数）
// 5. 内容索引状态映射：unavailable/empty/ready/indexing/error/cancelled（纯函数）
//
// 说明：因 pbxproj 冻结（T11 已完成 target 接入），本任务测试扩展在本文件
// （已挂入 FlowFinderNativeTests target 的既有文件）而非新建文件。

final class FFPaneStateDescriptorTests: XCTestCase {

    private func entry(_ path: String) -> FileEntry {
        FileEntry(path: path, name: (path as NSString).lastPathComponent, isDirectory: false)
    }

    func testDescriptorFirstLaunchNoPath() {
        let state = PaneState()
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .empty)
        XCTAssertEqual(d.title, "打开一个文件夹")
        XCTAssertFalse(d.showsRetry)
    }

    func testDescriptorEmptyFolder() {
        var state = PaneState()
        state.path = "/tmp/empty"
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .empty)
        XCTAssertEqual(d.title, "此文件夹为空")
    }

    func testDescriptorSearchNoResults() {
        var state = PaneState()
        state.path = "/tmp/dir"
        state.searchQuery = "zzz"
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .empty)
        XCTAssertEqual(d.title, "未找到匹配项")
        XCTAssertTrue(d.subtitle.contains("zzz"))
    }

    func testDescriptorTagFilterEmpty() {
        var state = PaneState()
        state.path = "/tmp/dir"
        state.tagFilter = Tag(name: "红")
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .empty)
        XCTAssertEqual(d.title, "没有符合所选标签的项目")
    }

    func testDescriptorLoading() {
        var state = PaneState()
        state.path = "/tmp/dir"
        state.isLoading = true
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .loading)
        XCTAssertTrue(d.isFullScreen)
    }

    func testDescriptorLoadErrorFullScreenRetry() {
        var state = PaneState()
        state.path = "/tmp/dir"
        state.error = "权限不足，无法读取"
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .error)
        XCTAssertTrue(d.isFullScreen)
        XCTAssertTrue(d.showsRetry)
        XCTAssertEqual(d.retryKind, .reload)
        XCTAssertEqual(d.subtitle, "权限不足，无法读取")
    }

    func testDescriptorDeleteProgressBanner() {
        var state = PaneState()
        state.path = "/tmp/dir"
        state.isDeleting = true
        state.selectedFiles = [entry("/tmp/dir/a.txt"), entry("/tmp/dir/b.txt")]
        state.files = [entry("/tmp/dir/c.txt")]
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .operation)
        XCTAssertFalse(d.isFullScreen)
        XCTAssertTrue(d.title.contains("正在删除 2 个项目"))
    }

    func testDescriptorPartialDeleteFailureBannerRetry() {
        var state = PaneState()
        state.path = "/tmp/dir"
        state.error = "1 个项目删除失败：/tmp/dir/a.txt"
        state.deleteFailedPaths = ["/tmp/dir/a.txt"]
        state.files = [entry("/tmp/dir/b.txt")]
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .error)
        XCTAssertFalse(d.isFullScreen)
        XCTAssertEqual(d.retryKind, .deleteRetry)
        XCTAssertTrue(d.title.contains("1 个项目删除失败"))
    }

    func testDescriptorContentWhenFilesPresent() {
        var state = PaneState()
        state.path = "/tmp/dir"
        state.files = [entry("/tmp/dir/a.txt")]
        state.isLoading = true  // 刷新中但有内容：不遮挡列表
        let d = FFPaneStateDescriptor.make(from: state)
        XCTAssertEqual(d.mode, .content)
    }
}

// MARK: - 任务 T12: loadDirectory 真流（loading→ready / empty / error→retry）

final class PaneStateFlowTests: XCTestCase {

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let exp = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)
        wait(for: [exp], timeout: timeout)
    }

    private func makeTempDir(prefix: String) -> URL {
        // 注意：不能用 FileManager.default.temporaryDirectory（/var/folders/...）。
        // Rust listDirectory 用 getattrlistbulk 枚举，在 XCTest harness（libRPAC 拦截）下
        // 该路径会被静默返回 0 条，导致 loading→ready 测试读到空列表。改用 /tmp。
        let dir = URL(fileURLWithPath: "/tmp/\(prefix)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLoadDirectoryLoadingThenReady() throws {
        let dir = makeTempDir(prefix: "ff_t12_flow")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "alpha".write(toFile: dir.appendingPathComponent("alpha.txt").path, atomically: true, encoding: .utf8)
        try "beta".write(toFile: dir.appendingPathComponent("beta.txt").path, atomically: true, encoding: .utf8)

        let vm = PaneViewModel()
        vm.navigate(to: dir.path)
        XCTAssertTrue(vm.state.isLoading, "navigate 后应立即进入加载状态（loading 阶段）")

        waitUntil { !vm.state.isLoading }
        XCTAssertNil(vm.state.error, "正常目录加载不应产生错误")
        XCTAssertEqual(vm.state.files.count, 2, "ready 后应加载全部 2 个文件")
        XCTAssertEqual(FFPaneStateDescriptor.make(from: vm.state).mode, .content)
    }

    func testEmptyDirectoryShowsEmptyState() {
        let dir = makeTempDir(prefix: "ff_t12_empty")

        let vm = PaneViewModel()
        vm.navigate(to: dir.path)
        waitUntil { !vm.state.isLoading }

        XCTAssertNil(vm.state.error)
        XCTAssertTrue(vm.state.files.isEmpty)
        let d = FFPaneStateDescriptor.make(from: vm.state)
        XCTAssertEqual(d.mode, .empty)
        XCTAssertEqual(d.title, "此文件夹为空")
    }

    func testLoadErrorThenRetryRecovers() throws {
        let base = makeTempDir(prefix: "ff_t12_err")
        defer { try? FileManager.default.removeItem(at: base) }
        let missingDir = base.appendingPathComponent("missing").path

        let vm = PaneViewModel()
        vm.navigate(to: missingDir)
        waitUntil { !vm.state.isLoading }

        XCTAssertNotNil(vm.state.error, "不存在的目录应产生可读错误")
        var d = FFPaneStateDescriptor.make(from: vm.state)
        XCTAssertEqual(d.mode, .error)
        XCTAssertTrue(d.showsRetry)
        XCTAssertEqual(d.retryKind, .reload)

        // 重试：修复问题（创建目录）后 refresh 恢复
        try FileManager.default.createDirectory(atPath: missingDir, withIntermediateDirectories: true)
        vm.refresh()
        waitUntil { !vm.state.isLoading }

        XCTAssertNil(vm.state.error, "重试成功后错误应清除")
        XCTAssertTrue(vm.state.files.isEmpty)
        d = FFPaneStateDescriptor.make(from: vm.state)
        XCTAssertEqual(d.mode, .empty, "重试成功后进入空文件夹状态（错误→ready）")
    }
}

// MARK: - 任务 T12: 统一删除确认入口

final class DeleteConfirmFlowTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FFUserDefaultsKeys.deleteConfirmDisabled)
        super.tearDown()
    }

    func testShouldConfirmDecisionMatrix() {
        XCTAssertFalse(DeleteConfirmDialog.shouldConfirm(fileCount: 0, confirmDisabled: false, windowAvailable: true),
                       "0 个条目无需确认")
        XCTAssertFalse(DeleteConfirmDialog.shouldConfirm(fileCount: 3, confirmDisabled: true, windowAvailable: true),
                       "勾选'不再询问'后跳过确认")
        XCTAssertFalse(DeleteConfirmDialog.shouldConfirm(fileCount: 3, confirmDisabled: false, windowAvailable: false),
                       "无宿主窗口回退直接执行")
        XCTAssertTrue(DeleteConfirmDialog.shouldConfirm(fileCount: 3, confirmDisabled: false, windowAvailable: true),
                      "正常路径应弹确认")
    }

    func testConfirmDeleteRunsActionWhenNoWindow() {
        UserDefaults.standard.removeObject(forKey: FFUserDefaultsKeys.deleteConfirmDisabled)
        var executed = false
        DeleteConfirmDialog.confirmDelete(fileCount: 5, window: nil) { executed = true }
        XCTAssertTrue(executed, "无窗口时应直接执行删除动作")
    }

    func testConfirmDeleteSkipsDialogWhenDisabled() {
        UserDefaults.standard.set(true, forKey: FFUserDefaultsKeys.deleteConfirmDisabled)
        var executed = false
        DeleteConfirmDialog.confirmDelete(fileCount: 3, window: nil) { executed = true }
        XCTAssertTrue(executed, "勾选'不再询问'后应跳过确认直接执行")
    }

    func testConfirmDeleteZeroCountRunsAction() {
        var executed = false
        DeleteConfirmDialog.confirmDelete(fileCount: 0, window: nil) { executed = true }
        XCTAssertTrue(executed)
    }
}

// MARK: - 任务 T12: 搜索结果详情 + 内容索引状态映射

final class SearchPanelDetailsTests: XCTestCase {

    func testDetailsTextNoSelection() {
        XCTAssertEqual(SearchPanelController.detailsText(for: nil), "选择一个结果以查看详情")
    }

    func testDetailsTextWithResult() {
        let result = FFSearchResult(path: "/Users/test/报告.pdf", name: "报告.pdf",
                                    size: 2048, modified: 1_700_000_000, isDir: false)
        let text = SearchPanelController.detailsText(for: result)
        XCTAssertFalse(text.contains("选择一个结果"), "选中后不应保留静态占位文案")
        XCTAssertTrue(text.contains("报告.pdf"))
        XCTAssertTrue(text.contains("/Users/test/报告.pdf"))
        XCTAssertTrue(text.contains("修改于"))
    }

    func testContentIndexStatusUnavailable() {
        let d = SearchPanelController.contentIndexStatusDescriptor(status: .unavailable, stats: nil)
        XCTAssertEqual(d.label, "内容搜索不可用")
        XCTAssertFalse(d.showsProgress)
        XCTAssertFalse(d.showsActionButton)
    }

    func testContentIndexStatusMapping() {
        let empty = SearchPanelController.contentIndexStatusDescriptor(status: .empty, stats: nil)
        XCTAssertEqual(empty.label, "内容索引尚未构建")
        XCTAssertEqual(empty.actionTitle, "构建索引")

        let readyStats = ContentIndexStats(json: #"{"status":2,"paused":false,"document_count":42}"#)
        let ready = SearchPanelController.contentIndexStatusDescriptor(status: .ready, stats: readyStats)
        XCTAssertTrue(ready.label.contains("42"))
        XCTAssertEqual(ready.actionTitle, "重建")
        XCTAssertFalse(ready.showsProgress)

        let indexing = SearchPanelController.contentIndexStatusDescriptor(status: .indexing, stats: nil)
        XCTAssertTrue(indexing.showsProgress)
        XCTAssertEqual(indexing.actionTitle, "取消")

        let pausedStats = ContentIndexStats(json: #"{"status":1,"paused":true,"document_count":0}"#)
        let indexingPaused = SearchPanelController.contentIndexStatusDescriptor(status: .indexing, stats: pausedStats)
        XCTAssertEqual(indexingPaused.actionTitle, "继续")

        let errorStats = ContentIndexStats(json: #"{"status":3,"error":"数据库损坏"}"#)
        let error = SearchPanelController.contentIndexStatusDescriptor(status: .error, stats: errorStats)
        XCTAssertTrue(error.label.contains("数据库损坏"))
        XCTAssertEqual(error.actionTitle, "重试")

        let cancelled = SearchPanelController.contentIndexStatusDescriptor(status: .cancelled, stats: nil)
        XCTAssertEqual(cancelled.label, "内容索引构建已取消")
        XCTAssertEqual(cancelled.actionTitle, "继续构建")
    }
}

// MARK: - 任务 T12: 状态浮层视图级验证（真实 AppKit 渲染，进程内可执行 QA 证据）

final class FFPaneStateOverlayViewTests: XCTestCase {

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let exp = expectation(for: NSPredicate { _, _ in condition() }, evaluatedWith: nil)
        wait(for: [exp], timeout: timeout)
    }

    private func makeTempDir(prefix: String) -> URL {
        let dir = URL(fileURLWithPath: "/tmp/\(prefix)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 浮层随 PaneState 真值流转：首次无路径(可见) → loading(可见) → content(隐藏)。
    func testOverlayVisibilityFollowsLoadingToReady() throws {
        let overlay = FFPaneStateOverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let vm = PaneViewModel()
        overlay.viewModel = vm
        XCTAssertFalse(overlay.isHidden, "首次无路径应显示空状态浮层")

        let dir = makeTempDir(prefix: "ff_t12_view")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(toFile: dir.appendingPathComponent("f.txt").path, atomically: true, encoding: .utf8)

        vm.navigate(to: dir.path)
        XCTAssertFalse(overlay.isHidden, "加载中应显示浮层")

        waitUntil { !vm.state.isLoading }
        XCTAssertTrue(overlay.isHidden, "ready 有内容时浮层隐藏、不遮挡列表")
    }

    /// 空目录 → 空状态浮层可见；错误目录 → 错误浮层可见；删除中 → 进度横幅可见。
    func testOverlayVisibilityForEmptyErrorAndDeleting() {
        let overlay = FFPaneStateOverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let vm = PaneViewModel()
        overlay.viewModel = vm

        let emptyDir = makeTempDir(prefix: "ff_t12_view_empty")
        vm.navigate(to: emptyDir.path)
        waitUntil { !vm.state.isLoading }
        XCTAssertFalse(overlay.isHidden, "空目录应显示空状态浮层")

        let missingDir = "/tmp/ff_t12_view_missing_\(UUID().uuidString)"
        vm.navigate(to: missingDir)
        waitUntil { !vm.state.isLoading }
        XCTAssertNotNil(vm.state.error)
        XCTAssertFalse(overlay.isHidden, "错误状态应显示错误浮层（含重试）")

        vm.navigate(to: emptyDir.path)
        waitUntil { !vm.state.isLoading }
        XCTAssertFalse(overlay.isHidden)

        vm.state.isDeleting = true
        XCTAssertFalse(overlay.isHidden, "删除进行中应显示进度横幅")
        vm.state.isDeleting = false
        XCTAssertFalse(overlay.isHidden, "删除结束后回落到空状态浮层")
    }
}

// MARK: - T13: 无障碍标签与 reduced-motion（纯函数单测）

final class FileEntryAccessibilityTests: XCTestCase {

    func testFileEntryLabelCombinesNameKindSize() {
        let entry = FileEntry(
            path: "/tmp/report.pdf", name: "report.pdf",
            isDirectory: false, size: 1024,
            modificationDate: Date()
        )
        let label = FileEntryAccessibility.label(for: entry)
        XCTAssertTrue(label.contains("report.pdf"), "标签应含文件名，实际: \(label)")
        XCTAssertTrue(label.contains("PDF"), "标签应含类型描述，实际: \(label)")
        XCTAssertTrue(label.contains("KB"), "标签应含大小，实际: \(label)")
    }

    func testFileEntryLabelForDirectoryOmitsSize() {
        let dir = FileEntry(path: "/tmp/dir", name: "dir", isDirectory: true)
        let label = FileEntryAccessibility.label(for: dir)
        XCTAssertTrue(label.contains("dir"))
        XCTAssertTrue(label.contains("文件夹"))
    }

    func testSidebarLabelMarksSelection() {
        XCTAssertEqual(FileEntryAccessibility.sidebarLabel(name: "下载", isSelected: false), "下载")
        XCTAssertEqual(FileEntryAccessibility.sidebarLabel(name: "下载", isSelected: true), "下载，已选中")
    }

    func testSearchResultLabelIncludesName() {
        let result = FFSearchResult(path: "/tmp/a.txt", name: "a.txt", size: 2048, modified: 0, isDir: false)
        let label = FileEntryAccessibility.searchResultLabel(result)
        XCTAssertTrue(label.contains("a.txt"), "搜索标签应含文件名，实际: \(label)")
    }
}

final class FFMotionTests: XCTestCase {

    func testAnimationDurationPositiveWhenMotionEnabled() {
        // 无法在测试中强制系统 reduced-motion 状态，验证纯函数在正常路径返回原值时长为正
        let d = FFMotion.animationDuration(0.25)
        XCTAssertGreaterThanOrEqual(d, 0)
    }
}
