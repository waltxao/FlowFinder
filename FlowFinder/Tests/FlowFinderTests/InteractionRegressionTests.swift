import AppKit
import XCTest
@testable import FlowFinder

// MARK: - 占位标签

final class PaneTabsStorePlaceholderTests: XCTestCase {

    private func session(_ path: String, placeholder: Bool = false) -> PaneTabSession {
        var session = PaneTabSession(state: PaneState(path: path))
        session.isPlaceholder = placeholder
        return session
    }

    func testInsertReplacesLonePlaceholder() {
        let store = PaneTabsStore(initial: session("/tmp/placeholder", placeholder: true))

        store.insert(session("/tmp/real"), at: 0)

        XCTAssertEqual(store.count, 1, "占位标签应被真实标签替换，而不是并列")
        XCTAssertEqual(store.active.state.path, "/tmp/real")
        XCTAssertFalse(store.active.isPlaceholder)
    }

    func testAddReplacesLonePlaceholder() {
        let store = PaneTabsStore(initial: session("/tmp/placeholder", placeholder: true))

        store.add(session("/tmp/new"))

        XCTAssertEqual(store.count, 1, "空面板新建标签时应填回占位，而不是留下占位 + 新标签")
        XCTAssertEqual(store.active.state.path, "/tmp/new")
        XCTAssertFalse(store.active.isPlaceholder)
    }

    func testInsertKeepsSiblingRealTabs() {
        let store = PaneTabsStore(initial: session("/tmp/a"))

        store.insert(session("/tmp/b"), at: 1)

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.tabs.map { $0.state.path }, ["/tmp/a", "/tmp/b"])
    }

    func testDropBackAfterTakeOutLeavesSingleTab() {
        let store = PaneTabsStore(initial: session("/tmp/a"))
        let taken = store.tabs[0]

        // 模拟 takeTabOut：唯一标签先被摘走，面板退化成占位
        store.resetToPlaceholder(session("/tmp/placeholder", placeholder: true))
        // 模拟拖回同一个标签条：落点插入
        store.insert(taken, at: 0)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.tabs.first?.id, taken.id)
        XCTAssertFalse(store.tabs.contains { $0.isPlaceholder })
    }
}

// MARK: - 决策表

final class FFInteractionPolicyTests: XCTestCase {

    func testTabInsideBufferReorders() {
        let state = FFInteractionState(pointerInsideTabBuffer: true)
        XCTAssertEqual(FFInteractionPolicy.intent(region: .tab, state: state), .reorderTab)
    }

    func testTabOutsideBufferDragsPane() {
        let state = FFInteractionState(pointerInsideTabBuffer: false)
        XCTAssertEqual(FFInteractionPolicy.intent(region: .tab, state: state), .dragPane)
    }

    func testTitleAndWindowDragWindow() {
        let state = FFInteractionState()
        XCTAssertEqual(FFInteractionPolicy.intent(region: .title, state: state), .dragWindow)
        XCTAssertEqual(FFInteractionPolicy.intent(region: .window, state: state), .dragWindow)
    }

    func testPanelPressesWithoutDragging() {
        XCTAssertEqual(FFInteractionPolicy.intent(region: .panel, state: FFInteractionState()),
                       .pressFeedback)
    }

    func testResizeHandleWinsOverEveryRegion() {
        let state = FFInteractionState(onResizeHandle: true)
        for region in FFRegion.allCases {
            XCTAssertEqual(FFInteractionPolicy.intent(region: region, state: state),
                           .resizeDivider,
                           "调宽把手必须优先于 \(region)")
        }
    }
}

// MARK: - 区域解析：控件与手势

private final class FFRegionContainerView: NSView, FFRegionAware {
    let ffRegion: FFRegion

