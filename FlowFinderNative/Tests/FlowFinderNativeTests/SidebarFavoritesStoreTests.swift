//
//  SidebarFavoritesStoreTests.swift
//  FlowFinderNativeTests
//
//  v0.8.0 P1：侧边栏收藏数据层回归测试。
//  覆盖设计稿 §7 P1-6 要求的三类：顺序重排（含 group row 跳过语义）、
//  失效灰显状态机、顺序持久化。
//

import AppKit
import XCTest
@testable import FlowFinderNative

final class SidebarFavoritesStoreTests: XCTestCase {

    // MARK: - 隔离的 UserDefaults

    /// 每个测试独立 suite，避免污染真实用户偏好（SidebarFavorites 键）
    private func makeIsolatedDefaults(_ label: String = #function) -> UserDefaults {
        let suiteName = "FlowFinderTests.\(label).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("无法创建隔离 UserDefaults suite: \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - 纯函数：顺序计算

    func testMoveElementToTail() {
        let items = ["A", "B", "C"]
        // childIndex 3 = 追加到末尾
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 0, insertionIndex: 3), ["B", "C", "A"])
    }

    func testMoveElementToHead() {
        let items = ["A", "B", "C"]
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 2, insertionIndex: 0), ["C", "A", "B"])
    }

    func testMoveToSamePositionKeepsOrder() {
        let items = ["A", "B", "C"]
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 1, insertionIndex: 2), ["A", "B", "C"])
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 1, insertionIndex: 1), ["A", "B", "C"])
    }

    func testMoveClampsOutOfRangeInsertionIndex() {
        let items = ["A", "B", "C"]
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 0, insertionIndex: 99), ["B", "C", "A"])
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 2, insertionIndex: -5), ["A", "B", "C"])
    }

    func testMoveIgnoresInvalidSourceIndex() {
        let items = ["A", "B"]
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 5, insertionIndex: 0), ["A", "B"])
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: -1, insertionIndex: 1), ["A", "B"])
    }

    func testMoveOnEmptyArrayIsSafe() {
        let items: [String] = []
        XCTAssertEqual(SidebarFavoriteOrder.move(items, fromIndex: 0, insertionIndex: 0), [])
    }

    func testMovingUpAndDownBoundaries() {
        XCTAssertNil(SidebarFavoriteOrder.indexAfterMovingUp(index: 0, count: 3), "首位不可上移")
        XCTAssertEqual(SidebarFavoriteOrder.indexAfterMovingUp(index: 2, count: 3), 1)

        XCTAssertNil(SidebarFavoriteOrder.indexAfterMovingDown(index: 2, count: 3), "末位不可下移")
        XCTAssertEqual(SidebarFavoriteOrder.indexAfterMovingDown(index: 0, count: 3), 1)

        XCTAssertNil(SidebarFavoriteOrder.indexAfterMovingUp(index: 0, count: 0))
        XCTAssertNil(SidebarFavoriteOrder.indexAfterMovingDown(index: 0, count: 0))
    }

    // MARK: - 存储：默认值

    func testStoreSeedsDefaultFavoritesWhenStorageMissing() {
        let store = SidebarFavoritesStore(defaults: makeIsolatedDefaults())
        XCTAssertEqual(store.items.count, 5)
        XCTAssertEqual(store.items.first?.name, "桌面")
        XCTAssertTrue(store.items.contains { $0.path == "/Applications" })
    }

    func testStoreDoesNotReseedAfterUserRemovesAllFavorites() {
        let defaults = makeIsolatedDefaults()
        let store = SidebarFavoritesStore(defaults: defaults)
        for item in store.items {
            store.remove(id: item.id)
        }
        XCTAssertTrue(store.items.isEmpty)

        // 重开：解码成功且为空数组表示用户主动清空，不得回填默认值
        let reopened = SidebarFavoritesStore(defaults: defaults)
        XCTAssertTrue(reopened.items.isEmpty)
    }

    // MARK: - 存储：顺序与持久化

    func testMovePersistsOrderAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let store = SidebarFavoritesStore(defaults: defaults)
        let originalIDs = store.items.map(\.id)

        XCTAssertTrue(store.move(fromIndex: 0, insertionIndex: store.items.count))
        let movedIDs = store.items.map(\.id)
        XCTAssertEqual(movedIDs.last, originalIDs.first)

        let reopened = SidebarFavoritesStore(defaults: defaults)
        XCTAssertEqual(reopened.items.map(\.id), movedIDs, "重启后顺序必须保持")
    }

    func testMoveReturnsFalseWhenOrderUnchanged() {
        let store = SidebarFavoritesStore(defaults: makeIsolatedDefaults())
        XCTAssertFalse(store.move(fromIndex: 1, insertionIndex: 2), "原位拖放不应写入磁盘")
    }

    func testMoveUpDownReturnsNewIndex() {
        let store = SidebarFavoritesStore(defaults: makeIsolatedDefaults())
        let secondID = store.items[1].id

        XCTAssertEqual(store.moveUp(index: 1), 0)
        XCTAssertEqual(store.index(of: secondID), 0)

        XCTAssertEqual(store.moveDown(index: 0), 1)
        XCTAssertEqual(store.index(of: secondID), 1)

        XCTAssertNil(store.moveUp(index: 0))
        XCTAssertNil(store.moveDown(index: store.items.count - 1))
    }

    func testAddAndRemoveFavorite() {
        let defaults = makeIsolatedDefaults()
        let store = SidebarFavoritesStore(defaults: defaults)
        let favorite = store.add(name: "项目", path: "/Volumes/Iris-Data/文件管理系统")

        XCTAssertEqual(store.items.last?.id, favorite.id)
        XCTAssertEqual(SidebarFavoritesStore(defaults: defaults).items.count, store.items.count)

        XCTAssertTrue(store.remove(id: favorite.id))
        XCTAssertFalse(store.remove(id: favorite.id), "重复移除应返回 false")
    }

    // MARK: - 失效状态机

    func testAvailabilityDefaultsToUnknown() {
        let store = SidebarFavoritesStore(defaults: makeIsolatedDefaults())
        let id = store.items[0].id
        XCTAssertEqual(store.availability(for: id), .unknown)
        XCTAssertFalse(store.isMissing(id: id), "unknown 不得被当作失效（避免启动期整列闪灰）")
    }

    func testRefreshAvailabilityMarksUnreachablePathsAsMissing() {
        let store = SidebarFavoritesStore(defaults: makeIsolatedDefaults())
        let existingPath = store.items[0].path

        store.refreshAvailability { path in path == existingPath }

        XCTAssertEqual(store.availability(for: store.items[0].id), .available)
        XCTAssertTrue(store.isMissing(id: store.items[1].id))
        XCTAssertTrue(store.hasMissingFavorites)
    }

    func testAvailabilityRecoversWhenPathComesBack() {
        let store = SidebarFavoritesStore(defaults: makeIsolatedDefaults())
        let id = store.items[0].id

        store.refreshAvailability { _ in false }
        XCTAssertTrue(store.isMissing(id: id), "外置卷拔出后应灰显")

        store.refreshAvailability { _ in true }
        XCTAssertFalse(store.isMissing(id: id), "外置卷重插后应恢复")
        XCTAssertFalse(store.hasMissingFavorites)
    }

    // MARK: - 行高度量（锁定，避免无意改动导致分区高度与行高脱节）

    func testSidebarMetricsLocked() {
        XCTAssertEqual(SidebarMetrics.sectionHeaderHeight, 22, "分区标题行高（访达 group row）")
        XCTAssertEqual(SidebarMetrics.rowHeight, 28, "收藏项行高")
        XCTAssertEqual(SidebarMetrics.emptyHintHeight, 26, "空态引导行高")
    }
}
