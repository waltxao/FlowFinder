import AppKit
import XCTest
@testable import FlowFinder

final class FFKeyboardContractTests: XCTestCase {
    func testFinderCanonicalShortcuts() {
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .newWindow).display, "⌘N")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .newFolder).display, "⌘⇧N")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .moveToTrash).display, "⌘⌫")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .rename).display, "Return")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .closeTab).display, "⌘W")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .closeWindow).display, "⌘⇧W")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .focusLeft).display, "⌘1")
        XCTAssertEqual(FFKeyboardContract.shortcut(for: .focusRight).display, "⌘2")
    }

    func testOverridesDetectConflict() {
        var overrides: [FFShortcutAction: FFShortcut] = [:]
        overrides[.newWindow] = FFKeyboardContract.shortcut(for: .newFolder)
        let conflicts = FFKeyboardContract.conflicts(overrides: overrides)
        XCTAssertTrue(conflicts[.newWindow]?.contains(.newFolder) ?? false)
        XCTAssertTrue(conflicts[.newFolder]?.contains(.newWindow) ?? false)
    }
}
