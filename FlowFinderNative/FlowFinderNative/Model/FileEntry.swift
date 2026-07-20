import Foundation

/// Represents a file or directory entry in the file system
public struct FileEntry: Identifiable, Equatable, Hashable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let isFile: Bool
    public let isSymlink: Bool
    public let isHidden: Bool
    public let isSystemProtected: Bool
    public let size: UInt64
    public let modificationDate: Date
    public let creationDate: Date
    public var tags: [Tag]

    /// File extension derived from the name (if any)
    public var fileExtension: String {
        let url = URL(fileURLWithPath: name)
        return url.pathExtension.lowercased()
    }

    /// Display name (name without extension for files)
    public var displayName: String {
        if isDirectory { return name }
        let url = URL(fileURLWithPath: name)
        return url.deletingPathExtension().lastPathComponent
    }

    /// Human-readable file kind description
    public var kindDescription: String {
        if isDirectory { return "文件夹" }
        let ext = fileExtension
        let kinds: [String: String] = [
            "jpg": "JPEG 图像", "jpeg": "JPEG 图像", "png": "PNG 图像",
            "gif": "GIF 图像", "pdf": "PDF 文档", "txt": "纯文本",
            "md": "Markdown", "html": "HTML", "css": "CSS",
            "js": "JavaScript", "json": "JSON", "xml": "XML",
            "zip": "ZIP 压缩包", "mp3": "MP3 音频", "mp4": "MP4 视频",
            "mov": "QuickTime 视频", "doc": "Word 文档", "docx": "Word 文档",
            "xls": "Excel 表格", "xlsx": "Excel 表格",
            "ppt": "PowerPoint", "pptx": "PowerPoint",
            "app": "应用程序", "dmg": "磁盘映像",
        ]
        return kinds[ext] ?? (ext.isEmpty ? "文件" : "\(ext.uppercased()) 文件")
    }

    /// Initialize from FFI reference
    public init(from ref: FFEntryRef) {
        self.path = String(cString: ref.path)
        self.name = String(cString: ref.name)
        self.isDirectory = ref.isDir
        self.isFile = ref.isFile
        self.isSymlink = ref.isSymlink
        self.isHidden = ref.isHidden
        self.isSystemProtected = ref.isSystemProtected
        self.size = ref.size
        self.modificationDate = Date(timeIntervalSince1970: TimeInterval(ref.modified))
        self.creationDate = Date(timeIntervalSince1970: TimeInterval(ref.created))
        self.tags = []
    }

    /// Convenience initializer
    public init(
        path: String, name: String, isDirectory: Bool, isFile: Bool = true,
        isSymlink: Bool = false, isHidden: Bool = false, isSystemProtected: Bool = false,
        size: UInt64 = 0, modificationDate: Date = Date(), creationDate: Date = Date(),
        tags: [Tag] = []
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.isFile = isFile
        self.isSymlink = isSymlink
        self.isHidden = isHidden
        self.isSystemProtected = isSystemProtected
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.tags = tags
    }

    /// Formatted file size string (e.g., "1.5 MB", "4 KB", "0 bytes")
    public var formattedSize: String {
        guard !isDirectory else { return "--" }
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        byteCountFormatter.countStyle = .file
        return byteCountFormatter.string(fromByteCount: Int64(size))
    }

    /// Formatted modification date string
    public var formattedModificationDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }

    /// Formatted creation date string
    public var formattedCreationDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }

    /// Sort-friendly name (directories first, then alphabetically)
    public var sortName: String {
        return isDirectory ? "0_\(name.lowercased())" : "1_\(name.lowercased())"
    }
}
