import Foundation

/// Represents a mounted volume/drive
public struct VolumeInfo: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let path: String
    public let fsType: String
    public let totalSize: UInt64
    public let freeSize: UInt64
    public let usedSize: UInt64
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isWritable: Bool

    /// Initialize from FFI reference
    /// - Parameter ref: FFVolumeInfo structure from Rust core
    public init(from ref: FFVolumeInfo) {
        // 安全解包：Rust 侧字符串指针可能为 nil（例如卷信息查询失败时），
        // 强制解包会崩溃。退化为空字符串以保持结构体可构造性。
        self.name = ref.name.map { String(cString: $0) } ?? ""
        self.path = ref.path.map { String(cString: $0) } ?? ""
        self.fsType = ref.fs_type.map { String(cString: $0) } ?? ""
        self.totalSize = ref.total_size
        self.freeSize = ref.free_size
        self.usedSize = ref.used_size
        self.isRemovable = ref.is_removable
        self.isEjectable = ref.is_ejectable
        self.isWritable = ref.is_writable
        self.id = self.path
    }

    /// Convenience initializer with all fields
    public init(name: String, path: String, fsType: String, totalSize: UInt64,
                freeSize: UInt64, usedSize: UInt64, isRemovable: Bool,
                isEjectable: Bool, isWritable: Bool) {
        self.name = name
        self.path = path
        self.fsType = fsType
        self.totalSize = totalSize
        self.freeSize = freeSize
        self.usedSize = usedSize
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isWritable = isWritable
        self.id = path
    }

}
