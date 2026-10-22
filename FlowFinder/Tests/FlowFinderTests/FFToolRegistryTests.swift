import XCTest
@testable import FlowFinder

final class FFToolRegistryTests: XCTestCase {

    private struct FakeTool: FFTool {
        let id: String
        let title: String
        var icon: FFIconName { .folder }
        var keywords: [String] { [] }
        var availability: FFToolAvailability = .available
        func availability(in context: FFToolContext) -> FFToolAvailability { availability }
        func run(in context: FFToolContext) {}
    }

    private func context(selection: [FileEntry] = []) -> FFToolContext {
        FFToolContext(activePane: .left, currentPath: "/tmp", selection: selection, window: nil)
    }

    func testRegisterAndAvailability() {
        let registry = FFToolRegistry()
        registry.register(FakeTool(id: "dup", title: "重复文件"))
        let tools = registry.availableTools(for: context())
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.1, .available)
    }

    func testDuplicateIDIsRejected() {
        let registry = FFToolRegistry()
        registry.register(FakeTool(id: "dup", title: "A"))
        registry.register(FakeTool(id: "dup", title: "B"))
        XCTAssertEqual(registry.availableTools(for: context()).count, 1)
        XCTAssertEqual(registry.availableTools(for: context()).first?.0.title, "A")
    }

    func testAvailabilityReasonIsExposed() {
        let registry = FFToolRegistry()
        registry.register(FakeTool(id: "batch", title: "批量", availability: .needsSelection))
        let pair = registry.availableTools(for: context()).first
        XCTAssertEqual(pair?.1, .needsSelection)
        XCTAssertEqual(pair?.1.reason, "先选择文件")
        XCTAssertFalse(pair?.1.isAvailable ?? true)
    }

    func testBuiltInsAreRegisteredOnce() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        FFToolRegistry.registerBuiltInsIfNeeded()
        let ids = FFToolRegistry.shared.registeredTools.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(ids.contains("duplicate-scan"))
        XCTAssertTrue(ids.contains("batch-rename"))
    }

    func testBuiltInToolsAreGrouped() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        let byID = Dictionary(uniqueKeysWithValues:
            FFToolRegistry.shared.registeredTools.map { ($0.id, $0.group) })
        XCTAssertEqual(byID["duplicate-scan"], .organize)
        XCTAssertEqual(byID["batch-rename"], .organize)
        XCTAssertEqual(byID["task-center"], .task)
        XCTAssertEqual(byID["settings"], .system)
        XCTAssertEqual(byID["about"], .system)
    }

    @MainActor
    func testToolsAreGroupedAndTitleOmitsPaneSide() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        let context = FFToolContext(activePane: .right, currentPath: "/tmp", selection: [], window: nil)
        let page = SidebarToolPageView(context: context)
        XCTAssertEqual(page.headerTextsForTesting.first, "工具")
        XCTAssertFalse(page.headerTextsForTesting.joined().contains("右面板"))
    }
}
