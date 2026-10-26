import AppKit
import XCTest
@testable import FlowFinder

final class FFShellLayoutTests: XCTestCase {

    /// P1：窄面板下名称列不得被类型/日期挤到比它们更窄。
    func testNameColumnFloorIsFortyPercentWithMinimum() {
        XCTAssertEqual(FFColumnFitPolicy.nameFloor(available: 300), 160, accuracy: 0.1)
        XCTAssertEqual(FFColumnFitPolicy.nameFloor(available: 500), 200, accuracy: 0.1)
        XCTAssertEqual(FFColumnFitPolicy.nameFloor(available: 1000), 400, accuracy: 0.1)
    }

    func testActivePaneUsesTwoPointEdge() {
        let border = FFActivePaneBorderView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(FFVisualTokens.activePaneEdge, 2)
        XCTAssertEqual(border.edgeHeight, 2)
    }

    func testToolbarRestoresTwoVisibleRows() {
        UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey)
        let toolbar = PaneToolbar(frame: .zero)
        toolbar.side = .left
        XCTAssertNotNil(toolbar.displaySettingsButton)
        XCTAssertTrue(toolbar.showsSecondaryRow)
        XCTAssertEqual(toolbar.visibleRow2ItemsForTesting,
                       Set(FFToolbarRow2Item.allCases))
    }

    func testToolbarCanHideOneRow2ItemAndKeepsDisplaySettings() {
        UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey)
        let toolbar = PaneToolbar(frame: .zero)
        toolbar.side = .left
        defer { UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey) }
        toolbar.setRow2Item(.search, visible: false)
        XCTAssertFalse(toolbar.visibleRow2ItemsForTesting.contains(.search))
        XCTAssertFalse(toolbar.displaySettingsButton.isHidden)
    }

    func testSingleTabRemainsVisible() {
        let strip = PaneTabStripView(frame: NSRect(x: 0, y: 0, width: 400, height: 28))
        strip.refresh(sessions: [PaneTabSession(state: PaneState(path: "/tmp"))], activeIndex: 0)
        XCTAssertEqual(strip.allTabItems().count, 1)
        XCTAssertFalse(strip.isHidden)
    }

    func testDetailsBarCollapsedHeightIs54() {
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 54))
        XCTAssertEqual(bar.currentHeight, 54)
        XCTAssertFalse(bar.isExpandedForTesting)
    }

    func testHostAppDetectsXCTestIsolation() {
        XCTAssertTrue(MainWindowController.isRunningTests,
                      "测试宿主必须识别 XCTest，避免写入用户级启动路径")
    }

    func testDetailsBarReservesListBottomInset() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        guard let bar = controller.detailsBar(for: .left) else {
            return XCTFail("缺少详情栏")
        }
        XCTAssertEqual(controller.leftFileListView.bottomOverlayInsetForTesting,
                       bar.currentHeight + 8, accuracy: 1,
                       "收起态列表底部应按详情栏高度 + 8 留白")
        bar.isExpanded = true
        bar.layoutSubtreeIfNeeded()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.leftFileListView.bottomOverlayInsetForTesting,
                       bar.currentHeight + 8, accuracy: 1,
                       "展开后列表底部留白应同步")
    }

    func testSingleDualRoundTripKeepsSidebarWidth() {
        let defaults = UserDefaults.standard
        let oldHidden = defaults.object(forKey: "sidebar_hidden")
        defaults.removeObject(forKey: "sidebar_hidden")
        defer {
            if let oldHidden {
                defaults.set(oldHidden, forKey: "sidebar_hidden")
            } else {
                defaults.removeObject(forKey: "sidebar_hidden")
            }
        }

        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.setSidebarVisible(true, animated: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let sidebarBefore = controller.sidebarView.frame.width
        XCTAssertGreaterThan(sidebarBefore, 100)

        controller.isSinglePaneMode = true
        controller.applyPaneMode()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.sidebarView.frame.width, sidebarBefore, accuracy: 1,
                       "双→单侧栏宽度不得变化")

        controller.isSinglePaneMode = false
        controller.applyPaneMode()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.sidebarView.frame.width, sidebarBefore, accuracy: 1,
                       "单→双侧栏宽度不得变化")
    }

    func testWindowResizeKeepsSidebarAndEqualPaneRatio() {
        let defaults = UserDefaults.standard
        let oldHidden = defaults.object(forKey: "sidebar_hidden")
        let oldPaneLeft = defaults.object(forKey: "pane_left_width")
        defaults.removeObject(forKey: "sidebar_hidden")
        defaults.removeObject(forKey: "pane_left_width")
        defer {
            if let oldHidden {
                defaults.set(oldHidden, forKey: "sidebar_hidden")
            } else {
                defaults.removeObject(forKey: "sidebar_hidden")
            }
            if let oldPaneLeft {
                defaults.set(oldPaneLeft, forKey: "pane_left_width")
            } else {
                defaults.removeObject(forKey: "pane_left_width")
            }
        }

        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.setSidebarVisible(true, animated: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let sidebarBefore = controller.sidebarView.frame.width
        XCTAssertGreaterThan(sidebarBefore, 100)

        guard let window = controller.window else { return XCTFail("缺少窗口") }
        var frame = window.frame
        frame.size.width = 1200
        window.setFrame(frame, display: true)
        controller.applyProportionalPaneWidths()
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.sidebarView.frame.width, sidebarBefore, accuracy: 1,
                       "窗口缩放不得改变侧栏宽度")
        let widths = controller.paneSplitView.arrangedSubviews.map(\.frame.width)
        XCTAssertEqual(widths.count, 2)
        XCTAssertEqual(widths[0], widths[1], accuracy: 2,
                       "默认 50/50 比例在窗口缩放后应保持，实际 \(widths)")
    }

    func testSingleToDualRestoresBothPaneWidths() {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }

        controller.isSinglePaneMode = false
        controller.applyPaneMode()
        controller.paneSplitView.layoutSubtreeIfNeeded()

        let widths = controller.paneSplitView.arrangedSubviews.map(\.frame.width)
        XCTAssertEqual(widths.count, 2, "双栏模式必须有两块面板")
        XCTAssertTrue(widths.allSatisfy { $0 > 100 },
                      "单→双切换后两块面板都应有可见宽度，实际 \(widths)")
    }

    func testTabCloseHitTargetIs24() {
        XCTAssertEqual(FFTabMetrics.closeVisualSize, 20)
        XCTAssertGreaterThanOrEqual(FFTabMetrics.closeHitSize, 24)
    }

    func testSidebarMinimumIs180() {
        XCTAssertGreaterThanOrEqual(MainWindowController.sidebarMinWidth, 180)
    }

    func testAuxiliaryWindowsHandleCmdW() {
        let selector = #selector(MainWindowController.menuCloseTab(_:))
        let controllers: [NSWindowController] = [
            SettingsWindowController.shared,
            SearchPanelController.shared,
            DuplicateScanWindowController.shared,
            BatchRenameWindowController.shared,
            TaskPanelWindowController.shared,
        ]
        for controller in controllers {
            XCTAssertTrue(controller.responds(to: selector),
                          "\(type(of: controller)) 应响应 ⌘W 关闭自身窗口")
        }
    }

    func testDualPaneMinWidthFits1060Window() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }

        XCTAssertEqual(controller.window?.minSize.width, 1060)
        XCTAssertLessThanOrEqual(FFDividerGlowMath.minPaneWidth, 400)
        XCTAssertLessThanOrEqual(
            MainWindowController.sidebarMinWidth + FFDividerGlowMath.minPaneWidth * 2 + 32,
            1060,
            "侧栏 + 两个面板 + 边距必须能放进 1060 窗口"
        )
    }

    func testDualPaneSplitViewAllows400PaneAtAnyWidth() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }

        XCTAssertEqual(FFDividerGlowMath.minPaneWidth, 400)
        XCTAssertEqual(
            controller.splitView(controller.paneSplitView,
                                 constrainMinCoordinate: 0,
                                 ofSubviewAt: 1),
            400,
            "分栏最小坐标应使用 400，而不是旧的 450"
        )
    }

    func testPaneContentIsClippedToContinuousPanelRadius() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }

        guard let container = controller.leftPaneContainer,
              let clip = container.subviews.compactMap({ $0 as? FFPaneContentClipView }).first else {
            return XCTFail("操作面板缺少内容裁切层")
        }
        XCTAssertEqual(clip.layer?.cornerRadius ?? 0, FFVisualTokens.Radius.panel, accuracy: 0.1)
        XCTAssertEqual(clip.layer?.cornerCurve, .continuous)
        XCTAssertTrue(clip.layer?.masksToBounds ?? false)
        XCTAssertTrue(controller.leftPaneToolbar.isDescendant(of: clip),
                      "工具栏必须位于裁切层内，否则会盖住卡片圆角")
        XCTAssertNotNil(controller.detailsBar(for: .left))
    }

    func testSinglePaneActivePaneSwitchFillsSplit() {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        controller.activePane = .right
        controller.applyPaneMode()
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let split = controller.paneSplitView!
        XCTAssertEqual(split.arrangedSubviews.count, 1, "单栏切换活动面板后只能有一块面板")
        let visible = split.arrangedSubviews[0]
        XCTAssertEqual(visible.frame.width, split.bounds.width, accuracy: 1,
                       "可见面板必须填满分栏宽度，实际 \(visible.frame) vs \(split.bounds)")
        XCTAssertEqual(visible.frame.height, split.bounds.height, accuracy: 1,
                       "可见面板必须填满分栏高度，实际 \(visible.frame) vs \(split.bounds)")
    }

    func testGlobalTopBarOrderAndSharedCenterline() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.updateGlobalTopBarLayout()

        guard let bar = controller.globalTopBar else {
            return XCTFail("缺少窗口级全局顶栏")
        }
        XCTAssertEqual(bar.frame.height, FFTopBarMetrics.height, accuracy: 1,
                       "顶栏高度应为 44")
        let ordered: [NSView] = [bar.sidebarButton,
                                 bar.leftTabStrip, bar.rightTabStrip,
                                 bar.themeButton, bar.paneModeButton]
        let minXs = ordered.map { $0.convert($0.bounds, to: bar).minX }
        XCTAssertEqual(minXs, minXs.sorted(),
                       "顶栏顺序必须是 侧栏→左标签→右标签→主题→单双栏，实际 \(minXs)")
        for view in ordered {
            let rect = view.convert(view.bounds, to: bar)
            XCTAssertEqual(bar.bounds.height - rect.midY, FFTopBarMetrics.centerline,
                           accuracy: 1,
                           "\(type(of: view)) 未对齐 22pt 中线（\(rect)）")
        }
        XCTAssertGreaterThan(bar.leftTabStrip.frame.width, 100)
        XCTAssertGreaterThan(bar.rightTabStrip.frame.width, 100)
    }

    func testSinglePaneShowsOnlyActivePaneTabStrip() {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        controller.activePane = .right
        controller.applyPaneMode()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.updateGlobalTopBarLayout()

        let bar = controller.globalTopBar!
        XCTAssertTrue(bar.leftTabStrip.isHidden, "单栏右侧时左标签组必须隐藏")
        XCTAssertFalse(bar.rightTabStrip.isHidden, "单栏右侧时右标签组必须显示")
        XCTAssertEqual(bar.rightTabStrip.allTabItems().count, 1)
        XCTAssertGreaterThan(bar.rightTabStrip.frame.width, 100)
        XCTAssertLessThanOrEqual(bar.rightTabStrip.frame.maxX,
                                 bar.themeButton.frame.minX,
                                 "右标签组不能压到主题/单双栏按钮")
    }

    /// R4-19：切到单面板后，被收起那一栏的标签必须整组消失，
    /// 既不能留在标签条上成为点不到的死条目，也不能混进可见那一栏的标签组。
    func testCollapsedPaneTabsDisappearInSinglePaneMode() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.newTab(in: .left, path: "/tmp/ff-r419-left"))
        XCTAssertTrue(controller.newTab(in: .right, path: "/tmp/ff-r419-right"))
        controller.updateGlobalTopBarLayout()

        let bar = controller.globalTopBar!
        let leftTitles = bar.leftTabStrip.allTabItems().map(\.titleText)
        let rightTitles = bar.rightTabStrip.allTabItems().map(\.titleText)
        XCTAssertTrue(leftTitles.contains("ff-r419-left"), "双栏时左标签组应有左栏新建的标签：\(leftTitles)")
        XCTAssertFalse(leftTitles.contains("ff-r419-right"), "左标签组不得混入右栏标签：\(leftTitles)")
        XCTAssertTrue(rightTitles.contains("ff-r419-right"), "双栏时右标签组应有右栏新建的标签：\(rightTitles)")
        XCTAssertFalse(rightTitles.contains("ff-r419-left"), "右标签组不得混入左栏标签：\(rightTitles)")

        controller.isSinglePaneMode = true
        controller.activePane = .left
        controller.applyPaneMode()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.updateGlobalTopBarLayout()

        XCTAssertTrue(bar.rightTabStrip.isHidden,
                      "单栏左侧时右标签组必须整组隐藏，否则收起面板的标签留在标签条上（R4-19）")
        XCTAssertFalse(bar.leftTabStrip.isHidden)
        XCTAssertFalse(bar.leftTabStrip.allTabItems().map(\.titleText).contains("ff-r419-right"),
                       "可见标签组里不得出现被收起面板的标签（R4-19）")

        // 隐藏只是收起：标签数据要保住，切回双栏时原样还原
        controller.isSinglePaneMode = false
        controller.applyPaneMode()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.updateGlobalTopBarLayout()
        XCTAssertFalse(bar.rightTabStrip.isHidden, "切回双栏后右标签组要回来")
        XCTAssertTrue(bar.rightTabStrip.allTabItems().map(\.titleText).contains("ff-r419-right"),
                      "切回双栏后被收起期间保住的标签必须还原")
    }

    func testHiddenSidebarKeepsPaneToolbarAtEightAndTabsClearControls() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        controller.setSidebarVisible(false, animated: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.updateGlobalTopBarLayout()
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.leftPaneToolbar.leadingInset, 8, accuracy: 0.1,
                       "隐藏侧栏后左侧面板工具栏仍应保持 8pt 缩进")
        XCTAssertEqual(controller.rightPaneToolbar.leadingInset, 8, accuracy: 0.1,
                       "右侧面板工具栏不应被隐藏侧栏推到 112")
        guard let bar = controller.globalTopBar else {
            return XCTFail("缺少全局顶栏")
        }
        let strip = bar.leftTabStrip
        XCTAssertGreaterThan(strip.frame.minX, bar.sidebarButton.frame.maxX,
                             "隐藏侧栏后标签组必须让开工具/侧栏按钮（\(strip.frame) vs \(bar.sidebarButton.frame)）")
        XCTAssertGreaterThan(strip.frame.width, 100)
    }

    func testGlobalTopBarFullScreenUsesSixteenPointMargins() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        controller.globalTopBar.fullScreenOverride = true
        controller.updateGlobalTopBarLayout()
        controller.globalTopBar.layoutSubtreeIfNeeded()

        let bar = controller.globalTopBar!
        XCTAssertEqual(bar.sidebarButton.frame.minX, 16, accuracy: 1,
                       "全屏顶栏左缘应为 16")
        XCTAssertEqual(bar.paneModeButton.frame.maxX, bar.bounds.width - 16, accuracy: 1,
                       "全屏顶栏右缘应为 16")
    }

    func testTrafficLightsAlignToTopBarCenterline() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.alignTrafficLightsToTopBar()

        guard let window = controller.window,
              let content = window.contentView else {
            return XCTFail("缺少窗口内容视图")
        }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type),
                  let superview = button.superview else {
                return XCTFail("缺少系统窗口按钮 \(type)")
            }
            let center = superview.convert(
                NSPoint(x: button.frame.midX, y: button.frame.midY), to: content)
            XCTAssertEqual(content.bounds.height - center.y,
                           FFTopBarMetrics.centerline,
                           accuracy: 1.5,
                           "红绿灯未对齐 18pt 中线：\(type) center=\(center)")
        }
    }

    func testLayoutDiagnosticsReportNoAnomaliesOnHealthyWindow() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.layoutAnomalies(phase: "健康窗口"), [],
                       "布局诊断不能对健康窗口误报：\(controller.layoutSummary())")
    }

    // MARK: - Phase 0：图二「操作区空白 / 详情栏悬空」布局回归

    func testNewWindowCanPrepareFirstFrameBeforeShow() {
        let defaults = UserDefaults.standard
        let oldHidden = defaults.object(forKey: "sidebar_hidden")
        defaults.removeObject(forKey: "sidebar_hidden")
        defer {
            if let oldHidden {
                defaults.set(oldHidden, forKey: "sidebar_hidden")
            } else {
                defaults.removeObject(forKey: "sidebar_hidden")
            }
        }

        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.prepareForInitialDisplay()

        let width = controller.paneSplitView.bounds.width
        XCTAssertGreaterThan(width, 900,
                             "新窗口首帧不应停在 50/50 的 700pt（实际 \(width)）")
        XCTAssertLessThan(width, 1200)
        XCTAssertGreaterThan(controller.paneSplitView.arrangedSubviews[0].frame.width, 400)
    }

    func testNewWindowLaysOutVisibleContentBeforeShow() {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let split = controller.paneSplitView!
        XCTAssertEqual(split.arrangedSubviews.count, 1,
                       "新窗口显示前必须只排列一块可见面板")
        XCTAssertTrue(controller.window?.isVisible == false,
                      "本测试验证 show 之前的布局，窗口不应提前显示")
        assertVisiblePaneFillsSplit(controller, split: split, phase: "新窗口显示前")
        assertActivePaneContentLaidOut(controller, phase: "新窗口显示前")
    }

    func testAlternatingSidebarAndPaneModeKeepsContentLaidOut() {
        let defaults = UserDefaults.standard
        let oldSidebarHidden = defaults.object(forKey: "sidebar_hidden")
        defer {
            if let oldSidebarHidden {
                defaults.set(oldSidebarHidden, forKey: "sidebar_hidden")
            } else {
                defaults.removeObject(forKey: "sidebar_hidden")
            }
        }

        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        for cycle in 0..<20 {
            controller.setSidebarVisible(false, animated: false)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            assertDualPaneContentLaidOut(controller, phase: "第 \(cycle) 轮隐藏侧栏")

            controller.activePane = (cycle % 2 == 0) ? .right : .left
            controller.isSinglePaneMode = true
            controller.applyPaneMode()
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            let split = controller.paneSplitView!
            XCTAssertEqual(split.arrangedSubviews.count, 1,
                           "第 \(cycle) 轮单栏只能排列一块面板")
            assertVisiblePaneFillsSplit(controller, split: split, phase: "第 \(cycle) 轮单栏")
            assertActivePaneContentLaidOut(controller, phase: "第 \(cycle) 轮单栏")

            controller.setSidebarVisible(true, animated: false)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            assertActivePaneContentLaidOut(controller, phase: "第 \(cycle) 轮显示侧栏")

            controller.isSinglePaneMode = false
            controller.applyPaneMode()
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            assertDualPaneContentLaidOut(controller, phase: "第 \(cycle) 轮双栏")
        }
    }

    private func assertVisiblePaneFillsSplit(_ controller: MainWindowController,
                                              split: FFSplitView,
                                              phase: String) {
        guard let wrapper = split.arrangedSubviews.first else {
            return XCTFail("\(phase)：分栏里没有可见面板")
        }
        XCTAssertGreaterThan(split.bounds.height, 100, "\(phase)：分栏高度塌陷 \(split.bounds)")
        XCTAssertEqual(wrapper.frame.height, split.bounds.height, accuracy: 1,
                       "\(phase)：面板高度未填满分栏 \(wrapper.frame) vs \(split.bounds)")
        XCTAssertEqual(wrapper.frame.width, split.bounds.width, accuracy: 1,
                       "\(phase)：单栏面板宽度未填满分栏 \(wrapper.frame) vs \(split.bounds)")
        XCTAssertFalse(wrapper.isHidden, "\(phase)：可见面板被标记隐藏")
    }

    private func assertDualPaneContentLaidOut(_ controller: MainWindowController,
                                               phase: String) {
        let split = controller.paneSplitView!
        XCTAssertEqual(split.arrangedSubviews.count, 2, "\(phase)：双栏必须排列两块面板")
        XCTAssertGreaterThan(split.bounds.height, 100, "\(phase)：分栏高度塌陷 \(split.bounds)")
        for wrapper in split.arrangedSubviews {
            XCTAssertFalse(wrapper.isHidden, "\(phase)：双栏面板被标记隐藏")
            XCTAssertGreaterThan(wrapper.frame.width, 100,
                                 "\(phase)：双栏面板宽度塌陷 \(wrapper.frame)")
            XCTAssertEqual(wrapper.frame.height, split.bounds.height, accuracy: 1,
                           "\(phase)：面板高度未填满分栏 \(wrapper.frame) vs \(split.bounds)")
        }
        assertPaneContentLaidOut(controller,
                                 wrapper: controller.leftPaneWrapper,
                                 side: .left,
                                 phase: phase)
        assertPaneContentLaidOut(controller,
                                 wrapper: controller.rightPaneWrapper,
                                 side: .right,
                                 phase: phase)
    }

    private func assertActivePaneContentLaidOut(_ controller: MainWindowController,
                                                 phase: String) {
        let wrapper = controller.activePane == .left
            ? controller.leftPaneWrapper
            : controller.rightPaneWrapper
        assertPaneContentLaidOut(controller,
                                 wrapper: wrapper,
                                 side: controller.activePane,
                                 phase: phase)
    }

    private func assertPaneContentLaidOut(_ controller: MainWindowController,
                                          wrapper: NSView?,
                                          side: PaneSide,
                                          phase: String) {
        guard let wrapper, wrapper.superview != nil else {
            return XCTFail("\(phase)：\(side) 面板不在分栏层级中")
        }
        guard let container = wrapper.subviews.first(where: { view in
            view.subviews.contains { $0 is FFPaneContentClipView }
        }) else {
            return XCTFail("\(phase)：\(side) 面板缺少内容容器")
        }
        guard let clip = container.subviews.compactMap({ $0 as? FFPaneContentClipView }).first,
              let details = controller.detailsBar(for: side),
              let list = side == .left ? controller.leftFileListView : controller.rightFileListView else {
            return XCTFail("\(phase)：\(side) 面板布局组件缺失")
        }

        XCTAssertGreaterThan(container.bounds.height, 100,
                             "\(phase)：\(side) 卡片高度塌陷 \(container.bounds)")
        XCTAssertGreaterThan(clip.frame.height, 100,
                             "\(phase)：\(side) 内容裁切层高度塌陷 \(clip.frame)")
        XCTAssertGreaterThan(list.frame.height, 100,
                             "\(phase)：\(side) 文件列表高度塌陷 \(list.frame)")
        XCTAssertGreaterThan(details.frame.height, 40,
                             "\(phase)：\(side) 详情栏高度异常 \(details.frame)")
        // AppKit 非翻转坐标：y=0 是卡片底部，详情栏贴底时 minY=8。
        XCTAssertLessThan(details.frame.minY, container.bounds.height / 2,
                          "\(phase)：\(side) 详情栏悬空到顶部 \(details.frame) / 卡片 \(container.bounds)")
        XCTAssertEqual(details.frame.minY, 8, accuracy: 2,
                       "\(phase)：\(side) 详情栏未贴卡片底部 \(details.frame) / 卡片 \(container.bounds)")
    }

    func testViewModePolicyDoesNotReapplySameMode() {
        XCTAssertFalse(FFViewModePolicy.shouldApply(previous: .list, current: .list))
        XCTAssertTrue(FFViewModePolicy.shouldApply(previous: .list, current: .grid))
        XCTAssertTrue(FFViewModePolicy.shouldApply(previous: nil, current: .list))
    }

    // MARK: - R4-03：最小尺寸 1060×700 下的工具栏/面包屑/列分级

    /// 行宽充足时什么都不收。
    func testRow2FitKeepsEveryControlInlineWhenWide() {
        let dropped = FFToolbarRow2Fit.overflowed(from: Set(FFToolbarRow2Fit.Slot.allCases),
                                                  rowWidth: 700)
        XCTAssertTrue(dropped.isEmpty)
    }

    /// 实测宽度：1060×700 双栏行宽 416，面板下限 400 时行宽 384。
    /// 让位顺序固定 分组 → 范围 → 排序；搜索框/视图切换/显示设置永不收进「更多」。
    func testRow2FitDropsGroupThenScopeThenSortAsTheRowNarrows() {
        let all = Set(FFToolbarRow2Fit.Slot.allCases)
        XCTAssertEqual(FFToolbarRow2Fit.overflowed(from: all, rowWidth: 416), [.group, .scope])
        XCTAssertEqual(FFToolbarRow2Fit.overflowed(from: all, rowWidth: 384), [.group, .scope])
        XCTAssertEqual(FFToolbarRow2Fit.overflowed(from: all, rowWidth: 300), [.group, .scope, .sort])
    }

    /// 用户已关闭的项不该被当成「收进更多」。
    func testRow2FitOnlyReportsEnabledSlots() {
        XCTAssertTrue(FFToolbarRow2Fit.overflowed(from: [], rowWidth: 100).isEmpty)
        XCTAssertEqual(FFToolbarRow2Fit.overflowed(from: [.group], rowWidth: 100), [.group])
        XCTAssertTrue(FFToolbarRow2Fit.overflowed(from: [.sort], rowWidth: 1000).isEmpty)
    }

    /// 预留宽度必须盖住每一项的最长标题，否则下拉会截成「…」（R4-03 实测症状）。
    func testRow2FitWidthsCoverEveryPopupTitle() throws {
        UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey)
        let toolbar = PaneToolbar(frame: .zero)
        toolbar.side = .left

        let scope = toolbar.scopePopupForTesting
        for value in FFSearchScope.allCases {
            scope.selectItem(withTitle: value.title)
            XCTAssertLessThanOrEqual(scope.intrinsicContentSize.width,
                                     FFToolbarRow2Fit.width(for: .scope),
                                     "范围「\(value.title)」超出预留宽度")
        }
        let sort = toolbar.sortPopupForTesting
        for field in SortField.allCases {
            sort.selectItem(withTitle: field.rawValue)
            XCTAssertLessThanOrEqual(sort.intrinsicContentSize.width,
                                     FFToolbarRow2Fit.width(for: .sort),
                                     "排序「\(field.rawValue)」超出预留宽度")
        }
        let group = toolbar.groupPopupForTesting
        for title in ["无分组", "按种类", "按日期", "按大小"] {
            group.selectItem(withTitle: title)
            XCTAssertLessThanOrEqual(group.intrinsicContentSize.width,
                                     FFToolbarRow2Fit.width(for: .group),
                                     "分组「\(title)」超出预留宽度")
        }
    }

    /// 收进「更多」的项必须能在菜单里继续操作，否则等于功能丢失。
    func testRow2OverflowMenuCarriesDroppedControls() throws {
        UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey)
        let toolbar = PaneToolbar(frame: .zero)
        toolbar.side = .left
        toolbar.applyRow2Fit(rowWidth: 416)

        let menu = toolbar.makeRow2OverflowMenu()
        let submenus = Set(menu.items.compactMap { $0.submenu?.title })
        XCTAssertEqual(submenus, ["分组", "搜索范围"],
                       "416pt 行宽下分组与范围被收起，菜单里必须还在")
        XCTAssertFalse(submenus.contains("排序"))

        // 菜单项要真的能改状态：行内下拉此时是隐藏的，选完仍要写回同一份状态
        let scopeEntry = try XCTUnwrap(menu.items.first { $0.submenu?.title == "搜索范围" })
        XCTAssertEqual(scopeEntry.title, "搜索范围：本栏")
        let pick = try XCTUnwrap(scopeEntry.submenu?.items.first { $0.title == "含子目录" })
        XCTAssertNotNil(pick.target)
        XCTAssertTrue(pick.target!.responds(to: pick.action!), "菜单项动作必须挂在工具栏自身")
        pick.target!.perform(pick.action, with: pick)
        XCTAssertEqual(toolbar.scopePopupForTesting.titleOfSelectedItem, "含子目录")

        // 再开一次：当前值要跟着变，勾也要跟着走
        let reopened = toolbar.makeRow2OverflowMenu()
        let reopenedEntry = try XCTUnwrap(reopened.items.first { $0.submenu?.title == "搜索范围" })
        XCTAssertEqual(reopenedEntry.title, "搜索范围：含子目录")
        let checked = reopenedEntry.submenu?.items.filter { $0.state == .on }.map { $0.title }
        XCTAssertEqual(checked, ["含子目录"])
    }

    /// 声明的最小尺寸下：图标按钮不得被压成 0 宽，行内不得有控件越界。
    func testMinSizeWindowKeepsRow2ControlsVisible() throws {
        UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey)
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        guard let window = controller.window, let content = window.contentView else {
            return XCTFail("缺少窗口")
        }
        var frame = window.frame
        frame.size = NSSize(width: 1060, height: 700)
        window.setFrame(frame, display: false)
        content.layoutSubtreeIfNeeded()

        guard let toolbar = controller.leftPaneToolbar else { return XCTFail("缺少工具栏") }
        let row2 = try XCTUnwrap(toolbar.row2ForTesting)
        let eyeButton: NSButton = toolbar.displaySettingsButton
        for button in [toolbar.listViewButtonForTesting,
                       toolbar.gridViewButtonForTesting,
                       eyeButton] {
            XCTAssertEqual(button.frame.width, 28, accuracy: 0.5,
                           "主操作按钮被压成 \(button.frame.width)pt（R4-03：视图切换/显示设置消失）")
            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor, "\(button) 在最小尺寸下不可见")
        }
        assertRow2Fallback(toolbar)
        for view in row2.arrangedSubviews where !view.isHidden {
            XCTAssertLessThanOrEqual(view.frame.maxX, row2.bounds.maxX + 0.5,
                                     "\(type(of: view)) 越出行尾：\(view.frame) vs \(row2.bounds)")
            XCTAssertGreaterThanOrEqual(view.frame.minX, row2.bounds.minX - 0.5,
                                        "\(type(of: view)) 越出行首：\(view.frame)")
        }

        // 侧栏可见时实测行宽只有 416pt：文字下拉整组收进「更多」，图标按钮宽度不受影响
        toolbar.applyRow2Fit(rowWidth: 416)
        XCTAssertEqual(toolbar.row2OverflowedSlots, [.group, .scope])
        XCTAssertTrue(toolbar.groupPopupForTesting.isHiddenOrHasHiddenAncestor)
        XCTAssertTrue(toolbar.scopePopupForTesting.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(toolbar.sortPopupForTesting.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(toolbar.row2OverflowButtonForTesting.isHiddenOrHasHiddenAncestor,
                       "分组/范围收进「更多」后必须留下入口")
        XCTAssertEqual(eyeButton.frame.width, 28, accuracy: 0.5, "收起文字下拉不得挤压图标按钮")
    }

    /// 行宽不足时可以收起文字下拉，但被收起的项必须能在「更多」里继续用。
    private func assertRow2Fallback(_ toolbar: PaneToolbar,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        let dropped = toolbar.row2OverflowedSlots
        let popups: [FFToolbarRow2Fit.Slot: NSPopUpButton] = [
            .group: toolbar.groupPopupForTesting,
            .scope: toolbar.scopePopupForTesting,
            .sort: toolbar.sortPopupForTesting,
        ]
        for slot in FFToolbarRow2Fit.Slot.allCases {
            XCTAssertEqual(popups[slot]!.isHiddenOrHasHiddenAncestor, dropped.contains(slot),
                           "\(slot.rawValue) 的显隐应与收起状态一致", file: file, line: line)
        }
        XCTAssertEqual(toolbar.row2OverflowButtonForTesting.isHiddenOrHasHiddenAncestor,
                       dropped.isEmpty, "「更多」按钮只应在确有收起项时出现",
                       file: file, line: line)
    }

    /// 面包屑溢出时整段收起，不得把路径切一半压在省略号下（R4-03 实测「压住刷新按钮」）。
    func testBreadcrumbDropsWholeSegmentsWhenNarrow() throws {
        let bar = BreadcrumbBar(frame: NSRect(x: 0, y: 0, width: 284, height: 24))
        bar.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 284, height: 24))
        host.addSubview(bar)
        NSLayoutConstraint.activate([
            // host 无父视图，Auto Layout 不会从它的 frame 推出尺寸约束，必须显式给宽
            host.widthAnchor.constraint(equalToConstant: 284),
            host.heightAnchor.constraint(equalToConstant: 24),
            bar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bar.topAnchor.constraint(equalTo: host.topAnchor),
            bar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        bar.setPath("/Volumes/Iris-Data/文件管理系统/flowfinder-native/FlowFinder/FlowFinder/UI")
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()

        let segments = bar.segmentButtonsForTesting
        XCTAssertEqual(bar.frame.width, 284, "宿主宽度未生效，测不出溢出")
        XCTAssertTrue(bar.isOverflowingForTesting, "284pt 放不下这条路径，应进入溢出态")
        let visible = segments.filter { !$0.isHiddenOrHasHiddenAncestor }
        XCTAssertFalse(visible.isEmpty, "溢出时当前目录仍要可见")
        XCTAssertEqual(visible.last?.title, segments.last?.title,
                       "最后一段（当前目录）必须始终显示")
        let ellipsis = bar.overflowButtonForTesting
        let ellipsisRight = ellipsis.frame.maxX   // 省略号贴本视图左缘，与 bar 同坐标系
        for segment in visible {
            let inBar = bar.convert(segment.frame, from: try XCTUnwrap(segment.superview))
            XCTAssertGreaterThanOrEqual(inBar.minX, ellipsisRight - 0.5,
                                        "路径段「\(segment.title ?? "")」压在省略号上：\(inBar) vs \(ellipsis.frame)")
        }
    }

    /// 面板太窄被临时收起的列要在「显示列」里说清楚，不能无声消失（R4-03）。
    func testFittedOutColumnsAreMarkedInColumnMenu() throws {
        FFListColumnsState.setFittedOut([.kind], for: .left)
        defer { FFListColumnsState.setFittedOut([], for: .left) }

        let menu = FFListColumnMenu.build(target: nil, action: #selector(NSApplication.terminate(_:)))
        let kind = try XCTUnwrap(menu.items.first { $0.representedObject as? String == "kind" })
        XCTAssertEqual(kind.title, "类型（面板太窄）")

        let name = try XCTUnwrap(menu.items.first { $0.representedObject as? String == "name" })
        XCTAssertEqual(name.title, "名称", "未被收起的列不得加后缀")
    }

    /// 单侧收起即标注，另一侧变宽后标注要能消失。
    func testFittedOutRegistryClearsPerSide() {
        FFListColumnsState.setFittedOut([.kind], for: .left)
        FFListColumnsState.setFittedOut([.kind], for: .right)
        XCTAssertEqual(FFListColumnsState.fittedOutColumns(), [.kind])
        FFListColumnsState.setFittedOut([], for: .left)
        XCTAssertEqual(FFListColumnsState.fittedOutColumns(), [.kind])
        FFListColumnsState.setFittedOut([], for: .right)
        XCTAssertTrue(FFListColumnsState.fittedOutColumns().isEmpty)
    }
}
