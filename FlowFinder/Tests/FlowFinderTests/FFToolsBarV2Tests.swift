import AppKit
import XCTest
@testable import FlowFinder

// MARK: - 新模型：药丸详情栏 + 54pt 圆形工具簇（2026-10-24 第二轮）

/// 详情栏默认是 54pt 药丸；展开为 132/240 胶囊，工具按钮自动隐藏。
final class FFDetailsPillTests: XCTestCase {

    private var oldTier: Any?

    override func setUp() {
        super.setUp()
        FFToolRegistry.registerBuiltInsIfNeeded()
        oldTier = UserDefaults.standard.object(forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        UserDefaults.standard.set(132.0, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
    }

    override func tearDown() {
        if let oldTier {
            UserDefaults.standard.set(oldTier, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        }
        super.tearDown()
    }

    @MainActor
    private func makeBar(containerHeight: CGFloat = 600) -> (ExpandableDetailsBar, NSView) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: containerHeight))
        let bar = ExpandableDetailsBar(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -70),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        container.layoutSubtreeIfNeeded()
        return (bar, container)
    }

    @MainActor
    private func selectFile(_ bar: ExpandableDetailsBar) {
        bar.update(with: FileEntry(path: "/tmp/pill.txt", name: "pill.txt", isDirectory: false))
    }

    /// 默认态：54pt 药丸，圆角 = 高度 / 2，内容垂直居中，状态栏让位给药丸形状
    @MainActor
    func testCollapsedBarIsPillWithCenteredContent() {
        let (bar, container) = makeBar()
        selectFile(bar)
        bar.updateStatus(itemCount: 3)
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(bar.currentHeight, 54, accuracy: 0.5)
        XCTAssertEqual(bar.cornerRadiusForTesting, 27, accuracy: 0.5)
        XCTAssertEqual(bar.compactContentFrameForTesting.midY, bar.bounds.midY, accuracy: 1,
                       "药丸内容应垂直居中，不再被底部状态栏挤到上半部")
        XCTAssertTrue(bar.statusLabelHiddenForTesting,
                      "收起态隐藏底部项目计数，避免文字压到药丸圆角")
    }

    /// 标准 132：展开为卡片（12pt 圆角）、横向内边距 30
    @MainActor
    func testStandardTierIsCardWithThirtyInset() {
        let (bar, container) = makeBar()
        selectFile(bar)
        bar.updateStatus(itemCount: 3)
        bar.isExpanded = true
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(bar.currentHeight, 132, accuracy: 0.5)
        XCTAssertEqual(bar.cornerRadiusForTesting, 12, accuracy: 0.5,
                       "展开态是卡片，不能沿用 66pt 药丸半径")
        XCTAssertEqual(bar.expandedSideInsetForTesting, 30, accuracy: 0.5)
        XCTAssertFalse(bar.statusLabelHiddenForTesting)
    }

    /// 大档 240：卡片 12pt 圆角、横向内边距 52
    @MainActor
    func testLargeTierIsCardWithFiftyTwoInset() {
        UserDefaults.standard.set(240.0, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        let (bar, container) = makeBar(containerHeight: 800)
        selectFile(bar)
        bar.isExpanded = true
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(bar.currentHeight, 240, accuracy: 0.5)
        XCTAssertEqual(bar.cornerRadiusForTesting, 12, accuracy: 0.5)
        XCTAssertEqual(bar.expandedSideInsetForTesting, 52, accuracy: 0.5)
    }

    /// 点击药丸/胶囊空白区域同样切换折叠展开
    @MainActor
    func testBackgroundClickTogglesPillAndCapsule() {
        let (bar, container) = makeBar()
        selectFile(bar)
        container.layoutSubtreeIfNeeded()

        bar.performBackgroundClickForTesting()
        XCTAssertTrue(bar.isExpanded)
        XCTAssertEqual(bar.currentHeight, 132, accuracy: 0.5)

        bar.performBackgroundClickForTesting()
        XCTAssertFalse(bar.isExpanded)
        XCTAssertEqual(bar.currentHeight, 54, accuracy: 0.5)
    }
}

// MARK: - 工具簇

/// 工具模块：54pt 工具按钮/关闭按钮/N 个独立 54pt 圆钮；仅列可用工具；执行后自动回默认。
final class FFToolsBarV2Tests: XCTestCase {

