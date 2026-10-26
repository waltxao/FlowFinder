import AppKit
import XCTest
@testable import FlowFinder

final class FFDetailsLayoutTests: XCTestCase {
    func testColumnsSwitchAt480() {
        XCTAssertEqual(FFDetailsLayoutPolicy.columns(forWidth: 479), 1)
        XCTAssertEqual(FFDetailsLayoutPolicy.columns(forWidth: 480), 2)
        XCTAssertEqual(FFDetailsLayoutPolicy.columns(forWidth: 800), 2)
    }

    func testExpandedHeightClamp() {
        XCTAssertEqual(FFDetailsLayoutPolicy.maxExpandedHeight(forPaneHeight: 200), 132)
        XCTAssertEqual(FFDetailsLayoutPolicy.maxExpandedHeight(forPaneHeight: 800), 300)
    }

    func testIconSizeClamp() {
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(40), 48)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(64), 64)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(120), 120)
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(260), 200)
    }

    func testStoredIconSizeDefaultsTo64() {
        let name = "FFDetailsLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        XCTAssertEqual(FFDetailsLayoutPolicy.storedIconSize(defaults: defaults), 64)
    }

    @MainActor
    func testDetailsBarAppliesPreviewIconSizeWithClamp() {
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 120))

        bar.applyPreviewIconSize(80, persist: false)
        XCTAssertEqual(bar.previewIconSize, 80)
        XCTAssertEqual(bar.bigIconSizeForTesting, 80)

        bar.applyPreviewIconSize(40, persist: false)
        XCTAssertEqual(bar.previewIconSize, 48)

        // 栏高 120：内容高 88，上下各留 8 → 图标显示上限 80（设定值可到 120）
        bar.applyPreviewIconSize(120, persist: false)
        XCTAssertEqual(bar.previewIconSize, 120)
        XCTAssertEqual(bar.bigIconSizeForTesting, 80)
    }

    func testPreviewColumnDefaultsTo132AndClamps() {
        let name = "FFDetailsLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertEqual(FFDetailsLayoutPolicy.storedPreviewColumnWidth(defaults: defaults), 132)
        defaults.set(80.0, forKey: "FFDetailsBarIconWidth")
        XCTAssertEqual(FFDetailsLayoutPolicy.storedPreviewColumnWidth(defaults: defaults), 132,
                       "旧默认 80 应迁移到新默认 132")
        defaults.set(260.0, forKey: "FFDetailsBarIconWidth")
        XCTAssertEqual(FFDetailsLayoutPolicy.storedPreviewColumnWidth(defaults: defaults), 232)
    }

    @MainActor
    func testExpandedDefaultHeightIs132() {
        let oldHeight = UserDefaults.standard.object(forKey: "FFDetailsBarExpandedHeight")
        let oldWidth = UserDefaults.standard.object(forKey: "FFDetailsBarIconWidth")
        let oldPreview = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.detailsPreviewSize)
        let oldTier = UserDefaults.standard.object(forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        UserDefaults.standard.set(FFDetailsLayoutPolicy.defaultExpandedHeight,
                                  forKey: "FFDetailsBarExpandedHeight")
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarIconWidth")
        UserDefaults.standard.set(Double(FFDetailsLayoutPolicy.defaultIconSize),
                                  forKey: FFUserDefaultsKeys.detailsPreviewSize)
        UserDefaults.standard.set(132.0, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
        defer {
            if let oldHeight {
                UserDefaults.standard.set(oldHeight, forKey: "FFDetailsBarExpandedHeight")
            } else {
                UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
            }
            if let oldWidth {
                UserDefaults.standard.set(oldWidth, forKey: "FFDetailsBarIconWidth")
            }
            if let oldPreview {
                UserDefaults.standard.set(oldPreview, forKey: FFUserDefaultsKeys.detailsPreviewSize)
            } else {
                UserDefaults.standard.removeObject(forKey: FFUserDefaultsKeys.detailsPreviewSize)
            }
            if let oldTier {
                UserDefaults.standard.set(oldTier, forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
            } else {
                UserDefaults.standard.removeObject(forKey: FFDetailsLayoutPolicy.lastExpandedTierKey)
            }
        }
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        bar.isExpanded = true
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.currentHeight, 132, accuracy: 1)
        XCTAssertEqual(bar.previewColumnWidthForTesting, 132, accuracy: 1)
    }

    func testZipEntryCountReadsCentralDirectory() throws {
        let dir = URL(fileURLWithPath: "/tmp/ff-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try Data("b".utf8).write(to: dir.appendingPathComponent("b.txt"))
        let archive = dir.appendingPathComponent("archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", archive.path, "a.txt", "b.txt"]
        process.currentDirectoryURL = dir
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(FFArchiveInfo.zipEntryCount(path: archive.path), 2)
    }

    func testStoredIconSizeClampsOutOfRangeValue() {
        let name = "FFDetailsLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(180.0, forKey: FFUserDefaultsKeys.detailsPreviewSize)

        XCTAssertEqual(FFDetailsLayoutPolicy.storedIconSize(defaults: defaults), 180)
        defaults.set(260.0, forKey: FFUserDefaultsKeys.detailsPreviewSize)
        XCTAssertEqual(FFDetailsLayoutPolicy.storedIconSize(defaults: defaults), 200)
    }

    @MainActor
    func testLocationClickCopiesPath() {
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let path = "/tmp/ff-location-\(UUID().uuidString)"
        bar.update(with: FileEntry(path: path, name: "demo.txt", isDirectory: false))
        NSPasteboard.general.clearContents()
        _ = bar.perform(NSSelectorFromString("copyLocationPath"))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), path)
    }

    /// F-02 回归：流动重排只能用详情栏自身推导的可用尺寸。
    /// 真实运行里重排发生在布局遍历之内，信息区/clip 等子视图还停在折叠态的 30pt，
    /// 按子视图高度分配会让每列只排 1 行，且遍历结束后不会再触发自愈重排。
    /// 这里刻意不 flush 布局，直接调用 rearrangeFlow 复现「子视图尚未重排」的时刻。
    @MainActor
    func testExpandedDetailsFlowFitsAllRowsIntoVisibleHeight() {
        let oldHeight = UserDefaults.standard.object(forKey: "FFDetailsBarExpandedHeight")
        UserDefaults.standard.set(FFDetailsLayoutPolicy.defaultExpandedHeight,
                                  forKey: "FFDetailsBarExpandedHeight")
        defer {
            if let oldHeight {
                UserDefaults.standard.set(oldHeight, forKey: "FFDetailsBarExpandedHeight")
            } else {
                UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
            }
        }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        // 栏按展开态尺寸挂载；子视图未参与布局，frame 仍是初始化值
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 132))
        container.addSubview(bar)
        bar.update(with: FileEntry(path: "/tmp/ff-flow-demo.pdf",
                                   name: "demo.pdf",
                                   isDirectory: false))
        bar.isExpanded = true

        XCTAssertEqual(bar.infoAreaSizeForFlow.height, 132 - 14 - 18,
                       "可用高度应由栏自身高度扣除顶部拉手区与状态栏推导")
        XCTAssertGreaterThan(bar.infoAreaSizeForFlow.width, 300,
                             "可用宽度应由栏宽度扣除左右缩进、图标区与分界线推导")

        bar.rearrangeFlow()
        let columns = bar.infoColumns.filter { !$0.isHidden }
        let visibleRows = columns.flatMap { column in
            column.arrangedSubviews.filter { !$0.isHiddenOrHasHiddenAncestor }
        }
        XCTAssertEqual(visibleRows.count, 8, "展开态应放下全部信息行")
        let tallest = columns.map { $0.fittingSize.height }.max() ?? 0
        XCTAssertLessThanOrEqual(tallest, bar.infoAreaSizeForFlow.height + 1,
                                 "行总高不得超过可用高度，否则会被裁切")
    }
}
