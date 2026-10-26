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

    func testDuplicateSelectionCannotDeleteEveryRemainingFile() {
        let paths = ["a", "b", "c"]
        XCTAssertTrue(FFDuplicateSelectionPolicy.canMarkForDeletion(
            filePath: "a", allPaths: paths, currentlyMarked: []))
        XCTAssertTrue(FFDuplicateSelectionPolicy.canMarkForDeletion(
            filePath: "b", allPaths: paths, currentlyMarked: ["a"]))
        XCTAssertFalse(FFDuplicateSelectionPolicy.canMarkForDeletion(
            filePath: "c", allPaths: paths, currentlyMarked: ["a", "b"]),
            "每组至少保留一个文件")
    }

    func testPermanentDeleteAlwaysRequiresConfirmation() {
        XCTAssertTrue(DeleteConfirmDialog.shouldConfirm(
            fileCount: 1, confirmDisabled: true, windowAvailable: true, isPermanent: true),
            "永久删除不能复用废纸篓的「不再询问」")
        XCTAssertFalse(DeleteConfirmDialog.shouldConfirm(
            fileCount: 1, confirmDisabled: true, windowAvailable: true, isPermanent: false))
    }
}
