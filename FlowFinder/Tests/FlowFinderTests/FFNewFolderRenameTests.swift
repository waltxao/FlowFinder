import Foundation
import XCTest
@testable import FlowFinder

/// 第四轮审计 R4-18：⇧⌘N「新建文件夹」
/// 症状：按下快捷键后只创建一个「未命名文件夹」就结束，焦点没回列表、新项没选中，
/// 用户还得手动再按一次 F2 才能改名；同名目录第二次新建直接失败。
final class FFNewFolderRenameTests: XCTestCase {

    private func makeTempDirectory() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("ff-newfolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 主线程轮询等待（回调同样派回主线程，不能用 wait(for:) 阻塞）
    private func waitUntil(_ deadline: TimeInterval = 10, _ condition: () -> Bool) {
        let limit = Date().addingTimeInterval(deadline)
        while !condition() && Date() < limit {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    // MARK: - 重名时自动加序号

    func testUntitledFolderNameAvoidsCollisions() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        XCTAssertEqual(PaneViewModel.untitledFolderName(in: dir), "未命名文件夹")

        try FileManager.default.createDirectory(
            atPath: (dir as NSString).appendingPathComponent("未命名文件夹"),
            withIntermediateDirectories: true)
        XCTAssertEqual(PaneViewModel.untitledFolderName(in: dir), "未命名文件夹 2",
                       "目录里已有同名文件夹时必须让路，否则第二次新建直接报错")
    }

    // MARK: - 创建后选中新项，并给出「可以开始重命名」的时机

    @MainActor
    func testNewFolderEndsUpSelectedAndReadyForRename() throws {
        // 临时目录在 /var/folders/…，而 rust-core 的 is_system_protected_path 把 /var、
        // /private 整片算作系统保护区，列表默认筛选系统文件会把新文件夹直接滤掉。
        let key = FFUserDefaultsKeys.showSystemFiles
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let viewModel = PaneViewModel(path: dir)
        waitUntil { !viewModel.isLoading }

        var readyPath: String?
        viewModel.createDirectoryThenRenaming { path in
            readyPath = path
        }
        waitUntil { readyPath != nil }

        let expected = (dir as NSString).appendingPathComponent("未命名文件夹")
        XCTAssertEqual(readyPath, expected, "回调要带回新建文件夹的路径，视图层据此进入内联重命名")
        XCTAssertEqual(viewModel.state.selectedFiles.map(\.path), [expected],
                       "新文件夹必须处于选中态，否则用户还得自己点一下（R4-18）")
    }

    // MARK: - C3 修复：内联重命名期间 reloadData 被 guard 拦截

    /// C3 真机验证通过（2026-10-23）：⇧⌘N 后内联重命名文本框不再被 tagCacheWarmed 通知
    /// 触发的 reloadData() 销毁。根因是 .ffTagCacheWarmed 通知在内联重命名开始后 33-43ms
    /// 触发，调用 reloadData() 重建所有 cell，导致编辑中的 textField 丢失 firstResponder。
    /// 修复：在 FileListView 的 tagCacheWarmed/listColumnsDidChange/Combine sink 三处加
    /// `guard !self.actionsController.isRenaming` 拦截 reloadData。
    ///
    /// 此测试验证 isRenaming 属性的可访问性（C3 修复将其从 private 改为 internal），
    /// 确保视图层可以读取该状态以决定是否跳过 reloadData。
    func testIsRenamingPropertyIsAccessible() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let viewModel = PaneViewModel(path: dir)
        let controller = FFPaneActionsController(host: MockPaneViewHost(viewModel: viewModel))

        // isRenaming 初始为 false
        XCTAssertFalse(controller.isRenaming, "isRenaming 初始状态必须为 false")

        // 模拟重命名状态切换（直接设置，因为 beginInlineRename 需要完整的 AppKit 环境）
        controller.isRenaming = true
        XCTAssertTrue(controller.isRenaming, "isRenaming 必须可写，视图层据此跳过 reloadData")

        controller.isRenaming = false
        XCTAssertFalse(controller.isRenaming, "重命名结束后 isRenaming 必须恢复为 false")
    }
}

// MARK: - Mock Host for Testing

private final class MockPaneViewHost: FFPaneViewHost {
    var viewModel: PaneViewModel?
    var hostWindow: NSWindow? = nil
    var panelSide: PaneSide? = nil
    var doubleClickHandler: ((FileEntry) -> Void)? = nil
    var selectedEntries: [FileEntry] = []
    var clickedEntry: FileEntry? = nil
    var focusRestoreTarget: NSResponder? = nil
    var tagsSubmenu: NSMenu = NSMenu()

    init(viewModel: PaneViewModel?) {
        self.viewModel = viewModel
    }

    func renameTextFieldForSelection() -> NSTextField? { return nil }
    func selectClickedItemForRename() {}
    func revealSelection() {}
    func reloadPaneData() {}
}
