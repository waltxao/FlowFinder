import AppKit
import XCTest
@testable import FlowFinder

/// 第四轮审计 R4-12：批量重命名窗口
/// ①预览表数据行下方固定 7 条空行条纹，像可点的空行；
/// ②冲突只有红字，没有原因、没有图例、没有筛选；
/// ③默认前缀 IMG_ 凭空出现；
/// ④`{name}.{ext}` 后面再接文字会静默产出伪扩展名；
/// ⑤跨目录选择时冲突只按第一个文件的目录判定。
final class FFBatchRenameTests: XCTestCase {

    private var tempRoot: String!

    override func setUpWithError() throws {
        tempRoot = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("ff-batchrename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        BatchRenameWindowController.shared.close()
        if let tempRoot {
            try? FileManager.default.removeItem(atPath: tempRoot)
        }
        super.tearDown()
    }

    /// 在指定目录里造一个文件，返回可直接喂给窗口的 FileEntry。
    @discardableResult
    private func makeFile(_ directory: String, _ name: String) throws -> FileEntry {
        let dir = (tempRoot as NSString).appendingPathComponent(directory)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent(name)
        try Data("x".utf8).write(to: URL(fileURLWithPath: path))
        return FileEntry(path: path, name: name, isDirectory: false)
    }

    /// 走真实的 target/action 连线提交输入，而不是直接调内部方法。
    private func fire(_ control: NSControl) {
        guard let action = control.action else { return }
        NSApp.sendAction(action, to: control.target, from: control)
    }

    private func present(_ entries: [FileEntry], pattern: String? = nil) throws -> BatchRenameWindowController {
        let controller = BatchRenameWindowController.shared
        controller.showWindow(selectedFiles: entries, paneViewModel: nil)
        if let pattern {
            let field = try XCTUnwrap(controller.patternFieldForTesting)
            field.stringValue = pattern
            fire(field)
        }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        return controller
    }

    // MARK: - ① 空行条纹

    @MainActor
    func testPreviewTableHasNoPhantomRowStripes() throws {
        let table = try XCTUnwrap(BatchRenameWindowController.shared.previewTableForTesting)
        XCTAssertFalse(table.usesAlternatingRowBackgroundColors,
                       "交替行底色会在数据行下方继续画出条纹，看起来像 7 个空行（R4-12）")
        XCTAssertTrue(table.gridStyleMask.contains(.solidHorizontalGridLineMask),
                      "取消条纹后要用横向分隔线保持可读性")
    }

    // MARK: - ③ 默认前缀

    @MainActor
    func testPrefixFieldStartsEmpty() throws {
        let field = try XCTUnwrap(BatchRenameWindowController.shared.prefixFieldForTesting)
        XCTAssertEqual(field.stringValue, "",
                       "凭空写死的 IMG_ 会把所有人的文件名吃掉（R4-12）")
        XCTAssertFalse(field.placeholderString?.isEmpty ?? true, "空字段要有占位提示")
    }

    // MARK: - ② 冲突原因

    @MainActor
    func testConflictCarriesAReasonAndIsBlocking() throws {
        let controller = try present([try makeFile("a", "one.txt"),
                                      try makeFile("a", "two.txt")], pattern: "same")

        let reason = try XCTUnwrap(controller.conflictReason(at: 0))
        XCTAssertFalse(reason.isEmpty, "两行新名称相同必须说明撞了谁（R4-12）")
        XCTAssertEqual(controller.conflictReason(at: 1), reason,
                       "同一场冲突的两行要给出一致的原因，不能一行有一句")
        XCTAssertFalse(controller.renameButtonForTesting?.isEnabled ?? true,
                       "有冲突时不允许执行")

        let table = try XCTUnwrap(controller.previewTableForTesting)
        let column = try XCTUnwrap(table.tableColumns.first { $0.identifier.rawValue == "new" })
        let cell = try XCTUnwrap(controller.tableView(table, viewFor: column, row: 0) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.toolTip, reason,
                       "红字之外还要在 tooltip 里写清原因，否则用户不知道该改哪里")
    }

    // MARK: - ⑤ 跨目录冲突

    @MainActor
    func testCrossDirectorySelectionChecksEachDirectory() throws {
        // a 目录里有一个没被选中的 blocker.txt；b 目录没有同名文件。
        try makeFile("a", "blocker.txt")
        let controller = try present([try makeFile("a", "one.txt"),
                                      try makeFile("b", "one.txt")], pattern: "blocker.txt")

        XCTAssertNotNil(controller.conflictReason(at: 0),
                        "a/one→blocker.txt 撞上 a 目录已有的 blocker.txt，必须报冲突")
        XCTAssertNil(controller.conflictReason(at: 1),
                     "b 目录里没有 blocker.txt，不该被 a 目录的判定连坐（R4-12 跨目录误报）")
    }

    // MARK: - ④ 伪扩展名

    @MainActor
    func testExtensionRewriteIsWarnedButNotBlocked() throws {
        let controller = try present([try makeFile("a", "script.py")], pattern: "{name}.{ext}areadme")

        let warning = try XCTUnwrap(controller.extensionWarning(at: 0))
        XCTAssertTrue(warning.contains("pyareadme"),
                      "提示要写明会变成什么扩展名：\(warning)")
        XCTAssertNil(controller.conflictReason(at: 0),
                     "改扩展名不是错误，只提示，不拦下重命名")
        XCTAssertTrue(controller.renameButtonForTesting?.isEnabled ?? false,
                      "只有警告时仍然允许执行")
    }

    // MARK: - ② 只看冲突

    @MainActor
    func testConflictFilterShowsOnlyConflictingRows() throws {
        // {index} 让两行分别变成 1、2；目录里已有 1，所以第一行冲突、第二行干净。
        try makeFile("a", "1")
        let controller = try present([try makeFile("a", "one.txt"),
                                      try makeFile("a", "two.txt")], pattern: "{index}")
        let table = try XCTUnwrap(controller.previewTableForTesting)
        XCTAssertEqual(table.numberOfRows, 2, "默认不过滤：整表都在，用户才改得完")

        let toggle = try XCTUnwrap(controller.onlyConflictsSwitchForTesting)
        toggle.state = .on
        fire(toggle)
        XCTAssertEqual(table.numberOfRows, 1, "过滤态下只留冲突行")
        let column = try XCTUnwrap(table.tableColumns.first { $0.identifier.rawValue == "old" })
        let cell = try XCTUnwrap(controller.tableView(table, viewFor: column, row: 0) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, "one.txt", "留下的必须就是那行冲突")

        toggle.state = .off
        fire(toggle)
        XCTAssertEqual(table.numberOfRows, 2, "关掉过滤要恢复全部行")
    }

    /// 勾选「只看冲突」却一场冲突都没有时，表格会整片空掉——图例必须说明这是「无冲突」，
    /// 否则空表看起来又像一次静默失效（R4-12 实测补充）。
    @MainActor
    func testLegendStatesConflictCount() throws {
        let controller = try present([try makeFile("a", "one.txt"),
                                      try makeFile("a", "two.txt")], pattern: "{name}")
        let legend = try XCTUnwrap(controller.conflictLegendForTesting)
        XCTAssertTrue(legend.stringValue.contains("无冲突"),
                      "没有冲突时图例要给出结论，而不是只留颜色说明：\(legend.stringValue)")

        let field = try XCTUnwrap(controller.patternFieldForTesting)
        field.stringValue = "same"
        fire(field)
        XCTAssertTrue(legend.stringValue.contains("2 处冲突"),
                      "有冲突时图例要报出数量，用户才知道要处理几行：\(legend.stringValue)")
    }

    /// 实测补充：图例文案变长后，标签的抗压缩优先级会把整条按钮栏顶出可视区——
    /// 窗口看起来正常，但「重命名/取消/只看冲突」全部点不到，属于最恶劣的静默失效。
    @MainActor
    func testBottomBarStaysVisibleAtMinimumWidth() throws {
        let controller = try present([try makeFile("a", "one.txt"),
                                      try makeFile("a", "two.txt")], pattern: "same")
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 560, height: 400))
        window.contentView?.layoutSubtreeIfNeeded()