    init(region: FFRegion) {
        self.ffRegion = region
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class FFGestureTarget: NSObject {
    @objc func click(_ sender: NSClickGestureRecognizer) {}
}

final class FFAreaResolverControlTests: XCTestCase {

    func testButtonInsideWindowRegionIsHandledByControl() {
        let container = FFRegionContainerView(region: .window)
        let button = NSButton(title: "按钮", target: nil, action: nil)
        container.addSubview(button)

        XCTAssertEqual(FFAreaResolver.intent(for: button, state: FFInteractionState()),
                       .handledByControl,
                       "侧栏按钮不能被翻译成拖窗口，否则 mouseUp 会被吞掉")
    }

    func testButtonInsideTitleRegionIsHandledByControl() {
        let container = FFRegionContainerView(region: .title)
        let button = NSButton(title: "按钮", target: nil, action: nil)
        container.addSubview(button)

        XCTAssertEqual(FFAreaResolver.intent(for: button, state: FFInteractionState()),
                       .handledByControl,
                       "标签条上的 + 按钮不能被翻译成拖窗口")
    }

    func testButtonInsidePanelRegionKeepsPanelRegion() {
        let container = FFRegionContainerView(region: .panel)
        let button = NSButton(title: "按钮", target: nil, action: nil)
        container.addSubview(button)

        XCTAssertEqual(FFAreaResolver.region(of: button), .panel,
                       "面板内控件不能丢区域，否则拖标签落到文件列表时找不到操作区")
    }

    func testClickGestureViewInsideWindowRegionIsHandledByControl() {
        let container = FFRegionContainerView(region: .window)
        let view = NSView()
        let target = FFGestureTarget()
        view.addGestureRecognizer(NSClickGestureRecognizer(
            target: target,
            action: #selector(FFGestureTarget.click(_:))
        ))
        container.addSubview(view)

        XCTAssertNil(FFAreaResolver.region(of: view),
                     "带点击手势的自绘控件不能被祖先的 .window 区域接管")
    }

    func testPlainViewInsideWindowRegionStillDragsWindow() {
        let container = FFRegionContainerView(region: .window)
        let view = NSView()
        container.addSubview(view)

        XCTAssertEqual(FFAreaResolver.intent(for: view, state: FFInteractionState()),
                       .dragWindow)
    }

    func testPillButtonDeclaresPanelRegion() {
        let button = FFPillButton(title: "发现功能", icon: .compass)
        XCTAssertEqual(FFAreaResolver.region(of: button), .panel,
                       "自绘药丸按钮必须自己声明区域，不能落进侧栏的拖窗口区")
    }
}

// MARK: - 标签重排的插入位置

final class FFTabReorderTests: XCTestCase {

    private let bounds = NSRect(x: 0, y: 0, width: 300, height: 28)
    private let midXs: [CGFloat] = [20, 80, 140]

    func testPointInsideStripUsesMidpointRule() {
        XCTAssertEqual(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: 10, y: 14),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ), 0)
        XCTAssertEqual(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: 50, y: 14),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ), 1)
        XCTAssertEqual(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: 250, y: 14),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ), 3)
    }

    func testPointInsideBufferStillReorders() {
        XCTAssertEqual(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: 50, y: -10),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ), 1, "标签条下方 10pt 仍属 20pt 缓冲，必须继续重排")
        XCTAssertEqual(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: -10, y: 14),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ), 0)
        XCTAssertEqual(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: 310, y: 14),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ), 3)
    }

    func testPointOutsideBufferReturnsNil() {
        XCTAssertNil(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: 50, y: -30),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ))
        XCTAssertNil(FFTabReorder.insertionIndex(
            localPoint: NSPoint(x: 330, y: 14),
            stripBounds: bounds,
            buffer: 20,
            itemMidXs: midXs
        ))
    }
}

// MARK: - 0.8.0 Beta 顶栏几何

final class FFTopBarLayoutTests: XCTestCase {