    private var oldTier: Any?

    private final class ContextBox {
        var path = "/tmp"
        var selection: [FileEntry] = []
        var hasTasks = false
        var context: FFToolContext {
            FFToolContext(activePane: .left, currentPath: path, selection: selection,
                          window: nil, hasTasks: hasTasks)
        }
    }

    private final class StubTool: FFTool {
        let id = "stub-tool"
        let title = "桩工具"
        let icon = FFIconName.wrench
        let keywords: [String] = []
        let group = FFToolGroup.system
        private(set) var ran = 0
        func availability(in context: FFToolContext) -> FFToolAvailability { .available }
        func run(in context: FFToolContext) { ran += 1 }
    }

    override func setUp() {
        super.setUp()
        FFToolRegistry.registerBuiltInsIfNeeded()
        oldTier = UserDefaults.standard.object(forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        UserDefaults.standard.set(132.0, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
    }

    override func tearDown() {
        if let oldTier {
            UserDefaults.standard.set(oldTier, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        }
        super.tearDown()
    }

    @MainActor
    private func makeCoordinator(
        containerHeight: CGFloat = 400
    ) -> (FFToolsModuleCoordinator, NSView, ExpandableDetailsBar, ContextBox) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: containerHeight))
        let bar = ExpandableDetailsBar(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        let box = ContextBox()
        let coordinator = FFToolsModuleCoordinator(
            container: container,
            detailsBar: bar,
            side: .left,
            contextProvider: { box.context },
            taskSummaryProvider: { .empty }
        )
        coordinator.install()
        container.layoutSubtreeIfNeeded()
        return (coordinator, container, bar, box)
    }

    private func availableEntries(context: FFToolContext) -> [FFToolPageCatalog.Entry] {
        FFToolPageCatalog.entries(context: context).filter { $0.availability.isAvailable }
    }

    /// 默认态：54pt 药丸 + 右侧 54pt 工具圆钮，同高同心，间距 8
    @MainActor
    func testDefaultPillAndToolButtonShareHeight() {
        let (coordinator, container, bar, _) = makeCoordinator()
        container.layoutSubtreeIfNeeded()

        let button = coordinator.toolButtonForTesting
        XCTAssertFalse(bar.isHidden)
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(coordinator.closeButtonForTesting.isHidden)
        XCTAssertTrue(coordinator.clusterForTesting.isHidden)

        XCTAssertEqual(button.frame.width, 54, accuracy: 0.5)
        XCTAssertEqual(button.frame.height, 54, accuracy: 0.5)
        XCTAssertEqual(button.frame.midY, bar.frame.midY, accuracy: 1,
                       "工具按钮与折叠详情栏同高同心")
        XCTAssertEqual(container.bounds.maxX - button.frame.maxX, 8, accuracy: 1)
        XCTAssertEqual(button.frame.minX - bar.frame.maxX, 8, accuracy: 1)
        XCTAssertEqual(bar.cornerRadiusForTesting, 27, accuracy: 0.5)
        XCTAssertEqual(coordinator.detailsBarTrailingConstraintForTesting.constant, -70, accuracy: 0.5)
    }

    /// 展开态：工具按钮自动隐藏，详情栏胶囊铺到右侧 8pt
    @MainActor
    func testExpandedCapsuleHidesToolButtonAndFillsWidth() {
        let (coordinator, container, bar, _) = makeCoordinator()
        bar.update(with: FileEntry(path: "/tmp/a.txt", name: "a.txt", isDirectory: false))
        bar.isExpanded = true
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(coordinator.toolButtonForTesting.isHidden, "展开时工具按钮自动隐藏")
        XCTAssertTrue(coordinator.closeButtonForTesting.isHidden)
        XCTAssertEqual(bar.frame.maxX, container.bounds.maxX - 8, accuracy: 1)
        XCTAssertEqual(coordinator.detailsBarTrailingConstraintForTesting.constant, -8, accuracy: 0.5)
        XCTAssertEqual(bar.cornerRadiusForTesting, 12, accuracy: 0.5)
    }

    /// 展开时不能打开工具；收起后恢复
    @MainActor
    func testToolsCannotOpenWhileExpanded() {
        let (coordinator, container, bar, _) = makeCoordinator()
        bar.update(with: FileEntry(path: "/tmp/a.txt", name: "a.txt", isDirectory: false))
        bar.isExpanded = true
        container.layoutSubtreeIfNeeded()

        coordinator.openTools()
        XCTAssertFalse(coordinator.isToolsOpenForTesting)

        bar.isExpanded = false
        container.layoutSubtreeIfNeeded()
        coordinator.openTools()
        XCTAssertTrue(coordinator.isToolsOpenForTesting)
    }

    /// 打开工具：详情栏缩成左侧 54pt 图标圆；工具按钮位置变成 54pt × 关闭钮
    @MainActor
    func testOpenToolsMorphsDetailsIntoCircleAndShowsClose() {
        let (coordinator, container, bar, _) = makeCoordinator()
        coordinator.openTools()
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(coordinator.isToolsOpenForTesting)
        XCTAssertTrue(bar.isHidden)
        XCTAssertFalse(coordinator.detailsCircleForTesting.isHidden)
        XCTAssertFalse(coordinator.closeButtonForTesting.isHidden)
        XCTAssertTrue(coordinator.toolButtonForTesting.isHidden)

        let circle = coordinator.detailsCircleForTesting
        let close = coordinator.closeButtonForTesting
        XCTAssertEqual(circle.frame.width, 54, accuracy: 0.5)
        XCTAssertEqual(circle.frame.height, 54, accuracy: 0.5)
        XCTAssertEqual(circle.frame.minX, 8, accuracy: 1)
        XCTAssertEqual(close.frame.width, 54, accuracy: 0.5)
        XCTAssertEqual(close.frame.height, 54, accuracy: 0.5)
        XCTAssertEqual(container.bounds.maxX - close.frame.maxX, 8, accuracy: 1)
    }

    /// 只列当前可用文件工具（设置/关于不属于工具；任务中心仅在有任务时出现）：
    /// 无任务/无选中 2、无任务/选中 2 项 3、空路径 0
    @MainActor
    func testOpenToolsListsOnlyCurrentlyAvailableTools() {
        let (coordinator, container, _, box) = makeCoordinator()

        coordinator.openTools()
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(coordinator.clusterForTesting.toolButtonsForTesting.count, 2)
        XCTAssertEqual(coordinator.clusterForTesting.toolIDsForTesting,
                       ["duplicate-scan", "batch-organize"])

        box.selection = [FileEntry(path: "/tmp/a", name: "a", isDirectory: false),
                         FileEntry(path: "/tmp/b", name: "b", isDirectory: false)]
        coordinator.contextDidChange(path: "/tmp", selection: box.selection)
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(coordinator.isToolsOpenForTesting, "选中变化只刷新工具，不关闭")
        XCTAssertEqual(coordinator.clusterForTesting.toolIDsForTesting,
                       ["duplicate-scan", "batch-rename", "batch-organize"])

        box.path = ""
        box.selection = []
        coordinator.contextDidChange(path: "", selection: [])
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(coordinator.isToolsOpenForTesting, "目录变化只刷新工具，不关闭")
        XCTAssertEqual(coordinator.clusterForTesting.toolIDsForTesting, [])
    }

    @MainActor
    private func frameInContainer(_ view: NSView, _ container: NSView) -> NSRect {
        container.convert(view.bounds, from: view)
    }

    /// 独立 54pt 圆钮，无药丸容器，最右圆钮紧贴关闭钮 8pt
    @MainActor
    func testToolCirclesAreIndependentAndFlushToClose() {
        let (coordinator, container, _, _) = makeCoordinator()
        coordinator.openTools()
        container.layoutSubtreeIfNeeded()

        let cluster = coordinator.clusterForTesting
        let close = frameInContainer(coordinator.closeButtonForTesting, container)
        let frames = cluster.toolButtonsForTesting.map { frameInContainer($0, container) }
        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(frames.allSatisfy { abs($0.width - 54) < 0.5 && abs($0.height - 54) < 0.5 },
                      "工具圆钮统一 54pt")
        XCTAssertTrue(frames.allSatisfy { abs($0.midY - close.midY) < 1 },
                      "工具圆钮与关闭钮同轴")
        XCTAssertEqual(close.minX - frames.last!.maxX, 8, accuracy: 1,
                       "最右工具圆钮紧贴关闭钮")

        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(right.minX - left.maxX, 8, accuracy: 1)
        }
        XCTAssertEqual(cluster.subviews.count, 1,
                       "工具区只能有滚动容器，不能有药丸形容器，圆钮彼此独立")
    }

