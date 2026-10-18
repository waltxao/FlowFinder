//
//  SidebarFavoritesStore.swift
//  FlowFinder
//
//  v0.8.0 P1：侧边栏收藏数据层（存储 / 顺序 / 失效状态）。
//
//  从 SidebarView 内嵌数据源中抽出，纯逻辑部分不依赖 AppKit，便于 XCTest 覆盖。
//  设计依据：docs/superpowers/specs/2026-09-02-v0.8.0-sidebar-favorites-redesign-design.md
//

import Foundation

// MARK: - 失效状态

/// 收藏路径可用性状态机
///
/// - `unknown`：尚未完成异步校验（启动初期），按可用渲染，避免整列闪灰
/// - `available`：路径存在，正常显示
/// - `missing`：路径不存在（外置卷拔出 / 目录被删除）——灰显保留，不自动删除，
///   外置卷重插后自动恢复（设计稿 §4.2「失效处理」）
enum FavoriteAvailability: Equatable {
    case unknown
    case available
    case missing
}

// MARK: - 顺序计算（纯函数，可单测）

/// 收藏顺序计算
///
/// 全部为纯函数：不读 UserDefaults、不碰 AppKit，测试可直接断言返回值。
enum SidebarFavoriteOrder {

    /// 把 `fromIndex` 位置的元素移动到插入位置 `insertionIndex`。
    ///
    /// `insertionIndex` 采用 NSOutlineView drop 的 childIndex 语义——"插入到该下标之前"，
    /// 取值范围 0...count（count 表示追加到末尾）。源下标小于插入位置时，
    /// 移除源元素后目标下标需前移一位，否则会落到预期位置的下一个。
    ///
    /// 越界输入不崩溃，做夹紧处理（拖拽过程中 Index 可能瞬时越界）。
    static func move<T>(_ items: [T], fromIndex: Int, insertionIndex: Int) -> [T] {
        guard items.indices.contains(fromIndex), insertionIndex >= 0 else { return items }
        let target = min(insertionIndex, items.count)
        var result = items
        let element = result.remove(at: fromIndex)
        let destination = fromIndex < target ? target - 1 : target
        result.insert(element, at: min(max(destination, 0), result.count))
        return result
    }

    /// 上移一位后的目标下标；已在首位返回 nil（调用方据此禁用菜单项）
    static func indexAfterMovingUp(index: Int, count: Int) -> Int? {
        guard index > 0, index < count else { return nil }
        return index - 1
    }

    /// 下移一位后的目标下标；已在末位返回 nil
    static func indexAfterMovingDown(index: Int, count: Int) -> Int? {
        guard index >= 0, index < count - 1 else { return nil }
        return index + 1
    }
}

// MARK: - 收藏存储

/// 侧边栏收藏存储
///
/// 单一职责：维护收藏数组顺序 + 失效状态，并负责 UserDefaults 持久化。
/// `defaults` 可注入，测试用独立 suite 避免污染真实偏好。
final class SidebarFavoritesStore {

    /// UserDefaults 存储键（与历史版本保持一致，老用户收藏不丢）
    static let storageKey = "SidebarFavorites"

    private let defaults: UserDefaults
    private(set) var items: [FavoriteItem] = []

    /// 每个收藏 id 的可用性状态
    private(set) var availability: [String: FavoriteAvailability] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - 默认值

    /// 首次启动（或数据损坏）时的默认收藏：桌面 / 文档 / 下载 / 应用程序 / 主目录
    static func defaultFavorites(homePath: String = NSHomeDirectory()) -> [FavoriteItem] {
        let homeName = homePath.split(separator: "/").map(String.init).last ?? "主目录"
        return [
            FavoriteItem(name: "桌面", path: (homePath as NSString).appendingPathComponent("Desktop")),
            FavoriteItem(name: "文档", path: (homePath as NSString).appendingPathComponent("Documents")),
            FavoriteItem(name: "下载", path: (homePath as NSString).appendingPathComponent("Downloads")),
            FavoriteItem(name: "应用程序", path: "/Applications"),
            FavoriteItem(name: homeName, path: homePath),
        ]
    }

    // MARK: - 持久化

    private func load() {
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            // 注意：解码成功但为空数组表示用户主动清空，不能回填默认值
            items = decoded
        } else {
            items = Self.defaultFavorites()
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - 增删

    @discardableResult
    func add(name: String, path: String) -> FavoriteItem {
        let favorite = FavoriteItem(name: name, path: path)
        items.append(favorite)
        persist()
        return favorite
    }

    @discardableResult
    func remove(id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: index)
        availability.removeValue(forKey: id)
        persist()
        return true
    }

    // MARK: - 顺序

    /// 按拖放插入位置重排；返回是否实际发生变化
    @discardableResult
    func move(fromIndex: Int, insertionIndex: Int) -> Bool {
        let reordered = SidebarFavoriteOrder.move(items, fromIndex: fromIndex, insertionIndex: insertionIndex)
        guard reordered.map(\.id) != items.map(\.id) else { return false }
        items = reordered
        persist()
        return true
    }

    /// 上移一位；返回移动后的新下标（已在首位返回 nil）
    func moveUp(index: Int) -> Int? {
        guard let target = SidebarFavoriteOrder.indexAfterMovingUp(index: index, count: items.count) else {
            return nil
        }
        items.swapAt(index, target)
        persist()
        return target
    }

    /// 下移一位；返回移动后的新下标（已在末位返回 nil）
    func moveDown(index: Int) -> Int? {
        guard let target = SidebarFavoriteOrder.indexAfterMovingDown(index: index, count: items.count) else {
            return nil
        }
        items.swapAt(index, target)
        persist()
        return target
    }

    // MARK: - 查询

    func index(of id: String) -> Int? {
        items.firstIndex(where: { $0.id == id })
    }

    func favorite(id: String) -> FavoriteItem? {
        items.first(where: { $0.id == id })
    }

    // MARK: - 失效状态

    func setAvailability(_ state: FavoriteAvailability, for id: String) {
        availability[id] = state
    }

    func availability(for id: String) -> FavoriteAvailability {
        availability[id] ?? .unknown
    }

    /// 是否确认失效（unknown 不算失效，避免启动初期误灰）
    func isMissing(id: String) -> Bool {
        availability[id] == .missing
    }

    /// 是否至少有一项失效（供空态/汇总提示使用）
    var hasMissingFavorites: Bool {
        items.contains { isMissing(id: $0.id) }
    }

    /// 逐项校验路径存在性（`fileExists` 注入便于测试；生产环境传 FileManager）
    ///
    /// 校验为同步纯计算——调用方负责放到后台队列执行，结果回主线程后再刷新 UI。
    func refreshAvailability(fileExists: (String) -> Bool) {
        var updated: [String: FavoriteAvailability] = [:]
        for item in items {
            updated[item.id] = fileExists(item.path) ? .available : .missing
        }
        availability = updated
    }
}