    func testTitleBandAndTabMetrics() {
        XCTAssertEqual(FFInteractionPolicy.titleBandHeight, 36)
        XCTAssertEqual(FFInteractionPolicy.activeTabHeight, 30)
        XCTAssertEqual(FFInteractionPolicy.inactiveTabHeight, 26)
        XCTAssertEqual(FFInteractionPolicy.tabTopGap, 6)
        XCTAssertEqual(FFInteractionPolicy.tabSeamFillet, 10)
        XCTAssertEqual(FFInteractionPolicy.tabInsetFromPanel, 26)
        XCTAssertEqual(FFInteractionPolicy.iconHitSize, 24)
        XCTAssertEqual(FFInteractionPolicy.topBarHitSize, 28)
        XCTAssertEqual(FFInteractionPolicy.addButtonBottomInset, 4)
        XCTAssertEqual(FFInteractionPolicy.plusGlyphSize, 14)
        XCTAssertEqual(FFInteractionPolicy.closeGlyphSize, 10)
    }

    func testTopBarContentSharesEighteenPointCenterline() {
        XCTAssertEqual(FFTopBarMetrics.centerline, 18, accuracy: 0.001)
        // 标签框高 30、底边焊在栏底 → 框中心距顶部 21；内容上移 3pt 落到 18。
        let tabCenter = FFTabStripLayout.centerFromTop(
            bandHeight: FFTopBarMetrics.height,
            itemHeight: FFTopBarMetrics.tabHeight,
            bottomInset: 0
        )
        XCTAssertEqual(tabCenter, 21, accuracy: 0.001)
        XCTAssertEqual(tabCenter - FFTopBarMetrics.tabContentOffset, 18, accuracy: 0.001)

        let plus = FFTabStripLayout.centerFromTop(
            bandHeight: FFTopBarMetrics.height,
            itemHeight: FFInteractionPolicy.topBarHitSize,
            bottomInset: FFInteractionPolicy.addButtonBottomInset
        )
        XCTAssertEqual(plus, 18, accuracy: 0.001)
    }

    func testTopBarSinglePaneTabGroupStartsAfterControls() {
        let pane = NSRect(x: 0, y: 0, width: 900, height: FFTopBarMetrics.height)
        let group = FFTopBarLayout.tabGroupFrame(pane: pane,
                                                  contentStart: 148,
                                                  rightLimit: 1200)
        XCTAssertEqual(group.minX, 148, accuracy: 0.001)
        XCTAssertEqual(group.width, 752, accuracy: 0.001)
        XCTAssertEqual(group.height, FFTopBarMetrics.height, accuracy: 0.001)
    }

    func testTopBarDualPaneTabGroupsAlignToPanes() {
        let left = NSRect(x: 220, y: 0, width: 500, height: FFTopBarMetrics.height)
        let right = NSRect(x: 720, y: 0, width: 500, height: FFTopBarMetrics.height)
        XCTAssertEqual(FFTopBarLayout.tabGroupFrame(pane: left,
                                                     contentStart: 148,
                                                     rightLimit: 1400), left)
        XCTAssertEqual(FFTopBarLayout.tabGroupFrame(pane: right,
                                                     contentStart: 148,
                                                     rightLimit: 1400), right)
    }
}

// MARK: - Phase 5 文件标签

final class FFTagPhase5Tests: XCTestCase {
    private var dir: URL!
    private var oldTags: Any?

    override func setUp() {
        super.setUp()
        oldTags = UserDefaults.standard.object(forKey: "SidebarTags")
        dir = URL(fileURLWithPath: "/tmp/ff-tags-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        if let oldTags {
            UserDefaults.standard.set(oldTags, forKey: "SidebarTags")
        } else {
            UserDefaults.standard.removeObject(forKey: "SidebarTags")
        }
        TagCatalog.shared.reload()
        TagBridge.shared.invalidateAllCache()
        super.tearDown()
    }

    private func makeFile(_ name: String) -> String {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url.path
    }

    func testMultipleTagFiltersUseAndSemantics() {
        let red = Tag(name: "红", color: "#FF453A")
        let work = Tag(name: "工作", color: "#0A84FF")
        let a = FileEntry(path: "/a", name: "a", isDirectory: false, tags: [red, work])
        let b = FileEntry(path: "/b", name: "b", isDirectory: false, tags: [red])
        let c = FileEntry(path: "/c", name: "c", isDirectory: false, tags: [work])
        XCTAssertEqual(PaneViewModel.filterEntries([a, b, c],
                                                   tagFilters: [red, work],
                                                   searchQuery: "").map(\.path), ["/a"])
        XCTAssertEqual(PaneViewModel.filterEntries([a, b],
                                                   tagFilters: [red],
                                                   searchQuery: "").map(\.path), ["/a", "/b"])
    }

