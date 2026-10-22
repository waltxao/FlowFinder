import XCTest
@testable import FlowFinder

final class FFDestructivePolicyTests: XCTestCase {

    func testConflictDefaultIsNotReplace() {
        XCTAssertNotEqual(FFConflictPolicy.defaultDecision, .replace)
        XCTAssertEqual(FFConflictPolicy.defaultDecision, .skip)
    }

    func testConflictButtonsPutSkipFirstAndReplaceLast() {
        XCTAssertEqual(FFConflictPolicy.buttonOrder.first, .skip)
        XCTAssertEqual(FFConflictPolicy.buttonOrder.last, .replace)
        XCTAssertEqual(FFConflictPolicy.buttonOrder, [.skip, .keepBoth, .replace])
    }

    func testDuplicateScanDefaultsToNoSelection() {
        XCTAssertTrue(FFDuplicateSelectionPolicy.initialSelection(groups: []).isEmpty)
        XCTAssertTrue(FFDuplicateSelectionPolicy.initialSelection(groups: ["group"]).isEmpty)
    }

    func testPermanentDeleteDoesNotPromiseUndo() {
        XCTAssertFalse(FFDeleteCopy.permanentDeleteMentionsUndo)
        XCTAssertTrue(FFDeleteCopy.permanentDeleteWarning.contains("无法撤销"))
    }
}
