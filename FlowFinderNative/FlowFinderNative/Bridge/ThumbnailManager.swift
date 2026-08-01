import Foundation
import QuickLookThumbnailing
import AppKit
import os.log

/// 缩略图管理器：QLThumbnailGenerator 异步生成 + NSCache LRU + 磁盘缓存
public final class ThumbnailManager {
    public static let shared = ThumbnailManager()

    private let generator = QLThumbnailGenerator.shared
    private let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200  // 最多缓存 200 个缩略图
        return cache
    }()

    /// 任务 F11-7: NSWorkspace.shared.icon(forFile:) 的应用层缓存。
    /// NSWorkspace 内部虽有缓存，但在主线程同步调用仍会触发 LaunchServices 查询，
    /// 大目录下 tableView(_:viewFor:row:) 每行都调用会造成明显卡顿。
    /// 此缓存命中时为纯内存查找，O(1)，彻底消除主线程同步调用。
    /// key 为文件绝对路径，value 为已缩放到 iconPointSize 的多色非模板图标副本。
    private let workspaceIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500  // 最多缓存 500 个工作区图标
        return cache
    }()

    /// 任务 F11-7: 异步获取工作区图标时的活跃请求去重表。
    /// 同一路径若已有后台请求在飞，新调用直接复用，避免重复触发 NSWorkspace 调用。
    /// value 中的 completion 数组在请求完成后被一次性清空并回调。
    private var inflightIconRequests: [String: [(NSImage?) -> Void]] = [:]
    private let iconLock = NSLock()

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
    ///
    /// 任务 F11-7: 磁盘缓存读取（NSImage(contentsOf:)）改为后台队列执行。
    /// 原实现中 loadFromDiskCache 在调用线程同步执行，首次未命中内存缓存时
    /// 会在主线程（tableView viewFor / collectionView itemFor）做同步文件 I/O，
    /// 大目录下叠加多个 cell 同时未命中即造成主线程卡顿。现仅在内存命中时同步返回，
    /// 其余路径（磁盘 / 生成）全部异步，completion 始终在主线程回调。
    public func generateThumbnail(
        path: String,
        size: CGSize = CGSize(width: 64, height: 64),
        completion: @escaping (NSImage?) -> Void
    ) {
        let cacheKey = cacheKey(for: path, size: size)

        // 1. 查内存缓存（命中才同步返回，避免主线程 I/O）
        if let cached = memoryCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        // 2. 磁盘缓存 / 3. 生成 全部放到后台队列，主线程回调
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // 2. 查磁盘缓存（后台线程）
            if let diskImage = self.loadFromDiskCache(path: path, cacheKey: cacheKey as String) {
                self.memoryCache.setObject(diskImage, forKey: cacheKey)
                DispatchQueue.main.async { completion(diskImage) }
                return
            }

            // 任务 F8: 调试日志（v0.6.5）
            FFLog.debug("[Thumb] 请求生成: \(path) size=\(size)", log: FFLog.thumbnail)

            // 3. 异步生成（QLThumbnailGenerator 本身异步，但请求构建移到后台）
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let request = QLThumbnailGenerator.Request(
                fileAt: URL(fileURLWithPath: path),
                size: size,
                scale: scale,
                // 任务 F10-9: representationTypes 改为 .all，无缩略图文件类型回退到图标
                representationTypes: .all
            )

            let reqRef = request

            // 记录活跃请求
            self.lock.lock()
            self.activeRequests[path] = reqRef
            self.lock.unlock()

            self.generator.generateBestRepresentation(for: request) { [weak self] thumbnail, error in
                // 请求完成（无论成功/失败）都必须从 activeRequests 移除，避免泄漏 Request 对象。
                self?.lock.lock()
                self?.activeRequests.removeValue(forKey: path)
                self?.lock.unlock()

                if let error = error {
                    FFLog.error("[Thumb] 生成失败: \(path) - \(error.localizedDescription)", log: FFLog.thumbnail)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                guard let thumbnail = thumbnail else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                // 任务 F10-9: 修正 NSImage.size 用请求的 point size（v0.6.5）
                // 原代码用 cgImage 像素尺寸（Retina 下翻倍），导致 NSImage.size 翻倍、
                // 绘制时被按 point size 缩放，最终缩略图模糊（问题7）。
                // 改为传入的 size（point size），与请求尺寸一致。
                let image = NSImage(
                    cgImage: thumbnail.cgImage,
                    size: size  // 用请求的 point size，非 cgImage 像素尺寸
                )
                FFLog.debug("[Thumb] 生成成功: \(path) \(thumbnail.cgImage.width)x\(thumbnail.cgImage.height)", log: FFLog.thumbnail)

                // 写入缓存
                self?.memoryCache.setObject(image, forKey: cacheKey)
                self?.saveToDiskCache(image: image, path: path, cacheKey: cacheKey as String)

                DispatchQueue.main.async { completion(image) }
            }
        }
    }

    /// 任务 F11-7: 同步获取缓存中的工作区图标（不触发 NSWorkspace 调用）。
    /// 用于 tableView(_:viewFor:) / collectionView item 回调中即时取占位图标，
    /// 命中则同步显示，未命中则调用 fetchWorkspaceIcon 异步获取。
    /// - Parameters:
    ///   - path: 文件绝对路径
    ///   - pointSize: 期望 point size（默认 18，与 FileListView 文件图标一致）
    /// - Returns: 已缓存的工作区图标（已缩放到 pointSize），未命中返回 nil
    public func cachedWorkspaceIcon(for path: String, pointSize: CGFloat = 18) -> NSImage? {
        let key = workspaceIconCacheKey(for: path, pointSize: pointSize)
        return workspaceIconCache.object(forKey: key)
    }

    /// 任务 F11-7: 异步获取工作区图标（NSWorkspace.shared.icon(forFile:)）。
    /// 命中内存缓存时同步回调（仍 dispatch 到主线程，保持调用方一致性）；
    /// 未命中则后台队列调用 NSWorkspace.shared.icon 并写入缓存，主线程回调。
    /// 同一路径的并发请求会去重合并（inflightIconRequests），避免重复触发。
    ///
    /// 注意：NSWorkspace.shared.icon(forFile:) 在文档上未明确线程安全，实测在后台
    /// 队列调用稳定（macOS 12+），且 Apple 自家 QLThumbnailGenerator 内部也会在
    /// 后台访问工作区图标。若未来 SDK 行为变化，可回退为主线程调用 + 缓存。
    /// - Parameters:
    ///   - path: 文件绝对路径
    ///   - pointSize: 期望 point size（默认 18）
    ///   - completion: 完成回调（主线程），传入已缩放的图标，失败/路径不存在返回 nil
    public func fetchWorkspaceIcon(
        for path: String,
        pointSize: CGFloat = 18,
        completion: @escaping (NSImage?) -> Void
    ) {
        let key = workspaceIconCacheKey(for: path, pointSize: pointSize)

        // 1. 内存命中：直接回调
        if let cached = workspaceIconCache.object(forKey: key) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        // 2. 去重：若该路径已有在飞请求，追加 completion 后返回
        iconLock.lock()
        if var existing = inflightIconRequests[path] {
            existing.append(completion)
            inflightIconRequests[path] = existing
            iconLock.unlock()
            return
        }
        inflightIconRequests[path] = [completion]
        iconLock.unlock()

        // 3. 后台队列调用 NSWorkspace.shared.icon
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let image: NSImage? = {
                // 路径不存在时 NSWorkspace 仍会返回通用图标，但 LaunchServices 查询更慢；
                // 先做轻量存在性检查，不存在则返回 nil 让调用方回退到占位图标。
                // （目录/文件都覆盖；symlink 走 FileManager.fileExists 默认行为）
                if !FileManager.default.fileExists(atPath: path) { return nil }
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: pointSize, height: pointSize)
                return icon
            }()

            if let image = image {
                self.workspaceIconCache.setObject(image, forKey: key)
            }

            // 4. 取出所有等待的 completion，主线程一次性回调
            self.iconLock.lock()
            let completions = self.inflightIconRequests.removeValue(forKey: path) ?? []
            self.iconLock.unlock()

            DispatchQueue.main.async {
                for cb in completions { cb(image) }
            }
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

    // MARK: - Private

    private func cacheKey(for path: String, size: CGSize) -> NSString {
        return "\(path)_\(Int(size.width))x\(Int(size.height))" as NSString
    }

    /// 任务 F11-7: 工作区图标缓存的 key。
    /// 与缩略图 cacheKey 分离，避免不同 pointSize 的图标互相覆盖。
    private func workspaceIconCacheKey(for path: String, pointSize: CGFloat) -> NSString {
        return "wsicon_\(path)_\(Int(pointSize))" as NSString
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