    func testMutateTagRenamesAcrossAllFiles() {
        let alpha = Tag(name: "Alpha", color: "#FF453A")
        let p1 = makeFile("a1.txt")
        let p2 = makeFile("a2.txt")
        XCTAssertTrue(TagBridge.shared.setTags([alpha], path: p1))
        XCTAssertTrue(TagBridge.shared.setTags([alpha], path: p2))

        let done = expectation(description: "rename")
        TagIndexStore.mutateTag(oldName: "Alpha", newName: "Gamma",
                                newColor: "#30D158", includeSpotlight: false) { _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        for path in [p1, p2] {
            let tags = TagBridge.shared.getTags(path: path)
            XCTAssertEqual(tags.map(\.name), ["Gamma"])
            XCTAssertEqual(tags.first?.color, "#30D158")
        }
    }

    func testMutateTagDeletesFromAllFiles() {
        let alpha = Tag(name: "Alpha", color: "#FF453A")
        let p1 = makeFile("d1.txt")
        let p2 = makeFile("d2.txt")
        _ = TagBridge.shared.setTags([alpha], path: p1)
        _ = TagBridge.shared.setTags([alpha], path: p2)

        let done = expectation(description: "delete")
        TagIndexStore.mutateTag(oldName: "Alpha", newName: nil,
                                newColor: nil, includeSpotlight: false) { _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertTrue(TagBridge.shared.getTags(path: p1).isEmpty)
        XCTAssertTrue(TagBridge.shared.getTags(path: p2).isEmpty)
    }

    func testBatchApplyAddsTagToAllPaths() {
        let tag = Tag(name: "批量", color: "#BF5AF2")
        let p1 = makeFile("b1.txt")
        let p2 = makeFile("b2.txt")
        let done = expectation(description: "batch")
        TagCatalog.shared.addTag(tag, to: [p1, p2]) { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(TagBridge.shared.getTags(path: p1).map(\.name), ["批量"])
        XCTAssertEqual(TagBridge.shared.getTags(path: p2).map(\.name), ["批量"])
    }

    func testCatalogRenameMergesIntoExistingDefinition() {
        let old = UserDefaults.standard.object(forKey: "SidebarTags")
        defer {
            if let old { UserDefaults.standard.set(old, forKey: "SidebarTags") }
            else { UserDefaults.standard.removeObject(forKey: "SidebarTags") }
            TagCatalog.shared.reload()
        }
        let a = Tag(name: "Alpha", color: "#FF453A")
        let b = Tag(name: "Beta", color: "#0A84FF")
        UserDefaults.standard.set(try? JSONEncoder().encode([a, b]), forKey: "SidebarTags")
        TagCatalog.shared.reload()
        _ = TagCatalog.shared.rename(id: a.id, to: "Beta", includeSpotlight: false)
        XCTAssertEqual(TagCatalog.shared.tags.map(\.name), ["Beta"])
        XCTAssertEqual(TagCatalog.shared.tags.first?.id, b.id)
    }
}

// MARK: - Phase 4 详情浮层策略

final class FFDetailsPhase4PolicyTests: XCTestCase {

    func testExpandedHeightRangeAndDefault() {
        XCTAssertEqual(FFDetailsLayoutPolicy.defaultExpandedHeight, 132)
        XCTAssertEqual(FFDetailsLayoutPolicy.minimumExpandedHeight, 132)
        XCTAssertEqual(FFDetailsLayoutPolicy.maximumExpandedHeight, 300)
        XCTAssertEqual(FFDetailsLayoutPolicy.maxExpandedHeight(forPaneHeight: 700), 300)
        XCTAssertEqual(FFDetailsLayoutPolicy.maxExpandedHeight(forPaneHeight: 240), 132)
    }

    func testPreviewColumnWidthRangeAndDefault() {
        XCTAssertEqual(FFDetailsLayoutPolicy.defaultPreviewColumnWidth, 132)
        XCTAssertEqual(FFDetailsLayoutPolicy.minimumPreviewColumnWidth, 96)
        XCTAssertEqual(FFDetailsLayoutPolicy.maximumPreviewColumnWidth, 232)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedPreviewColumnWidth(40), 96)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedPreviewColumnWidth(260), 232)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedPreviewColumnWidth(150), 150)
    }
}

