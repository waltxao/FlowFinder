import AppKit
import XCTest
@testable import FlowFinder

/// 详情栏重做（2026-10-23）策略与行为回归。
/// 覆盖：三档吸附 / 点击回上次档 / 图标边长三角夹紧 / 滚动列数 / 全部行可达 / 换行。
final class FFDetailsBarV2Tests: XCTestCase {

    // MARK: - 三档与吸附

    func testTierSnappingUsesMidpoints() {
        XCTAssertEqual(FFDetailsLayoutPolicy.snapTier(forHeight: 92, paneHeight: 900), .collapsed)
        XCTAssertEqual(FFDetailsLayoutPolicy.snapTier(forHeight: 93, paneHeight: 900), .standard)
        XCTAssertEqual(FFDetailsLayoutPolicy.snapTier(forHeight: 185, paneHeight: 900), .standard)
        XCTAssertEqual(FFDetailsLayoutPolicy.snapTier(forHeight: 186, paneHeight: 900), .large)
    }

    func testLargeTierClampedByPaneHeight() {
        XCTAssertEqual(FFDetailsLayoutPolicy.largeTierHeight(forPaneHeight: 400), 180)
        XCTAssertEqual(FFDetailsLayoutPolicy.largeTierHeight(forPaneHeight: 900), 240)
    }

    func testClickReturnsToLastExpandedTier() {
        var state = FFDetailsBarTierState(tier: .collapsed, lastExpanded: .standard)
        XCTAssertEqual(state.click(), .standard)
        XCTAssertEqual(state.click(), .collapsed)

        state = FFDetailsBarTierState(tier: .large, lastExpanded: .large)
        XCTAssertEqual(state.click(), .collapsed)
        XCTAssertEqual(state.click(), .large, "从大档收起后，再点应回到大档")
    }

    func testSnapStateRemembersLargeTier() {
        var state = FFDetailsBarTierState(tier: .collapsed, lastExpanded: .standard)
        XCTAssertEqual(state.snap(to: 200, paneHeight: 900), .large)
        XCTAssertEqual(state.lastExpanded, .large)
        XCTAssertEqual(state.click(), .collapsed)
        XCTAssertEqual(state.click(), .large)
    }

    // MARK: - 图标尺寸

    func testIconEdgeClampedByTierHeightAndWidth() {
        // 132 档：内容高 100，上下留白 8 → 上限 92
        XCTAssertEqual(FFDetailsLayoutPolicy.iconEdge(setting: 200, columnWidth: 232, contentHeight: 100), 92)
        // 240 档：内容高 216 → 上限 200
        XCTAssertEqual(FFDetailsLayoutPolicy.iconEdge(setting: 200, columnWidth: 232, contentHeight: 216), 200)
        // 列宽限制：132 − 32 = 100
        XCTAssertEqual(FFDetailsLayoutPolicy.iconEdge(setting: 200, columnWidth: 132, contentHeight: 300), 100)
        // 下限 48
        XCTAssertEqual(FFDetailsLayoutPolicy.iconEdge(setting: 20, columnWidth: 232, contentHeight: 300), 48)
    }

    func testIconColumnFollowsEdgeAndCapsAt232() {
        XCTAssertEqual(FFDetailsLayoutPolicy.iconColumnWidth(forEdge: 48), 132)
        XCTAssertEqual(FFDetailsLayoutPolicy.iconColumnWidth(forEdge: 100), 132)
        XCTAssertEqual(FFDetailsLayoutPolicy.iconColumnWidth(forEdge: 200), 232)
    }

    func testStoredIconSizeAllows200() {
        let name = "FFDetailsBarV2Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(200.0, forKey: FFUserDefaultsKeys.detailsPreviewSize)
        XCTAssertEqual(FFDetailsLayoutPolicy.storedIconSize(defaults: defaults), 200)
        defaults.set(260.0, forKey: FFUserDefaultsKeys.detailsPreviewSize)
        XCTAssertEqual(FFDetailsLayoutPolicy.storedIconSize(defaults: defaults), 200)
    }

    // MARK: - 滚动与列数

