import XCTest
@testable import FlowFinder

/// 批次 1：设置读取与策略纯函数。
/// 每个设置都用注入的 UserDefaults 断言默认值与生效值，避免污染真实偏好。
final class FFAppSettingsTests: XCTestCase {

    private let suiteName = "FFAppSettingsTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - 拖拽默认行为

    func testDragBehaviorDefaultsToFinder() {
        XCTAssertEqual(FFAppSettings.dragBehavior(defaults: defaults), .finder)
        // 访达语义：同盘移动、跨盘复制，⌘ 反转
        XCTAssertTrue(FFDragBehaviorPolicy.shouldMove(behavior: .finder, commandPressed: false, sameVolume: true))
        XCTAssertFalse(FFDragBehaviorPolicy.shouldMove(behavior: .finder, commandPressed: false, sameVolume: false))
        XCTAssertFalse(FFDragBehaviorPolicy.shouldMove(behavior: .finder, commandPressed: true, sameVolume: true))
        XCTAssertTrue(FFDragBehaviorPolicy.shouldMove(behavior: .finder, commandPressed: true, sameVolume: false))
    }

    func testDragBehaviorAlwaysCopyAndAlwaysMoveInvertWithCommand() {
        XCTAssertFalse(FFDragBehaviorPolicy.shouldMove(behavior: .alwaysCopy, commandPressed: false, sameVolume: true))
        XCTAssertFalse(FFDragBehaviorPolicy.shouldMove(behavior: .alwaysCopy, commandPressed: false, sameVolume: false))
        XCTAssertTrue(FFDragBehaviorPolicy.shouldMove(behavior: .alwaysCopy, commandPressed: true, sameVolume: true))

        XCTAssertTrue(FFDragBehaviorPolicy.shouldMove(behavior: .alwaysMove, commandPressed: false, sameVolume: true))
        XCTAssertTrue(FFDragBehaviorPolicy.shouldMove(behavior: .alwaysMove, commandPressed: false, sameVolume: false))
        XCTAssertFalse(FFDragBehaviorPolicy.shouldMove(behavior: .alwaysMove, commandPressed: true, sameVolume: true))
    }

    /// 旧版把「默认操作行为」存成 Int（0/1），必须安全回退到跟随访达
    func testLegacyIntegerBehaviorFallsBackToFinder() {
        defaults.set(1, forKey: FFUserDefaultsKeys.defaultFileBehavior)
        XCTAssertEqual(FFAppSettings.dragBehavior(defaults: defaults), .finder)

        defaults.set("alwaysMove", forKey: FFUserDefaultsKeys.defaultFileBehavior)
        XCTAssertEqual(FFAppSettings.dragBehavior(defaults: defaults), .alwaysMove)
    }

    // MARK: - 排序与选中

    func testFolderFirstSortDefaultsOnAndCanBeDisabled() {
        XCTAssertTrue(FFAppSettings.folderFirstSort(defaults: defaults))
        defaults.set(false, forKey: FFUserDefaultsKeys.folderFirstSort)
        XCTAssertFalse(FFAppSettings.folderFirstSort(defaults: defaults))
    }

    func testSortPolicyRespectsFolderFirstToggle() {
        let folder = FileEntry(path: "/tmp/z", name: "z", isDirectory: true)
        let file = FileEntry(path: "/tmp/a", name: "a", isDirectory: false)
        XCTAssertTrue(FFSortPolicy.isOrderedBefore(folder, file, field: .name,
                                                   ascending: true, folderFirst: true))
        XCTAssertFalse(FFSortPolicy.isOrderedBefore(folder, file, field: .name,
                                                    ascending: true, folderFirst: false))
    }

    func testSelectionRestoreKeepsExistingPathsInPreviousOrder() {
        XCTAssertEqual(FFSelectionRestore.pathsToRestore(previous: ["/a", "/b", "/c"],
                                                         available: ["/c", "/a"]),
                       ["/a", "/c"])
        XCTAssertEqual(FFSelectionRestore.pathsToRestore(previous: ["/a"], available: []), [])
    }

    func testKeepSelectionPositionDefaultsOff() {
        XCTAssertFalse(FFAppSettings.keepSelectionPosition(defaults: defaults))
        defaults.set(true, forKey: FFUserDefaultsKeys.keepSelectionPosition)
        XCTAssertTrue(FFAppSettings.keepSelectionPosition(defaults: defaults))
    }

    // MARK: - 移动确认 / 更新 / SMB

    func testMoveConfirmationDefaultsOffAndReadsSwitch() {
        XCTAssertFalse(FFAppSettings.confirmMove(defaults: defaults))
        defaults.set(true, forKey: FFUserDefaultsKeys.confirmFileOperations)
        XCTAssertTrue(FFAppSettings.confirmMove(defaults: defaults))
    }

