import AppKit
import XCTest
@testable import FlowFinder

final class FFAccentSelectionTests: XCTestCase {
    func testTabUnderlineUsesApplicationAccent() {
        XCTAssertEqual(FFVisualTokens.tabUnderlineColor.ffHexString,
                       FFAccent.current.ffHexString)
    }

    func testTokenAccentUsesApplicationAccent() {
        XCTAssertEqual(FFVisualTokens.accent.ffHexString,
                       FFAccent.current.ffHexString)
    }
}