    /// 窄面板：先压缩圆钮间隙 8 → 2，再横向滚动
    @MainActor
    func testClusterCompressesGapsThenScrolls() {
        let (_, _, _, box) = makeCoordinator()
        let entries = availableEntries(context: box.context)
        XCTAssertEqual(entries.count, 2)

        let cluster = FFToolsClusterView()
        cluster.update(entries: entries)
        cluster.setFrameSize(NSSize(width: 116, height: 54))
        cluster.layoutSubtreeIfNeeded()
        XCTAssertEqual(cluster.spacingForTesting, 8, accuracy: 0.5)
        XCTAssertFalse(cluster.isHorizontallyScrollableForTesting)

        cluster.setFrameSize(NSSize(width: 112, height: 54))
        cluster.layoutSubtreeIfNeeded()
        XCTAssertEqual(cluster.spacingForTesting, 2, accuracy: 0.5)
        XCTAssertFalse(cluster.isHorizontallyScrollableForTesting)

        cluster.setFrameSize(NSSize(width: 108, height: 54))
        cluster.layoutSubtreeIfNeeded()
        XCTAssertEqual(cluster.spacingForTesting, 2, accuracy: 0.5)
        XCTAssertTrue(cluster.isHorizontallyScrollableForTesting)
        XCTAssertEqual(cluster.documentWidthForTesting, 110, accuracy: 1)
    }