// MARK: - Phase 3 面板宽度模型

final class FFPaneWidthMathTests: XCTestCase {

    func testSoftMinimumIsFourHundredAndHardMinimumIsThreeSixty() {
        XCTAssertEqual(FFPaneWidthMath.preferredMin, 400)
        XCTAssertEqual(FFPaneWidthMath.hardMin, 360)
        XCTAssertEqual(FFPaneWidthMath.effectiveMin(total: 1200), 400)
        XCTAssertEqual(FFPaneWidthMath.effectiveMin(total: 780), 390)
        XCTAssertEqual(FFPaneWidthMath.effectiveMin(total: 720), 360)
        XCTAssertEqual(FFPaneWidthMath.effectiveMin(total: 600), 360)
    }

    func testClampNeverLetsEitherPaneGoBelowHardMinimum() {
        XCTAssertEqual(FFPaneWidthMath.clampLeft(100, total: 1000), 400)
        XCTAssertEqual(FFPaneWidthMath.clampLeft(900, total: 1000), 600)
        XCTAssertEqual(FFPaneWidthMath.clampLeft(100, total: 780), 390)
        XCTAssertEqual(FFPaneWidthMath.clampLeft(700, total: 780), 390)
        XCTAssertEqual(FFPaneWidthMath.clampLeft(500, total: 720), 360)
    }

    func testSnapsToQuarterHalfThreeQuarters() {
        XCTAssertEqual(FFPaneWidthMath.snappedRatio(0.50, total: 1000), 0.50)
        XCTAssertEqual(FFPaneWidthMath.snappedRatio(0.494, total: 1000), 0.50, accuracy: 0.0001)
        XCTAssertEqual(FFPaneWidthMath.snappedRatio(0.257, total: 1000), 0.25, accuracy: 0.0001)
        XCTAssertEqual(FFPaneWidthMath.snappedRatio(0.742, total: 1000), 0.75, accuracy: 0.0001)
        XCTAssertEqual(FFPaneWidthMath.snappedRatio(0.40, total: 1000), 0.40, accuracy: 0.0001)
    }

    func testDoubleClickTargetsHalf() {
        XCTAssertEqual(FFPaneWidthMath.doubleClickLeft(total: 1200), 600)
        XCTAssertEqual(FFPaneWidthMath.doubleClickLeft(total: 720), 360)
    }
}

// MARK: - 系统窗口按钮命中

final class FFWindowChromeTests: XCTestCase {

    func testPointInsideSingleRect() {
        let rect = NSRect(x: 0, y: 0, width: 20, height: 20)
        XCTAssertTrue(FFWindowChrome.contains(point: NSPoint(x: 10, y: 10), in: [rect]))
        XCTAssertTrue(FFWindowChrome.contains(point: NSPoint(x: 0, y: 0), in: [rect]))
        XCTAssertFalse(FFWindowChrome.contains(point: NSPoint(x: 20, y: 10), in: [rect]))
        XCTAssertFalse(FFWindowChrome.contains(point: NSPoint(x: 10, y: 20), in: [rect]))
    }

    func testPointInsideAnyOfMultipleRects() {
        let rects = [NSRect(x: 0, y: 0, width: 10, height: 10),
                     NSRect(x: 20, y: 0, width: 10, height: 10)]
        XCTAssertTrue(FFWindowChrome.contains(point: NSPoint(x: 25, y: 5), in: rects))
        XCTAssertFalse(FFWindowChrome.contains(point: NSPoint(x: 15, y: 5), in: rects))
    }

    func testEmptyRectsNeverMatch() {
        XCTAssertFalse(FFWindowChrome.contains(point: .zero, in: []))
    }
}