    func testScrollColumnsFollowInfoWidth() {
        XCTAssertEqual(FFDetailsLayoutPolicy.scrollColumnCount(forWidth: 339), 1)
        XCTAssertEqual(FFDetailsLayoutPolicy.scrollColumnCount(forWidth: 340), 2)
        XCTAssertEqual(FFDetailsLayoutPolicy.scrollColumnCount(forWidth: 520), 2)
        XCTAssertEqual(FFDetailsLayoutPolicy.scrollColumnCount(forWidth: 700), 3)
    }

    func testScrollLayoutKeepsEveryRow() {
        let heights = Array(repeating: CGFloat(20), count: 14)
        let narrow = FFDetailsFlowLayout.scrollLayout(itemHeights: heights, availableWidth: 300)
        XCTAssertEqual(narrow.count, 1)
        XCTAssertEqual(narrow.flatMap { $0 }.count, 14)

        let wide = FFDetailsFlowLayout.scrollLayout(itemHeights: heights, availableWidth: 700)
        XCTAssertEqual(wide.flatMap { $0 }.count, 14)
        XCTAssertGreaterThan(wide.count, 1)
    }

    func testStoredLastExpandedTierDefaultsToStandard() {
        let name = "FFDetailsBarV2Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertEqual(FFDetailsLayoutPolicy.storedLastExpandedTier(defaults: defaults), .standard)
        defaults.set(240.0, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        XCTAssertEqual(FFDetailsLayoutPolicy.storedLastExpandedTier(defaults: defaults), .large)
    }

    // MARK: - 视图行为

    @MainActor
    func testExpandedInfoScrollsInsteadOfHidingRows() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 400))
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 420, height: 132))
        container.addSubview(bar)
        bar.update(with: FileEntry(path: "/tmp/ff-scroll-demo.pdf", name: "demo.pdf", isDirectory: false))
        bar.isExpanded = true
        bar.layoutSubtreeIfNeeded()
        bar.rearrangeFlow()

        XCTAssertTrue(bar.infoScrollViewForTesting.hasVerticalScroller,
                      "信息区必须允许纵向滚动")
        let rows = bar.infoColumns.filter { !$0.isHidden }.flatMap { $0.arrangedSubviews }
        XCTAssertEqual(rows.count, 8, "所有信息行都应保留在列里，不再隐藏末行")
        XCTAssertTrue(rows.allSatisfy { !$0.isHidden })
    }

    @MainActor
    func testNameAndLocationWrapWithoutFixedWidth() {        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 400))
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 420, height: 132))
        container.addSubview(bar)
        let path = "/tmp/" + String(repeating: "很长的目录名/", count: 6) + "文件.txt"
        let name = String(repeating: "超长文件名", count: 5) + ".txt"
        bar.update(with: FileEntry(path: path, name: name, isDirectory: false))
        bar.isExpanded = true
        bar.layoutSubtreeIfNeeded()
        bar.rearrangeFlow()

        XCTAssertEqual(bar.nameFieldForTesting.maximumNumberOfLines, 0)
        XCTAssertEqual(bar.locationFieldForTesting.maximumNumberOfLines, 0)
        let available = bar.infoAreaSizeForFlow.width
        XCTAssertLessThanOrEqual(bar.nameFieldForTesting.preferredMaxLayoutWidth, available)
        XCTAssertLessThanOrEqual(bar.locationFieldForTesting.preferredMaxLayoutWidth, available)
    }

    @MainActor
    func testLargeIconAutoWidensIconColumn() {
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        bar.applyPreviewIconSize(200, persist: false)
        XCTAssertEqual(bar.bigIconSizeForTesting, 200)
        XCTAssertEqual(bar.previewColumnWidthForTesting, 232,
                       "图标 200 时图标区应自动加宽到 232")
    }

    @MainActor
    func testScrollerAndContentInsetsFollowBarHeight() {
        let list = FileListView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        list.setBottomOverlayInset(132)
        XCTAssertEqual(list.bottomOverlayInsetForTesting, 140, accuracy: 0.5,
                       "内容底部应让开栏高 + 8pt 浮层边距")
        XCTAssertEqual(list.scrollerBottomInsetForTesting, 140, accuracy: 0.5,
                       "滚动条轨道也应止于栏顶（D-01 C）")

        let grid = FileGridView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        grid.setBottomOverlayInset(240)
        XCTAssertEqual(grid.scrollerBottomInsetForTesting, 248, accuracy: 0.5)
    }
}
