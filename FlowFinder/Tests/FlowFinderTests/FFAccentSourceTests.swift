import AppKit
import XCTest
@testable import FlowFinder

final class FFAccentSourceTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "FFAccentSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testMigrationClearsLegacyAccentOnce() {
        let defaults = suite()
        defaults.set("#ff375f", forKey: FFAccent.storageKey)

        FFAccent.migrateToUnifiedAccent(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: FFAccent.storageKey))
        XCTAssertTrue(defaults.bool(forKey: FFAccent.unifiedMigrationKey))

        FFAccent.set(hex: "#bf5af2", defaults: defaults)
        FFAccent.migrateToUnifiedAccent(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: FFAccent.storageKey), "#bf5af2")
    }

    func testStaleLegacyAccentIsClearedEvenWhenMigrationKeyExists() {
        let defaults = suite()
        defaults.set(true, forKey: FFAccent.unifiedMigrationKey)
        defaults.set("#ff375f", forKey: FFAccent.storageKey)

        FFAccent.migrateToUnifiedAccent(defaults: defaults)

        XCTAssertNil(defaults.string(forKey: FFAccent.storageKey))
    }

    func testExplicitAccentSurvivesMigration() {
        let defaults = suite()
        FFAccent.set(hex: "#bf5af2", defaults: defaults)

        FFAccent.migrateToUnifiedAccent(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: FFAccent.storageKey), "#bf5af2")
    }

    func testResolvedHexFallsBackToSystemAccent() {
        XCTAssertEqual(FFAccent.resolvedHex(forStoredHex: nil), FFAccent.systemHex)
        XCTAssertEqual(FFAccent.resolvedHex(forStoredHex: "#bf5af2"), "#bf5af2")
    }

    func testCustomColorIsParsed() {
        let color = FFAccent.color(forStoredHex: "#ff375f")
        XCTAssertEqual(color.ffHexString, "ff375f")
    }
}