// MARK: - 同目录拖放策略

final class FFFileDropPolicyTests: XCTestCase {

    func testSameDirectoryFileIsNoOp() {
        XCTAssertEqual(FFFileDropPolicy.validSources(["/tmp/ff-parent/file.txt"],
                                                     destination: "/tmp/ff-parent"), [])
    }

    func testDifferentDirectoryKeepsSource() {
        XCTAssertEqual(FFFileDropPolicy.validSources(["/tmp/ff-other/file.txt"],
                                                     destination: "/tmp/ff-parent"),
                       ["/tmp/ff-other/file.txt"])
    }

    func testFolderIntoItselfIsNoOp() {
        XCTAssertEqual(FFFileDropPolicy.validSources(["/tmp/ff-parent"],
                                                     destination: "/tmp/ff-parent"), [])
    }

    func testFolderIntoDescendantIsNoOp() {
        XCTAssertEqual(FFFileDropPolicy.validSources(["/tmp/ff-parent"],
                                                     destination: "/tmp/ff-parent/child"), [])
    }

    func testMixedSourcesKeepOnlyValid() {
        let sources = ["/tmp/ff-parent/a.txt", "/tmp/ff-other/b.txt"]
        XCTAssertEqual(FFFileDropPolicy.validSources(sources, destination: "/tmp/ff-parent"),
                       ["/tmp/ff-other/b.txt"])
    }

    func testTrailingSlashAndDotSegmentsAreNormalized() {
        XCTAssertEqual(FFFileDropPolicy.validSources(["/tmp/ff-parent/./file.txt"],
                                                     destination: "/tmp/ff-parent/"), [])
    }

    func testSiblingWithSamePrefixIsNotDescendant() {
        XCTAssertEqual(FFFileDropPolicy.validSources(["/tmp/ff-parent/file.txt"],
                                                     destination: "/tmp/ff-parent-2"),
                       ["/tmp/ff-parent/file.txt"])
    }
}

// MARK: - 版本与实例治理

final class FFBuildInfoTests: XCTestCase {

    /// 版本命名规则（用户裁定 2026-10-21）：`A.B.C-yymmddxx`
    /// A=主版本（测试期恒 0）B=主线大版本（第八轮改版=8）C=小版本；
    /// 内部构建号 = yymmdd + 当日序号，显示时以 `-` 直接拼接，不再用括号。
    func testDisplayVersionFollowsDateStampedRule() {
        XCTAssertEqual(FFBuildInfo.displayVersion(marketing: "0.8.0", build: "26102101", channel: "Beta"),
                       "0.8.0-26102101 Beta")
    }

    /// R4-16 修订：关于页只显示构建时间，bundle 路径退出可见文案。
    func testAboutBuildLineShowsDateOnly() {
        XCTAssertEqual(FFBuildInfo.aboutBuildLine(buildDateText: "2026-10-21 12:30",
                                                   bundlePath: "/Users/x/Desktop/FlowFinder.app"),
                       "构建 2026-10-21 12:30")
    }
}

final class FFInstanceGuardTests: XCTestCase {

    private func instance(pid: Int32, path: String, version: String) -> FFInstanceGuard.Instance {
        FFInstanceGuard.Instance(pid: pid, path: path, version: version)
    }

    func testFiltersCurrentProcess() {
        let current = instance(pid: 100, path: "/A/FlowFinder.app", version: "0.8.0 (8001) Beta")
        let other = instance(pid: 101, path: "/B/FlowFinder.app", version: "0.7.9 (7901)")
        XCTAssertEqual(FFInstanceGuard.otherInstances(currentPID: 100, instances: [current, other]),
                       [other])
    }

    func testWarningTextListsPathAndVersion() {
        let other = instance(pid: 101, path: "/B/FlowFinder.app", version: "0.7.9 (7901)")
        let text = FFInstanceGuard.warningText(for: [other])
        XCTAssertTrue(text.contains("/B/FlowFinder.app"))
        XCTAssertTrue(text.contains("0.7.9 (7901)"))
    }
}
