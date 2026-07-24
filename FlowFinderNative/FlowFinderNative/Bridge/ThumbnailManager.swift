import Foundation
import QuickLookThumbnailing
import AppKit

/// 缩略图管理器：QLThumbnailGenerator 异步生成 + NSCache LRU + 磁盘缓存
public final class ThumbnailManager {
    public static let shared = ThumbnailManager()

    private let generator = QLThumbnailGenerator.shared
    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200  // 最多缓存 200 个缩略图
        return cache
    }()

    /// 磁盘缓存目录
    private let diskCacheURL: URL = {
        // 安全解包：cachesDirectory 通常存在，但 first 在极端环境（沙盒配置异常）可能为 nil。
        // 退化为 ~/Library/Caches，若仍不可用则使用 NSTemporaryDirectory。
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let cacheDir = cachesDir.appendingPathComponent("FlowFinderThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }()

    /// 磁盘缓存上限（字节）。超过此上限时按最久未访问清理旧文件。
    private let maxDiskCacheBytes: Int64 = 100 * 1024 * 1024  // 100 MB

    /// 活跃请求（用于取消）。请求完成后必须移除，否则会泄漏 QLThumbnailGenerator.Request 对象。
    private var activeRequests: [String: QLThumbnailGenerator.Request] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    /// 异步生成缩略图（先查缓存，再生成）
    /// - Parameters:
    ///   - path: 文件路径
    ///   - size: 期望尺寸（默认 64x64）
    ///   - completion: 完成回调（主线程）
    public func generateThumbnail(
        path: String,
        size: CGSize = CGSize(width: 64, height: 64),
        completion: @escaping (NSImage?) -> Void
    ) {
        let cacheKey = cacheKey(for: path, size: size)

        // 1. 查内存缓存
        if let cached = memoryCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        // 2. 查磁盘缓存
        if let diskImage = loadFromDiskCache(path: path, cacheKey: cacheKey as String) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            completion(diskImage)
            return
        }

        // 3. 异步生成
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        let reqRef = request

        // 记录活跃请求
        lock.lock()
        activeRequests[path] = reqRef
        lock.unlock()

        generator.generateBestRepresentation(for: request) { [weak self] thumbnail, error in
            // 请求完成（无论成功/失败）都必须从 activeRequests 移除，避免泄漏 Request 对象。
            self?.lock.lock()
            self?.activeRequests.removeValue(forKey: path)
            self?.lock.unlock()

            if let error = error {
                print("ThumbnailManager: 生成缩略图失败: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let thumbnail = thumbnail else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let image = NSImage(
                cgImage: thumbnail.cgImage,
                size: CGSize(width: thumbnail.cgImage.width, height: thumbnail.cgImage.height)
            )

            // 写入缓存
            self?.memoryCache.setObject(image, forKey: cacheKey)
            self?.saveToDiskCache(image: image, path: path, cacheKey: cacheKey as String)

            DispatchQueue.main.async { completion(image) }
        }
    }

    /// 同步获取缓存中的缩略图（不触发生成）
    /// - Parameters:
    ///   - path: 文件路径
    ///   - size: 期望尺寸
    /// - Returns: 缓存的图片（如果存在）
    public func cacheImage(for path: String, size: CGSize = CGSize(width: 64, height: 64)) -> NSImage? {
        let key = cacheKey(for: path, size: size)
        return memoryCache.object(forKey: key)
    }

    /// 预生成缩略图（不返回结果，用于预热缓存）
    /// - Parameters:
    ///   - paths: 文件路径数组
    ///   - size: 期望尺寸
    public func prefetchThumbnails(paths: [String], size: CGSize = CGSize(width: 64, height: 64)) {
        for path in paths {
            generateThumbnail(path: path, size: size) { _ in }
        }
    }

    /// 取消指定路径的缩略图生成
    /// - Parameter path: 文件路径
    public func cancelGeneration(for path: String) {
        lock.lock()
        if let request = activeRequests[path] {
            generator.cancel(request)
            activeRequests.removeValue(forKey: path)
        }
        lock.unlock()
    }

    /// 清除内存缓存
    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// 清除磁盘缓存
    public func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    /// 清除所有缓存（内存 + 磁盘）
    public func clearCache() {
        clearMemoryCache()
        clearDiskCache()
    }

    // MARK: - Private

    private func cacheKey(for path: String, size: CGSize) -> NSString {
        return "\(path)_\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private func diskCacheURL(for path: String, cacheKey: String) -> URL {
        // 使用路径的 hash 作为文件名
        let hash = path.djb2hash()
        let ext = (path as NSString).pathExtension
        return diskCacheURL.appendingPathComponent("\(hash)_\(cacheKey).\(ext.isEmpty ? "png" : ext)")
    }

    private func loadFromDiskCache(path: String, cacheKey: String) -> NSImage? {
        let url = diskCacheURL(for: path, cacheKey: cacheKey)
        return NSImage(contentsOf: url)
    }

    private func saveToDiskCache(image: NSImage, path: String, cacheKey: String) {
        let url = diskCacheURL(for: path, cacheKey: cacheKey)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            // 转为 PNG 数据保存
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url, options: .atomic)
            }
            // 写入后触发磁盘缓存清理，确保总大小不超过 maxDiskCacheBytes。
            // cleanupDiskCache 是 best-effort，失败不影响主流程。
            self?.cleanupDiskCacheIfNeeded()
        }
    }

    /// 磁盘缓存清理：当总大小超过 maxDiskCacheBytes 时，按 contentModificationDate
    /// 从旧到新删除文件，直到总大小降到上限以下。best-effort，错误被忽略。
    private func cleanupDiskCacheIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: diskCacheURL,
                                                      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                      options: [.skipsHiddenFiles]) else {
            return
        }

        // 收集 (url, modificationDate, size)
        var entries: [(url: URL, date: Date, size: Int64)] = []
        var totalBytes: Int64 = 0
        for fileURL in files {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate ?? Date.distantPast
            let size = Int64(values?.fileSize ?? 0)
            entries.append((fileURL, date, size))
            totalBytes += size
        }

        guard totalBytes > maxDiskCacheBytes else { return }

        // 按修改时间从旧到新排序，优先删除最旧的文件
        entries.sort { $0.date < $1.date }
        for entry in entries {
            if totalBytes <= maxDiskCacheBytes { break }
            try? fm.removeItem(at: entry.url)
            totalBytes -= entry.size
        }
    }
}

// MARK: - String Hash Extension

private extension String {
    func djb2hash() -> UInt64 {
        var hash: UInt64 = 5381
        for char in self.utf8 {
            hash = hash &* 33 &+ UInt64(char)
        }
        return hash
    }
}
