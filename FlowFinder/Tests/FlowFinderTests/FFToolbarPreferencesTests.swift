import XCTest
@testable import FlowFinder

final class FFToolbarPreferencesTests: XCTestCase {
    func testDefaultIsEveryItem() {
        XCTAssertEqual(FFToolbarRow2Preferences.visibleItems(from: nil),
                       Set(FFToolbarRow2Item.allCases))
    }

    func testUnknownAndDuplicatesAreIgnored() {
        let items = FFToolbarRow2Preferences.visibleItems(from: "search,sort,unknown,search")
        XCTAssertEqual(items, [.search, .sort])
    }

    func testRoundTripAndToggle() {
        var items = FFToolbarRow2Preferences.defaultItems
        items = FFToolbarRow2Preferences.toggled(.search, in: items)
        XCTAssertFalse(items.contains(.search))
        XCTAssertEqual(FFToolbarRow2Preferences.visibleItems(
            from: FFToolbarRow2Preferences.encode(items)), items)
    }

    func testEmptyStringMeansAllHidden() {
        XCTAssertTrue(FFToolbarRow2Preferences.visibleItems(from: "").isEmpty)
    }
}

// MARK: - R19-2 D-07/D-08：新建文件夹退出工具栏，第二行配置并入「显示设置」

final class FFToolbarRow2MergeTests: XCTestCase {
    private let storageKey = FFToolbarRow2Preferences.storageKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    /// 第二行可配置项只剩四类（新建文件夹改由右键菜单 / ⌘⇧N 负责）
    func testRow2ItemSetDropsNewFolder() {
        XCTAssertEqual(FFToolbarRow2Item.allCases, [.search, .sort, .group, .viewMode])
    }

    /// 老配置里残留的 newFolder 必须被忽略，不能复活按钮
    func testLegacyNewFolderEntryIsIgnored() {
        XCTAssertEqual(FFToolbarRow2Preferences.visibleItems(from: "search,newFolder,sort"),
                       [.search, .sort])
    }

    /// 眼睛按钮是第二行唯一的设置入口，菜单内并入第二行配置与显示列
    func testDisplaySettingsMenuMergesRow2Config() {
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 480, height: 76))
        let menu = toolbar.makeDisplaySettingsMenu()
        let titles = menu.items.map(\.title)

        XCTAssertTrue(titles.contains { $0.hasSuffix("隐藏文件") }, "应保留显示隐藏文件开关")
        XCTAssertTrue(titles.contains("显示列"), "应保留显示列子菜单")

        let row2Menu = menu.items.first(where: { $0.title == "第二行显示" })?.submenu
        let row2Titles = row2Menu?.items.compactMap { $0.isSeparatorItem ? nil : $0.title }
        XCTAssertEqual(row2Titles, ["搜索", "排序", "分组", "列表 / 图标"])

        XCTAssertFalse(titles.contains("新建文件夹"), "新建文件夹不应回到工具栏菜单")
    }

    /// 齿轮按钮与新建文件夹按钮都从第二行消失，只留一个显示设置按钮
    func testRow2KeepsSingleDisplaySettingsButton() {
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 480, height: 76))
        let buttons = toolbar.row2Buttons().compactMap { $0.accessibilityLabel() }
        XCTAssertEqual(toolbar.displaySettingsButton.accessibilityLabel(), "显示设置")
        XCTAssertFalse(buttons.contains("第二行显示"), "齿轮入口应并入显示设置")
        XCTAssertFalse(buttons.contains("新建文件夹"))
    }

    /// 显示设置菜单使用固定名词 + 勾选态，不再用「隐藏…」动作文案配勾选
    func testDisplaySettingsMenuUsesFixedLabels() {
        let tagKey = FFUserDefaultsKeys.showFileTags
        let oldTag = UserDefaults.standard.object(forKey: tagKey)
        UserDefaults.standard.set(true, forKey: tagKey)
        defer {
            if let oldTag { UserDefaults.standard.set(oldTag, forKey: tagKey) }
            else { UserDefaults.standard.removeObject(forKey: tagKey) }
        }

        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 480, height: 76))
        let menu = toolbar.makeDisplaySettingsMenu()
        let tagItem = menu.items.first { $0.title == "显示文件标签" }
        XCTAssertNotNil(tagItem, "菜单应为固定名词「显示文件标签」")
        XCTAssertEqual(tagItem?.state, .on)
        XCTAssertFalse(menu.items.contains { $0.title == "隐藏文件标签" })
    }

    /// 第二行隐藏的控件不能继续留在 Tab 环里
    func testHiddenRow2ControlsLeaveKeyViewLoop() {
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 480, height: 76))
        defer { toolbar.setRow2Item(.search, visible: true) }

        toolbar.setRow2Item(.search, visible: false)
        XCTAssertFalse(toolbar.keyViewControls().contains { $0 === toolbar.searchFieldForTesting })
        XCTAssertFalse(toolbar.keyViewControls().contains { $0 === toolbar.scopePopupForTesting })
    }
}
