import AppKit
import XCTest
@testable import FlowFinder

final class FFDropResolverTests: XCTestCase {

    private final class WindowToken {}

    private var tokenA: WindowToken!
    private var tokenB: WindowToken!

    override func setUp() {
        super.setUp()
        tokenA = WindowToken()
        tokenB = WindowToken()
    }

    override func tearDown() {
        tokenA = nil
        tokenB = nil
        super.tearDown()
    }

    private func tabRects(x: CGFloat, y: CGFloat, widths: [CGFloat], height: CGFloat = 28) -> [CGRect] {
        var result: [CGRect] = []
        var cursor = x
        for width in widths {
            result.append(CGRect(x: cursor, y: y, width: width, height: height))
            cursor += width + 6
        }
        return result
    }

    private func geometry(
        id: ObjectIdentifier,
        frame: CGRect = CGRect(x: 0, y: 0, width: 1200, height: 900),
        single: Bool = false,
        active: PaneSide = .left,
        leftTabs: [CGRect]? = nil,
        rightTabs: [CGRect]? = nil,
        leftPane: CGRect? = nil,
        rightPane: CGRect? = nil,
        leftReal: Int = 2,
        rightReal: Int = 2,
        invalid: [CGRect] = []
    ) -> FFWindowDropGeometry {
        let lTabs = leftTabs ?? tabRects(x: 120, y: 820, widths: [100, 120])
        let rTabs = rightTabs ?? tabRects(x: 620, y: 820, widths: [100, 120])
        var strips: [PaneSide: FFTabStripGeometry] = [:]
        if single {
            let stripRect = active == .left
                ? CGRect(x: 100, y: 800, width: 460, height: 60)
                : CGRect(x: 600, y: 800, width: 460, height: 60)
            strips[active] = FFTabStripGeometry(rect: stripRect,
                                                tabRects: active == .left ? lTabs : rTabs)
        } else {
            strips[.left] = FFTabStripGeometry(rect: CGRect(x: 100, y: 800, width: 460, height: 60),
                                               tabRects: lTabs)
            strips[.right] = FFTabStripGeometry(rect: CGRect(x: 600, y: 800, width: 460, height: 60),
                                                tabRects: rTabs)
        }

        var panes: [PaneSide: FFPaneGeometry] = [:]
        if single {
            let rect = active == .left
                ? (leftPane ?? CGRect(x: 100, y: 100, width: 1000, height: 700))
                : (rightPane ?? CGRect(x: 100, y: 100, width: 1000, height: 700))
            panes[active] = FFPaneGeometry(rect: rect,
                                           realTabCount: active == .left ? leftReal : rightReal)
        } else {
            panes[.left] = FFPaneGeometry(rect: leftPane ?? CGRect(x: 100, y: 100, width: 460, height: 700),
                                          realTabCount: leftReal)
            panes[.right] = FFPaneGeometry(rect: rightPane ?? CGRect(x: 600, y: 100, width: 460, height: 700),
                                           realTabCount: rightReal)
        }

        return FFWindowDropGeometry(windowID: id,
                                    frame: frame,
                                    isSinglePane: single,
                                    activePane: active,
                                    tabStrips: strips,
                                    paneContents: panes,
                                    invalidRects: invalid)
    }

    func testSameWindowTabStripReordersAtPointerIndex() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 300, y: 830),
                                              geometries: [g])
        XCTAssertEqual(decision, .reorder(windowID: g.windowID, side: .left, index: 2))
    }

    func testSameWindowOtherTabStripMerges() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 700, y: 830),
                                              geometries: [g])
        XCTAssertEqual(decision, .merge(windowID: g.windowID, side: .right, index: 1))
    }

    func testSameWindowDoublePaneSameSideReturns() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 200, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testSameWindowDoublePaneOtherSideMerges() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 700, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .merge(windowID: g.windowID, side: .right, index: nil))
    }

    func testSinglePaneRightHalfSplitsRight() {
        let g = geometry(id: ObjectIdentifier(tokenA), single: true, active: .left)
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .split(windowID: g.windowID, dropSide: .right))
    }

    func testSinglePaneLeftHalfSplitsLeft() {
        let g = geometry(id: ObjectIdentifier(tokenA), single: true, active: .left)
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 400, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .split(windowID: g.windowID, dropSide: .left))
    }

    func testSinglePaneOnlyTabReturnsToSource() {
        let g = geometry(id: ObjectIdentifier(tokenA), single: true, active: .left, leftReal: 1)
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testTargetSinglePaneEmptyMergesInsteadOfSplitting() {
        let a = geometry(id: ObjectIdentifier(tokenA),
                         frame: CGRect(x: -2000, y: -2000, width: 1200, height: 900),
                         single: true, active: .left)
        let b = geometry(id: ObjectIdentifier(tokenB), single: true, active: .left, leftReal: 0)
        let source = FFDragSource(windowID: a.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [a, b])
        XCTAssertEqual(decision, .merge(windowID: b.windowID, side: .left, index: nil))
    }

    func testTargetSinglePaneWithTabsSplits() {
        let a = geometry(id: ObjectIdentifier(tokenA),
                         frame: CGRect(x: -2000, y: -2000, width: 1200, height: 900),
                         single: true, active: .left)
        let b = geometry(id: ObjectIdentifier(tokenB), single: true, active: .left, leftReal: 2)
        let source = FFDragSource(windowID: a.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 800, y: 400),
                                              geometries: [a, b])
        XCTAssertEqual(decision, .split(windowID: b.windowID, dropSide: .right))
    }

    func testOtherWindowDoublePaneMergesIntoPointerSide() {
        let a = geometry(id: ObjectIdentifier(tokenA),
                         frame: CGRect(x: -2000, y: -2000, width: 1200, height: 900),
                         single: false)
        let b = geometry(id: ObjectIdentifier(tokenB), single: false)
        let source = FFDragSource(windowID: a.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 700, y: 400),
                                              geometries: [a, b])
        XCTAssertEqual(decision, .merge(windowID: b.windowID, side: .right, index: nil))
    }

    func testOutsideAllWindowsCreatesWindow() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 3000, y: 3000),
                                              geometries: [g])
        XCTAssertEqual(decision, .newWindow)
    }

    func testInvalidZoneWinsOverTabStrip() {
        let plus = CGRect(x: 500, y: 810, width: 20, height: 20)
        let g = geometry(id: ObjectIdentifier(tokenA), invalid: [plus])
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 510, y: 820),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testWindowFrameButNoValidZoneReturns() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 400, y: 890),
                                              geometries: [g])
        XCTAssertEqual(decision, .returnToSource)
    }

    func testTabStripBufferStillReorders() {
        let g = geometry(id: ObjectIdentifier(tokenA))
        let source = FFDragSource(windowID: g.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: 300, y: 790),
                                              geometries: [g])
        XCTAssertEqual(decision, .reorder(windowID: g.windowID, side: .left, index: 2))
    }
}