    func testUpdateCheckDefaultsOnAndSMBDefaults() {
        XCTAssertTrue(FFAppSettings.checkUpdateOnStartup(defaults: defaults))
        XCTAssertEqual(FFAppSettings.smbDomain(defaults: defaults), "")
        XCTAssertFalse(FFAppSettings.smbAutoReconnect(defaults: defaults))
    }

    /// 移动确认只拦移动，不拦复制；文案带项目数与目标目录名
    func testMoveConfirmationGateAndMessage() {
        XCTAssertFalse(MoveConfirmation.shouldAsk(enabled: false, isMove: true))
        XCTAssertFalse(MoveConfirmation.shouldAsk(enabled: true, isMove: false))
        XCTAssertTrue(MoveConfirmation.shouldAsk(enabled: true, isMove: true))
        XCTAssertEqual(MoveConfirmation.message(count: 3, destinationName: "归档"),
                       "将 3 个项目移动到「归档」？可用 ⌘Z 撤销。")
    }

    // MARK: - 更新判定（B1-04）

    func testUpdateDecisionPrefersFullVersionStamp() {
        // 完整版本戳：只比较构建号
        XCTAssertEqual(FFUpdateDecision.evaluate(localMarketing: "0.8.0", localBuild: "26102202",
                                                 releaseText: "v0.8.0-26102301", releaseTag: "v0.8.0"),
                       .updateAvailable(remoteVersion: "0.8.0-26102301"))
        XCTAssertEqual(FFUpdateDecision.evaluate(localMarketing: "0.8.0", localBuild: "26102202",
                                                 releaseText: "v0.8.0-26102202", releaseTag: "v0.8.0"),
                       .upToDate)
        XCTAssertEqual(FFUpdateDecision.evaluate(localMarketing: "0.8.0", localBuild: "26102202",
                                                 releaseText: "v0.8.0-26102101", releaseTag: "v0.8.0"),
                       .upToDate)
    }

    func testUpdateDecisionFallsBackToMarketingVersion() {
        XCTAssertEqual(FFUpdateDecision.evaluate(localMarketing: "0.8.0", localBuild: "26102202",
                                                 releaseText: "v0.8.1 稳定性更新", releaseTag: "v0.8.1"),
                       .updateAvailable(remoteVersion: "0.8.1"))
        XCTAssertEqual(FFUpdateDecision.evaluate(localMarketing: "0.8.0", localBuild: "26102202",
                                                 releaseText: "v0.7.9-b1", releaseTag: "v0.7.9-b1"),
                       .upToDate)
    }

    func testUpdateDecisionUnknownWhenNoVersionFound() {
        XCTAssertEqual(FFUpdateDecision.evaluate(localMarketing: "0.8.0", localBuild: "26102202",
                                                 releaseText: "Nightly build", releaseTag: "nightly"),
                       .unknown)
    }

    // MARK: - SMB（B1-07 / B1-08）

    func testSMBURLIncludesDomainAndCredentials() {
        XCTAssertEqual(FFSMBURL.build(server: "server.local", port: "445", share: "Team",
                                      user: "alice", password: "secret", domain: "WORKGROUP")?.absoluteString,
                       "smb://WORKGROUP;alice:secret@server.local:445/Team")
        XCTAssertEqual(FFSMBURL.build(server: "server.local", user: "alice")?.absoluteString,
                       "smb://alice@server.local")
        XCTAssertNil(FFSMBURL.build(server: ""))
    }

    func testSMBConnectionStoreRoundTripAndDedupe() {
        let d = defaults!
        let a = FFSavedSMBConnection(url: "smb://a", mountPoint: "/Volumes/A", volumeName: "A")
        let b = FFSavedSMBConnection(url: "smb://b", mountPoint: "/Volumes/B", volumeName: "B")
        FFSMBConnectionStore.save(a, defaults: d)
        FFSMBConnectionStore.save(b, defaults: d)
        FFSMBConnectionStore.save(a, defaults: d)
        XCTAssertEqual(FFSMBConnectionStore.load(defaults: d), [b, a])

        FFSMBConnectionStore.remove(url: "smb://b", defaults: d)
        XCTAssertEqual(FFSMBConnectionStore.load(defaults: d), [a])
    }

    func testActivePaneRestoreHonorsSinglePane() {
        XCTAssertEqual(FFStartupPath.activePane(from: "right", singlePane: false), .right)
        XCTAssertEqual(FFStartupPath.activePane(from: "left", singlePane: false), .left)
        XCTAssertNil(FFStartupPath.activePane(from: "right", singlePane: true))
        XCTAssertNil(FFStartupPath.activePane(from: "bogus", singlePane: false))
    }

    func testSMBStatusTexts() {
        XCTAssertEqual(FFSMBStatusText.reconnecting(volume: "Team", attempt: 2, max: 3),
                       "正在重连「Team」（2/3）")
        XCTAssertEqual(FFSMBStatusText.reconnected(volume: "Team"), "「Team」已重新连接")
        XCTAssertEqual(FFSMBStatusText.failed(volume: "Team"), "「Team」重连失败")
    }
}
