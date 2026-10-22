import Combine
import XCTest
@testable import FlowFinder

final class PaneStoreTests: XCTestCase {
    func testSelectionDoesNotEmitFilesChange() {
        let store = PaneStore(initial: PaneState(path: "/tmp"))
        var changes: [PaneChange] = []
        let c = store.$change.sink { changes.append($0) }
        defer { c.cancel() }

        store.setSelection(["a"])
        XCTAssertFalse(changes.contains(.files))
        XCTAssertTrue(changes.contains(.selection))
    }

    func testFilesChangeEmitsFiles() {
        let store = PaneStore(initial: PaneState(path: "/tmp"))
        var state = store.state
        state.files = [FileEntry(path: "/tmp/a", name: "a", isDirectory: false)]
        store.apply(state: state)
        XCTAssertEqual(store.change, .files)
    }

    func testFocusModelIsSingleSource() {
        let focus = WindowFocusModel()
        XCTAssertEqual(focus.activePane, .left)
        focus.activate(.right)
        XCTAssertEqual(focus.activePane, .right)
        focus.toggle()
        XCTAssertEqual(focus.activePane, .left)
    }
}