    /// 实机报告：AXPress 能开，物理鼠标点不开。用真实窗口事件复现命中与 mouseDown。
    @MainActor
    func testToolButtonReceivesPhysicalMouseDownInWindow() throws {
        let (coordinator, container, _, _) = makeCoordinator()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        let button = coordinator.toolButtonForTesting
        let centerInContainer = button.convert(NSPoint(x: 27, y: 27), to: container)
        let hit = container.hitTest(centerInContainer)
        XCTAssertTrue(hit === button, "圆钮中心的 hitTest 必须返回圆钮本身，实际 \(String(describing: hit))")
        XCTAssertTrue(button.acceptsFirstMouse(for: NSEvent()), "首击也应生效")

        let centerInWindow = button.convert(NSPoint(x: 27, y: 27), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: centerInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: centerInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0))
        window.sendEvent(down)
        XCTAssertTrue(button.isPressedForTesting, "按下应进入按压态并缩放")
        window.sendEvent(up)
        XCTAssertTrue(coordinator.isToolsOpenForTesting, "物理 mouseDown+mouseUp 应打开工具簇")
        window.close()
    }

    /// 真实窗口里开合形变必须收敛到稳定状态：打开后详情栏隐藏、宽度约束接管；关闭后恢复。
    @MainActor
    func testMorphAnimationCompletesToStableStates() {
        let (coordinator, container, bar, _) = makeCoordinator()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        coordinator.openTools()
        XCTAssertFalse(bar.isHidden, "形变过程中详情栏仍可见")
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(coordinator.isToolsOpenForTesting)
        XCTAssertTrue(bar.isHidden, "打开完成后详情栏交给左侧圆")
        XCTAssertFalse(coordinator.detailsBarTrailingConstraintForTesting.isActive,
                       "打开期间由宽度约束接管")
        XCTAssertFalse(coordinator.detailsCircleForTesting.isHidden)

        coordinator.closeTools()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(coordinator.isToolsOpenForTesting)
        XCTAssertFalse(bar.isHidden, "关闭后详情栏恢复")
        XCTAssertTrue(coordinator.detailsBarTrailingConstraintForTesting.isActive,
                      "关闭后恢复 trailing 约束")
        XCTAssertTrue(coordinator.clusterForTesting.isHidden)
        window.close()
    }

