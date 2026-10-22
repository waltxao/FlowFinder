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
        XCTAssertEqual(FFDetailsLayoutPolicy.clampedIconSize(120), 96)
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

        bar.applyPreviewIconSize(80)
        XCTAssertEqual(bar.previewIconSize, 80)
        XCTAssertEqual(bar.bigIconSizeForTesting, 80)

        bar.applyPreviewIconSize(40)
        XCTAssertEqual(bar.previewIconSize, 48)

        bar.applyPreviewIconSize(120)
        XCTAssertEqual(bar.previewIconSize, 96)
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
        XCTAssertEqual(FFDetailsLayoutPolicy.storedPreviewColumnWidth(defaults: defaults), 200)
    }

    @MainActor
    func testExpandedDefaultHeightIs132() {
        let oldHeight = UserDefaults.standard.object(forKey: "FFDetailsBarExpandedHeight")
        let oldWidth = UserDefaults.standard.object(forKey: "FFDetailsBarIconWidth")
        UserDefaults.standard.set(FFDetailsLayoutPolicy.defaultExpandedHeight,
                                  forKey: "FFDetailsBarExpandedHeight")
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarIconWidth")
        defer {
            if let oldHeight {
                UserDefaults.standard.set(oldHeight, forKey: "FFDetailsBarExpandedHeight")
            } else {
                UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
            }
            if let oldWidth {
                UserDefaults.standard.set(oldWidth, forKey: "FFDetailsBarIconWidth")
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

        XCTAssertEqual(FFDetailsLayoutPolicy.storedIconSize(defaults: defaults), 96)
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
}
