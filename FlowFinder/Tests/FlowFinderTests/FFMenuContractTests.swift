import AppKit
import XCTest
@testable import FlowFinder

/// 第 3 批：菜单契约与命名统一
/// （docs/AUDIT-2026-10-23-UIUX-R4.md 的 R4-06…R4-11、R4-20、R4-28、R4-29）
final class FFMenuContractTests: XCTestCase {

    /// 本批新增的入口。用字符串 selector 引用：测试要能在实现落地**之前**编译通过并失败，
    /// 而不是编译不过。实现改名时这里会以断言失败的形式暴露，而不是静默漏检。
    private static let toggleSidebar = NSSelectorFromString("ffToggleSidebar:")
    private static let toggleDetailsBar = NSSelectorFromString("menuToggleDetailsBar:")

    // MARK: - helpers

    override func setUp() {
        super.setUp()
        // 侧栏/工具页的名称取自注册表；单测宿主不一定已开过窗口，先幂等补齐内置工具
        FFToolRegistry.registerBuiltInsIfNeeded()
    }

    private func submenu(_ title: String) throws -> NSMenu {
        try XCTUnwrap(MainMenu.submenu(of: MainMenu.buildMainMenu(), titled: title),
                      "主菜单缺少「\(title)」")
    }

    private func item(in menu: NSMenu, _ action: Selector) throws -> NSMenuItem {
        try XCTUnwrap(menu.items.first { $0.action == action },
                      "「\(menu.title)」菜单里找不到 action \(action)")
    }

    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + allItems($0.submenu ?? NSMenu()) }
    }

    private func entry(_ name: String, isDir: Bool = false) -> FileEntry {
        FileEntry(path: "/tmp/\(name)", name: name, isDirectory: isDir, size: 1_024)
    }

    private func makeController() -> MainWindowController {
        MainWindowController(startsWithSinglePane: false,
                             showImmediately: false,
                             runsSelfTests: false)
    }

    private func contextMenu() -> NSMenu {
        FFPaneMenuBuilder.buildMenu(for: NSObject(), isLeft: true, tagsSubmenu: NSMenu())
    }

    // MARK: - R4-06 命名漂移

    /// 侧栏/工具页取自 FFToolRegistry，其余入口必须同名——否则用户找不到同一个功能。
    func testToolNamesAreIdenticalAcrossEntries() throws {
        let tools = try submenu("工具")
        let registry = FFToolRegistry.shared.registeredTools

        let scan = try item(in: tools, #selector(MainWindowController.menuDuplicateScan(_:)))
        XCTAssertEqual(scan.title, FFNaming.duplicateScanTitle,
                       "菜单里的查重必须与侧栏同名")
        XCTAssertTrue(registry.contains { $0.title == FFNaming.duplicateScanBase })

        let task = try item(in: tools, #selector(MainWindowController.menuTaskPanel(_:)))
        XCTAssertEqual(task.title, FFNaming.taskCenterBase,
                       "菜单写「任务面板」而侧栏写「任务中心」——同一个东西两个名字")
        XCTAssertTrue(registry.contains { $0.title == FFNaming.taskCenterBase })
    }

    func testToolWindowTitlesMatchTheirEntryNames() throws {
        XCTAssertEqual(DuplicateScanWindowController.shared.window?.title,
                       FFNaming.duplicateScanBase, "窗口标题与侧栏/菜单不一致")
        XCTAssertEqual(TaskPanelWindowController.shared.window?.title,
                       FFNaming.taskCenterBase, "窗口标题与侧栏/菜单不一致")
        XCTAssertEqual(ConnectServerDialog { _ in }.title,
                       FFNaming.connectServerBase, "对话框标题写「连接到服务器」，菜单写「连接服务器…」")
    }

    func testContextMenuUsesMainMenuVocabulary() throws {
        let menu = contextMenu()
        let titles = Set(menu.items.map(\.title))
        XCTAssertTrue(titles.contains(FFNaming.moveToTrashBase),
                      "右键写「移到废纸篓」、主菜单写「移动到废纸篓」：\(titles)")
        XCTAssertTrue(titles.contains(FFNaming.duplicateScanBase),
                      "右键写「查重扫描」：\(titles)")
        XCTAssertTrue(titles.contains(FFNaming.batchOrganizeBase),
                      "右键写「整理当前目录…」而侧栏写「批量整理」：\(titles)")
    }

    // MARK: - R4-07 侧栏菜单项恒禁用

    /// `NSWindow` 自带 `toggleSidebar:`，它在响应链里排在窗口控制器之前，
    /// 且没有分栏控制器时校验恒为 false → 菜单项永远灰着。必须换掉这个保留名。
    func testSidebarMenuItemAvoidsAppKitReservedSelector() throws {
        let view = try submenu("显示")
        XCTAssertTrue(NSWindow.instancesRespond(to: NSSelectorFromString("toggleSidebar:")),
                      "前提：AppKit 的 NSWindow 保留了 toggleSidebar:")

        let item = try item(in: view, Self.toggleSidebar)
        XCTAssertFalse(NSWindow.instancesRespond(to: item.action!),
                       "菜单项仍会先命中 NSWindow 的同名实现，校验被 AppKit 抢走")
        XCTAssertTrue(MainWindowController.instancesRespond(to: item.action!))
    }

    // MARK: - R4-08 窗口菜单没有窗口清单

    func testWindowMenuIsRegisteredWithApp() {
        MainMenu.setupMainMenu()
        defer { NSApp.windowsMenu = nil }
        XCTAssertNotNil(NSApp.windowsMenu,
                        "不注册 windowsMenu，AppKit 就不会往窗口菜单里塞窗口清单，多窗口无法切换")
        XCTAssertEqual(NSApp.windowsMenu?.title, "窗口")
    }

    // MARK: - R4-09 省略号混排

    func testMainMenuUsesTypographicEllipsis() {
        for item in allItems(MainMenu.buildMainMenu()) where !item.isSeparatorItem {
            XCTAssertFalse(item.title.hasSuffix("..."),
                           "菜单项「\(item.title)」用了 ASCII 省略号，应统一为「…」")
        }
    }

    func testPaneContextMenuUsesTypographicEllipsis() {
        for item in allItems(contextMenu()) where !item.isSeparatorItem {
            XCTAssertFalse(item.title.hasSuffix("..."),
                           "右键菜单项「\(item.title)」用了 ASCII 省略号")
        }
    }

    // MARK: - R4-10 撤销/重做混进文件右键菜单

    func testPaneContextMenuOmitsUndoRedo() {
        let undo = NSSelectorFromString("undoFromMenu:")
        let redo = NSSelectorFromString("redoFromMenu:")
        let actions = Set(contextMenu().items.compactMap { $0.action })
        XCTAssertFalse(actions.contains(undo), "撤销属于 编辑 菜单，不该出现在文件右键菜单首位")
        XCTAssertFalse(actions.contains(redo), "重做属于 编辑 菜单，不该出现在文件右键菜单")
    }

    // MARK: - R4-11 批量重命名静默禁用

    func testBatchRenameDisabledItemStatesItsThreshold() throws {
        let controller = makeController()
        defer { controller.close() }
        controller.focus.activate(.left)
        controller.leftPaneViewModel.state.selectedFiles = [entry("one.txt")]

        let item = NSMenuItem(title: FFNaming.batchRenameTitle,
                              action: #selector(MainWindowController.menuBatchRename(_:)),
                              keyEquivalent: "")
        item.target = controller
        XCTAssertFalse(controller.validateMenuItem(item), "只选 1 项时不该可用")
        XCTAssertEqual(item.toolTip, FFNaming.batchRenameRequires,
                       "禁用却不解释，用户不知道阈值是 2")

        controller.leftPaneViewModel.state.selectedFiles = [entry("a.txt"), entry("b.txt")]
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertNil(item.toolTip, "可用状态不该留着禁用解释")
    }

    // MARK: - R4-20 编辑菜单校验

    /// AppKit 只认 Objective-C 的 `validateMenuItem:`。Swift 方法若没标 `@objc`
    /// 也没声明 `NSMenuItemValidation` 一致性，直接调用它的单测照样通过，
    /// 真实菜单却永远不校验——剪切/粘贴/批量重命名全按静态 enabled 显示。
    func testValidateMenuItemIsVisibleToAppKit() {
        XCTAssertTrue(MainWindowController.instancesRespond(to: NSSelectorFromString("validateMenuItem:")),
                      "校验方法没暴露给 Objective-C，AppKit 永远不会调用它")
    }

    func testSelectionActionsAreDisabledWithoutSelection() throws {
        let controller = makeController()
        defer { controller.close() }
        controller.focus.activate(.left)
        controller.leftPaneViewModel.state.selectedFiles = []

        for action in [#selector(NSText.cut(_:)), #selector(NSText.copy(_:)),
                       #selector(MainWindowController.menuRename(_:)),
                       #selector(MainWindowController.menuBatchRename(_:)),
                       #selector(MainWindowController.menuEditTags(_:)),
                       #selector(MainWindowController.menuDuplicateSelected(_:)),
                       #selector(MainWindowController.menuCopyToOther(_:)),
                       #selector(MainWindowController.menuOpenInOther(_:))] as [Selector] {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.target = controller
            XCTAssertFalse(controller.validateMenuItem(item), "\(action) 无选中时不该可用")
        }
    }

    /// 「在对侧面板打开」只对目录有效——同一条 selector 原先在 switch 里出现两次，
    /// 第二个分支永远不可达，目录判断形同虚设（R4-20 复核时发现）。
    func testOpenInOtherRequiresDirectorySelection() throws {
        let controller = makeController()
        defer { controller.close() }
        controller.focus.activate(.left)
        let item = NSMenuItem(title: "",
                              action: #selector(MainWindowController.menuOpenInOther(_:)),
                              keyEquivalent: "")
        item.target = controller

        controller.leftPaneViewModel.state.selectedFiles = [entry("plain.txt")]
        XCTAssertFalse(controller.validateMenuItem(item), "选中普通文件时不该可点")

        controller.leftPaneViewModel.state.selectedFiles = [entry("folder", isDir: true)]
        XCTAssertTrue(controller.validateMenuItem(item), "选中目录时应可点")
    }

    /// 审计的「剪切/复制无选中仍可用」经复核是取证时活动面板确有选中；
    /// 真正的缺口是 `粘贴`：validateMenuItem 落 default 恒为 true。
    func testPasteFollowsPasteboardContents() throws {
        let controller = makeController()
        defer { controller.close() }
        let paste = NSSelectorFromString("paste:")
        let item = NSMenuItem(title: "粘贴", action: paste, keyEquivalent: "v")
        item.target = controller

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }

        pasteboard.clearContents()
        XCTAssertFalse(controller.validateMenuItem(item), "空剪贴板时粘贴不该可用")

        pasteboard.clearContents()
        pasteboard.setString("可粘贴的内容", forType: .string)
        XCTAssertTrue(controller.validateMenuItem(item))
    }

    // MARK: - R4-28 显示隐藏文件无键盘等价键

    func testShowHiddenFilesUsesFinderKeyboardEquivalent() throws {
        let view = try submenu("显示")
        let hidden = try item(in: view, #selector(MainWindowController.menuToggleHiddenFiles(_:)))
        XCTAssertEqual(hidden.keyEquivalent, ".", "访达惯例是 ⌘⇧.")
        XCTAssertEqual(hidden.keyEquivalentModifierMask, [.command, .shift])
    }

    // MARK: - R4-29 详情栏显隐没有菜单项

    func testViewMenuTogglesDetailsBar() throws {
        let view = try submenu("显示")
        let details = try item(in: view, Self.toggleDetailsBar)
        XCTAssertEqual(details.title, FFNaming.detailsBarTitle)
        // 键位沿用原「显示简介」的 ⌘I（D-07 定的就是区内详情栏），只把标签和归属菜单改对
        XCTAssertEqual(details.keyEquivalent, "i")
        XCTAssertEqual(details.keyEquivalentModifierMask, [.command])
    }

    func testMenuToggleDetailsBarExpandsThenCollapses() throws {
        let controller = makeController()
        defer { controller.close() }
        guard controller.responds(to: Self.toggleDetailsBar) else {
            return XCTFail("详情栏开关 \(NSStringFromSelector(Self.toggleDetailsBar)) 尚未实现")
        }
        controller.focus.activate(.left)
        controller.leftPaneViewModel.state.selectedFiles = [entry("one.txt")]
        let bar = try XCTUnwrap(controller.detailsBar(for: .left))

        controller.perform(Self.toggleDetailsBar, with: nil)
        XCTAssertTrue(bar.isExpandedForTesting, "收起态下应展开")
        controller.perform(Self.toggleDetailsBar, with: nil)
        XCTAssertFalse(bar.isExpandedForTesting, "展开态下应收起")
    }

    /// 详情栏开关挪到 显示 菜单后，文件 菜单的「显示简介」标签与实际行为不再互相打架。
    func testDetailsBarToggleLivesInViewMenuNotFileMenu() throws {
        let view = try submenu("显示")
        let file = try submenu("文件")
        XCTAssertTrue(view.items.contains { $0.action == Self.toggleDetailsBar })
        XCTAssertFalse(file.items.contains { $0.action == Self.toggleDetailsBar },
                       "「显示简介」⌘I 原先其实只是展开详情栏，标签与行为不一致")
    }
}
