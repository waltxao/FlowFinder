import AppKit
import XCTest
@testable import FlowFinder

final class FFRadiusTokensTests: XCTestCase {
    func testHierarchyRadii() {
        XCTAssertEqual(FFVisualTokens.Radius.window, 12)
        XCTAssertEqual(FFVisualTokens.Radius.panel, 12)
        XCTAssertEqual(FFVisualTokens.Radius.details, 12)
        XCTAssertEqual(FFVisualTokens.Radius.card, 8)
        XCTAssertEqual(FFVisualTokens.Radius.control, 6)
    }

    func testPaneUsesPanelRadius() {
        let pane = SquircleView(cornerRadius: FFVisualTokens.Radius.panel)
        pane.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        pane.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.layer?.cornerRadius, 12)
        XCTAssertEqual(pane.layer?.cornerCurve, .continuous)
    }

    func testGlassPanelUsesContinuousCurve() {
        let glass = FFGlassView(level: .panel, cornerRadius: FFVisualTokens.Radius.panel)
        glass.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        glass.layoutSubtreeIfNeeded()
        XCTAssertEqual(glass.layer?.cornerCurve, .continuous)
    }
}
