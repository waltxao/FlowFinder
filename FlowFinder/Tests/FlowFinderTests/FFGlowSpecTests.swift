import XCTest
@testable import FlowFinder

final class FFGlowSpecTests: XCTestCase {
    func testStandardValues() {
        XCTAssertEqual(FFGlowSpec.standard.blurRadius, 9)
        XCTAssertEqual(FFGlowSpec.standard.opacity, 0.50)
        XCTAssertEqual(FFGlowSpec.standard.fadeStart, 0.42)
    }

    func testBottomIsOpaqueAndTopIsInvisible() {
        XCTAssertEqual(FFGlowSpec.standard.alpha(atNormalizedY: 0), 0.50, accuracy: 0.001)
        XCTAssertEqual(FFGlowSpec.standard.alpha(atNormalizedY: 0.42), 0.50, accuracy: 0.001)
        XCTAssertEqual(FFGlowSpec.standard.alpha(atNormalizedY: 1), 0, accuracy: 0.001)
    }

    func testMidFadeIsBetween() {
        let alpha = FFGlowSpec.standard.alpha(atNormalizedY: 0.71)
        XCTAssertGreaterThan(alpha, 0)
        XCTAssertLessThan(alpha, 0.50)
    }
}