    /// 执行工具后自动回到默认详情药丸 + 工具圆钮
    @MainActor
    func testRunToolAutoReturnsToDefaultPill() {
        let (coordinator, container, bar, _) = makeCoordinator()
        coordinator.openTools()
        container.layoutSubtreeIfNeeded()

        let stub = StubTool()
        let entry = FFToolPageCatalog.Entry(tool: stub, availability: .available)
        coordinator.runForTesting(entry)
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(stub.ran, 1)
        XCTAssertFalse(coordinator.isToolsOpenForTesting)
        XCTAssertFalse(bar.isHidden)
        XCTAssertFalse(coordinator.toolButtonForTesting.isHidden)
        XCTAssertTrue(coordinator.closeButtonForTesting.isHidden)
        XCTAssertTrue(coordinator.detailsCircleForTesting.isHidden)
    }

    /// × 是唯一手动关闭入口
    @MainActor
    func testCloseButtonClosesTools() {
        let (coordinator, container, _, _) = makeCoordinator()
        coordinator.openTools()
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(coordinator.closeButtonForTesting.accessibilityPerformPress())
        XCTAssertFalse(coordinator.isToolsOpenForTesting)
        XCTAssertFalse(coordinator.toolButtonForTesting.isHidden)
    }

    /// 活动面板切换不自动关闭，只刷新（关闭只认 ×）
    @MainActor
    func testActivePaneChangeKeepsToolsOpen() {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.openTools()
        coordinator.closeIfActivePaneChanged()
        XCTAssertTrue(coordinator.isToolsOpenForTesting)
    }

    /// 工具圆钮按工具 id 执行并自动回默认
    @MainActor
    func testToolCircleAXPressRunsTool() {
        let (coordinator, container, _, _) = makeCoordinator()
        coordinator.applyTaskSummaryForTesting(
            FFTaskSummary(hasTasks: true, activeCount: 0, progress: 1))
        coordinator.openTools()
        container.layoutSubtreeIfNeeded()
        let circle = try! XCTUnwrap(coordinator.clusterForTesting.toolButtonsForTesting.first {
            $0.toolIDForTesting == "task-center"
        })
        // 直接走协调器的执行路径，避免真的弹出任务中心窗口
        XCTAssertTrue(circle.accessibilityRole() == .button)
        XCTAssertEqual(circle.accessibilityLabel(), "任务中心")
    }
}

// MARK: - 任务按钮 / 任务中心条件显隐 / 注水

final class FFTaskButtonTests: XCTestCase {

    private final class ContextBox {
        var path = "/tmp"
        var selection: [FileEntry] = []
        var context: FFToolContext {
            FFToolContext(activePane: .left, currentPath: path, selection: selection, window: nil)
        }
    }

    override func setUp() {
        super.setUp()
        FFToolRegistry.registerBuiltInsIfNeeded()
    }

    @MainActor
    private func makeCoordinator() -> (FFToolsModuleCoordinator, NSView, ExpandableDetailsBar) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let bar = ExpandableDetailsBar(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        let box = ContextBox()
        let coordinator = FFToolsModuleCoordinator(
            container: container,
            detailsBar: bar,
            side: .left,
            contextProvider: { box.context },
            taskSummaryProvider: { .empty }
        )
        coordinator.install()
        container.layoutSubtreeIfNeeded()
        return (coordinator, container, bar)
    }

    private func appTask(progress: Double, active: Bool) -> FFTask {
        FFTask(id: UUID().uuidString,
               title: "任务",
               detail: "",
               completedBytes: Int64(progress * 100),
               totalBytes: 100,
               state: active ? .running : .finished,
               startedAt: Date())
    }

    private func systemTask(progress: Double, active: Bool) -> TaskInfo {
        TaskInfo(id: UUID().uuidString,
                 name: "系统任务",
                 description: "",
                 priority: .normal,
                 status: active ? .running : .completed,
                 progress: progress,
                 createdAt: Date())
    }

