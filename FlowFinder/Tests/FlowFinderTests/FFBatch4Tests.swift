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
        // C1：TCC 未应答（超时）不得显示「已授权」，否则首启会同时出现「已授权」与「读不到目录」。
        XCTAssertEqual(OnboardingPolicy.permissionTitle(denied: false, timedOut: true), "待确认")
        XCTAssertEqual(OnboardingPolicy.permissionTitle(denied: true, timedOut: true), "待授权")
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

    /// P2：前往文件夹的输入归一化（支持 ~、去空白、拒绝相对路径）
    func testGoToFolderNormalization() {
        let home = NSHomeDirectory()
        XCTAssertEqual(FFGoToFolder.normalize("  ~/Desktop  ", home: home),
                       (home as NSString).appendingPathComponent("Desktop"))
        XCTAssertEqual(FFGoToFolder.normalize("/tmp/", home: home), "/tmp")
        XCTAssertNil(FFGoToFolder.normalize("Documents", home: home))
        XCTAssertNil(FFGoToFolder.normalize("   ", home: home))
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
        // 2026-10-24：侧栏工具胶囊已迁到底栏右侧圆钮，不再属于侧栏 Tab 环
    }
}

final class FFBatchRenamePatternTests: XCTestCase {

    func testEmptyExtensionDoesNotAppendDot() {
        let folder = FileEntry(path: "/tmp/Projects", name: "Projects", isDirectory: true)
        XCTAssertEqual(FFBatchRenamePattern.apply("{name}.{ext}", entry: folder, index: 0),
                       "Projects")
    }

    func testFileExtensionStillAppends() {
        let file = FileEntry(path: "/tmp/photo.JPG", name: "photo.JPG", isDirectory: false)
        XCTAssertEqual(FFBatchRenamePattern.apply("{name}.{ext}", entry: file, index: 0),
                       "photo.jpg")
    }

    func testTrailingDotsAreSanitized() {
        let file = FileEntry(path: "/tmp/report", name: "report", isDirectory: false)
        XCTAssertEqual(FFBatchRenamePattern.apply("{name}...", entry: file, index: 0),
                       "report")
    }

    func testIndexPlaceholderStillWorks() {
        let file = FileEntry(path: "/tmp/a.txt", name: "a.txt", isDirectory: false)
        XCTAssertEqual(FFBatchRenamePattern.apply("{index:3}-{name}.{ext}", entry: file, index: 4),
                       "005-a.txt")
    }
}
