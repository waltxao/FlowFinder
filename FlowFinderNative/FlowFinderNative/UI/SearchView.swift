import Cocoa

// MARK: - SearchView (Legacy compat)

/// 旧的 SearchBarView 和 SearchResultsView 已被 SearchPanelController 替代。
/// 此文件保留兼容性，实际搜索功能由 SearchPanelController 实现。

/// 搜索过滤器（保留兼容性）
public struct SearchFilters {
    public var fileTypes: String?
    public var minSize: UInt64?
    public var maxSize: UInt64?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?

    public init(fileTypes: String? = nil, minSize: UInt64? = nil, maxSize: UInt64? = nil,
                modifiedAfter: Date? = nil, modifiedBefore: Date? = nil) {
        self.fileTypes = fileTypes
        self.minSize = minSize
        self.maxSize = maxSize
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
    }
}