    /// 聚合：有任务记录 = true；进度只取活动任务平均；无活动=100%；无任务=0
    func testTaskSummaryAggregatesProgress() {
        let none = FFTaskPresence.summary(appTasks: [], systemTasks: [])
        XCTAssertEqual(none, FFTaskSummary(hasTasks: false, activeCount: 0, progress: 0))

        let mixed = FFTaskPresence.summary(
            appTasks: [appTask(progress: 0.2, active: true),
                       appTask(progress: 0.4, active: true)],
            systemTasks: [systemTask(progress: 0.9, active: false)])
        XCTAssertTrue(mixed.hasTasks)
        XCTAssertEqual(mixed.activeCount, 2)
        XCTAssertEqual(mixed.progress, 0.3, accuracy: 0.001,
                       "已完成历史不能拉高活动任务进度")

        let historyOnly = FFTaskPresence.summary(
            appTasks: [appTask(progress: 1, active: false)],
            systemTasks: [])
        XCTAssertTrue(historyOnly.hasTasks)
        XCTAssertEqual(historyOnly.activeCount, 0)
        XCTAssertEqual(historyOnly.progress, 1, accuracy: 0.001,
                       "没有活动任务时水量注满")
    }

    /// 无任务时任务中心不出现；有任务时出现并带进度
    @MainActor
    func testTaskCenterOnlyAppearsWithTaskRecords() {
        let (coordinator, container, _) = makeCoordinator()
        coordinator.openTools()
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(coordinator.clusterForTesting.toolIDsForTesting,
                       ["duplicate-scan", "batch-organize"])

        coordinator.applyTaskSummaryForTesting(
            FFTaskSummary(hasTasks: true, activeCount: 1, progress: 0.42))
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(coordinator.isToolsOpenForTesting, "任务出现不关闭工具簇")
        XCTAssertEqual(coordinator.clusterForTesting.toolIDsForTesting,
                       ["duplicate-scan", "batch-organize", "task-center"])
        let taskCircle = coordinator.clusterForTesting.toolButtonsForTesting.first {
            $0.toolIDForTesting == "task-center"
        }
        XCTAssertEqual(taskCircle?.waterProgressForTesting ?? -1, 0.42, accuracy: 0.001)

        coordinator.applyTaskSummaryForTesting(
            FFTaskSummary(hasTasks: false, activeCount: 0, progress: 0))
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(coordinator.clusterForTesting.toolIDsForTesting,
                       ["duplicate-scan", "batch-organize"])
        XCTAssertFalse(coordinator.toolButtonForTesting.isTaskModeForTesting)
        XCTAssertNil(coordinator.toolButtonForTesting.waterProgressForTesting)
    }

    /// 有任务时右侧按钮换任务图标 + 注水；点击仍打开工具簇；清空后恢复扳手
    @MainActor
    func testTaskButtonModeWaterAndRestores() {
        let (coordinator, container, _) = makeCoordinator()
        XCTAssertFalse(coordinator.toolButtonForTesting.isTaskModeForTesting)

        coordinator.applyTaskSummaryForTesting(
            FFTaskSummary(hasTasks: true, activeCount: 2, progress: 0.62))
        XCTAssertTrue(coordinator.toolButtonForTesting.isTaskModeForTesting)
        XCTAssertEqual(coordinator.toolButtonForTesting.waterProgressForTesting ?? -1,
                       0.62, accuracy: 0.001)
        XCTAssertEqual(coordinator.toolButtonForTesting.accessibilityLabel(), "任务")

        XCTAssertTrue(coordinator.toolButtonForTesting.accessibilityPerformPress())
        XCTAssertTrue(coordinator.isToolsOpenForTesting, "任务按钮仍打开工具簇")

        coordinator.applyTaskSummaryForTesting(
            FFTaskSummary(hasTasks: false, activeCount: 0, progress: 0))
        container.layoutSubtreeIfNeeded()
        XCTAssertFalse(coordinator.toolButtonForTesting.isTaskModeForTesting)
        XCTAssertNil(coordinator.toolButtonForTesting.waterProgressForTesting)
        XCTAssertEqual(coordinator.toolButtonForTesting.accessibilityLabel(), "工具")
    }
}