        let buttonBar = try XCTUnwrap(controller.renameButtonForTesting?.superview)
        let barFrame = buttonBar.convert(buttonBar.bounds, to: nil)
        let height = window.contentLayoutRect.height
        XCTAssertGreaterThanOrEqual(barFrame.minY, 0,
                                    "按钮栏被顶到窗口下方不可见处：\(barFrame.minY) / 高 \(height)")
        XCTAssertLessThanOrEqual(barFrame.maxY, height + 1,
                                  "按钮栏超出可视区：\(barFrame.maxY) > \(height)")
        XCTAssertGreaterThanOrEqual(window.frame.width, 560, "窗口不应被约束挤到小于最小宽度")
    }

    /// 截图取证时这条栏反复“看不见”，而 AX 报出的坐标是对的——所以用视图自绘的位图来判定，
    /// 不受窗口遮挡与窗口服务器合成影响：按钮栏矩形内必须画得出多种颜色（文字、描边）。
    @MainActor
    func testBottomBarControlsArePainted() throws {
        let controller = try present([try makeFile("a", "one.txt"),
                                      try makeFile("a", "two.txt")], pattern: "same")
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 700, height: 552))
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()

        let buttonBar = try XCTUnwrap(controller.renameButtonForTesting?.superview)
        let barRect = content.convert(buttonBar.bounds, from: buttonBar)

        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            return XCTFail("无法把 contentView 缓存成位图")
        }
        content.cacheDisplay(in: content.bounds, to: rep)

        var colors = Set<[Int]>()
        let top = content.bounds.height - barRect.maxY   // 位图原点在左上
        for y in Int(top.rounded())...Int((content.bounds.height - barRect.minY).rounded() - 1) {
            for x in Int(barRect.minX.rounded())..<Int(barRect.maxX.rounded()) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                colors.insert([Int((c.redComponent * 255).rounded()),
                               Int((c.greenComponent * 255).rounded()),
                               Int((c.blueComponent * 255).rounded())])
            }
        }
        XCTAssertGreaterThan(colors.count, 3,
                             "按钮栏整条是纯色：图例、「只看冲突」、「重命名/取消」都没画出来（\(colors.count) 种颜色）")
    }

    /// R4-32（F11-2 遗留）：layer 只吃 CGColor 快照。把动态色在构建时解析一次钉到
    /// `contentView.layer.backgroundColor` 上，主题切换后窗口背景不跟着变——
    /// 深色模式下整条底部留白带实测停在 Aqua 纯白 255,255,255。
    @MainActor
    func testWindowBackgroundFollowsLiveThemeSwitch() throws {
        let controller = try present([try makeFile("a", "one.txt")], pattern: "{name}.{ext}")
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)

        guard let light = paintedBackground(of: content, in: .aqua),
              let dark = paintedBackground(of: content, in: .darkAqua) else {
            return  // 没有冻结的 layer 色：背景由窗口的动态 backgroundColor 提供
        }
        XCTAssertNotEqual(light, dark,
                          "窗口背景被钉死在构建时的外观上：浅色与深色实测同为 \(dark)")
        XCTAssertEqual(dark, expectedWindowBackground(in: .darkAqua),
                       "切到深色后窗口背景应是深色 windowBackgroundColor，实测 \(dark)")
    }

    private func paintedBackground(of view: NSView, in name: NSAppearance.Name) -> [Int]? {
        view.window?.appearance = NSAppearance(named: name)
        view.needsDisplay = true
        view.displayIfNeeded()
        guard var color = view.layer?.backgroundColor else { return nil }
        return rgb(&color)
    }

    private func expectedWindowBackground(in name: NSAppearance.Name) -> [Int] {
        let appearance = NSAppearance(named: name)!
        var color = CGColor(gray: 0, alpha: 1)
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.cgColor
        }
        var mutable = color
        return rgb(&mutable)
    }

    private func rgb(_ color: inout CGColor) -> [Int] {
        guard let converted = color.converted(to: CGColorSpaceCreateDeviceRGB(),
                                              intent: .defaultIntent, options: nil),
              let components = converted.components else { return [] }
        return components.prefix(3).map { Int(($0 * 255).rounded()) }
    }
}
