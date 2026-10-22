import AppKit
import XCTest
@testable import FlowFinder

/// 批次 4：引导、崩溃日志、工具命名、侧栏 Tab 环。
final class FFBatch4Tests: XCTestCase {

    private let suite = "FFBatch4Tests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testOnboardingPolicy() {
        XCTAssertTrue(OnboardingPolicy.shouldShow(completed: false, isRunningTests: false, selfTest: false))
        XCTAssertFalse(OnboardingPolicy.shouldShow(completed: true, isRunningTests: false, selfTest: false))
        XCTAssertFalse(OnboardingPolicy.shouldShow(completed: false, isRunningTests: true, selfTest: false))
        XCTAssertFalse(OnboardingPolicy.shouldShow(completed: false, isRunningTests: false, selfTest: true))
        XCTAssertEqual(OnboardingPolicy.permissionTitle(denied: true), "待授权")
        XCTAssertEqual(OnboardingPolicy.permissionTitle(denied: false), "已授权")
    }

    @MainActor
    func testOnboardingStartMarksCompleted() {
        let controller = OnboardingWindowController(defaults: defaults, center: false)
        XCTAssertFalse(defaults.bool(forKey: OnboardingWindowController.completedKey))
        controller.startUsing()
        XCTAssertTrue(defaults.bool(forKey: OnboardingWindowController.completedKey))
    }

    @MainActor
    func testOnboardingLaterDoesNotMarkCompleted() {
        let controller = OnboardingWindowController(defaults: defaults, center: false)
        controller.later()
        XCTAssertFalse(defaults.bool(forKey: OnboardingWindowController.completedKey))
    }

    func testCrashLogFormatAndAppend() throws {
        let base = URL(fileURLWithPath: "/tmp/ff_crash_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let formatted = FFCrashLog.format(name: "NSInternalInconsistencyException",
                                          reason: "boom",
                                          date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(formatted.contains("NSInternalInconsistencyException"))
        XCTAssertTrue(formatted.contains("boom"))

        let url = try XCTUnwrap(FFCrashLog.append(name: "TestCrash", reason: "reason", base: base))
        XCTAssertEqual(url.lastPathComponent, "crash.log")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("TestCrash"))
        XCTAssertTrue(text.contains("reason"))
    }

    func testToolTitlesNoLongerClaimAI() {
        FFToolRegistry.registerBuiltInsIfNeeded()
        let titles = FFToolRegistry.shared.registeredTools.map(\.title)
        XCTAssertFalse(titles.contains { $0.contains("AI") },
                       "工具标题不应再出现 AI：\(titles)")
        XCTAssertTrue(titles.contains("按类型自动打标签"))
    }

    @MainActor
    func testKeyViewLoopIncludesSidebarFavorites() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        _ = controller.window
        controller.setSidebarVisible(true, animated: false)

        let loop = controller.keyViewLoopForTesting()
        XCTAssertTrue(loop.contains(controller.sidebarView.sidebarFocusableView),
                      "Tab 环应包含侧栏收藏列表")
        XCTAssertTrue(loop.contains(controller.sidebarView.toolPillFocusView),
                      "Tab 环仍应包含工具胶囊")
    }
}
