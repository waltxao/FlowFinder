import XCTest
@testable import FlowFinder

final class FFShortcutSettingsTests: XCTestCase {

    func testDefaultsComeFromKeyboardContract() {
        XCTAssertEqual(FFShortcutSettings.defaultDisplay(for: FFUserDefaultsKeys.shortcutNewFolder), "⌘⇧N")
        XCTAssertEqual(FFShortcutSettings.defaultDisplay(for: FFUserDefaultsKeys.shortcutCloseWindow), "⌘⇧W")
        XCTAssertEqual(FFShortcutSettings.defaultDisplay(for: FFUserDefaultsKeys.shortcutDuplicateScan), "⌘⇧D")
        XCTAssertEqual(FFShortcutSettings.defaultDisplay(for: FFUserDefaultsKeys.shortcutListView), "⌥⌘1")
    }

    func testConflictDetectsOverrideAgainstDefaultAndStored() {
        let conflict = FFShortcutSettings.conflict(
            for: "⌘F",
            storageKey: FFUserDefaultsKeys.shortcutNewFolder,
            stored: [:]
        )
        XCTAssertEqual(conflict, FFUserDefaultsKeys.shortcutSearch)

        let storedCustom = [FFUserDefaultsKeys.shortcutRefresh: "⌘R",
                            FFUserDefaultsKeys.shortcutTaskPanel: "⌘R"]
        XCTAssertEqual(
            FFShortcutSettings.conflict(for: "⌘R",
                                        storageKey: FFUserDefaultsKeys.shortcutRefresh,
                                        stored: storedCustom),
            FFUserDefaultsKeys.shortcutTaskPanel
        )
    }

    func testNoConflictForSameKeyOrEmptyValue() {
        XCTAssertNil(FFShortcutSettings.conflict(for: "⌘R",
                                                 storageKey: FFUserDefaultsKeys.shortcutRefresh,
                                                 stored: [:]))
        XCTAssertNil(FFShortcutSettings.conflict(for: "",
                                                 storageKey: FFUserDefaultsKeys.shortcutRefresh,
                                                 stored: [:]))
    }

    func testEveryCustomizableShortcutHasDisplayAndTitle() {
        for key in FFUserDefaultsKeys.allShortcutKeys {
            XCTAssertNotNil(FFShortcutSettings.defaultDisplay(for: key), "missing default for \(key)")
            XCTAssertNotEqual(FFShortcutSettings.title(for: key), key, "missing title for \(key)")
        }
    }
}
