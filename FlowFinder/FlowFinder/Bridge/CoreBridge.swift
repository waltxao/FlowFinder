import Foundation

// MARK: - CoreBridge Error Types

/// Errors that can occur during CoreBridge operations
public enum CoreBridgeError: Error, LocalizedError {
    case ffiError(String)
    case invalidPath(String)
    case rustCoreNotLoaded
    case stringConversionFailed
    /// 目录列举等待 FFI 结果超时（活体死锁热修）：消息原样透出给错误浮层
    case directoryListTimeout(String)

    public var errorDescription: String? {
        switch self {
        case .ffiError(let message):
            return "FFI Error: \(message)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .rustCoreNotLoaded:
            return "Rust core library not loaded"
        case .stringConversionFailed:
            return "Failed to convert string to C string"
        case .directoryListTimeout(let message):
            return message
        }
    }
}

// MARK: - AI Generated Tag

/// AI 生成的标签（由 Rust 规则分类引擎产出，JSON 解码得到）。
/// 与 `Tag` 结构体不同，`GeneratedTag` 无 `id` 字段——在写入 xattr 时
/// 由调用方生成 UUID。
public struct GeneratedTag: Codable {
    /// 标签显示名称（如 "图片"、"视频"）
    public let name: String
    /// 标签颜色（hex 格式，如 "#FF6B35"）
    public let color: String
    /// 分类标识符（如 "image"、"video"）
    public let category: String
}

// MARK: - Thread-Safe Result Wrapper

/// Thread-safe wrapper for FFI results
private final class ThreadSafeFFIResult<T> {
    private var value: T?
    private let lock = NSLock()

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}

// MARK: - FFI Callbacks (Global C Functions)

/// Callback function called by Rust for each directory entry
private func entryCallback(
    _ entryRefPtr: UnsafeRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let entryRefPtr = entryRefPtr,
          let userData = userData else { return }

    let entryRef = entryRefPtr.assumingMemoryBound(to: FFEntryRef.self)
    let context = userData.assumingMemoryBound(to: EntryCollectorContext.self)
    let entry = FileEntry(from: entryRef.pointee)
    context.pointee.entries.append(entry)
}

/// FSEvents 变更通知回调上下文：持有 changeHandler 闭包
private final class FSEventsContext {
    let changeHandler: (String) -> Void
    init(changeHandler: @escaping (String) -> Void) {
        self.changeHandler = changeHandler
    }
}

/// FSEvents 变更通知回调：从 userData 恢复上下文并调用 changeHandler
private func fseventsCallback(
    _ path: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let path = path, let userData = userData else { return }
    let context = Unmanaged<FSEventsContext>.fromOpaque(userData).takeUnretainedValue()
    let pathString = String(cString: path)
    context.changeHandler(pathString)
}

/// Callback for thumbnail generation
private func thumbnailCallback(
    _ thumbnailPath: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let thumbnailPath = thumbnailPath,
          let userData = userData else { return }

    let context = userData.assumingMemoryBound(to: ThumbnailContext.self)
    let path = String(cString: thumbnailPath)
    // 确保 completion 始终在主线程回调（FFI 回调可能来自后台线程）
    let completion = context.pointee.completion
    DispatchQueue.main.async {
        completion(path)
    }
}

/// Callback for task list
private func taskListCallback(
    _ taskInfoPtr: UnsafeRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let taskInfoPtr = taskInfoPtr,
          let userData = userData else { return }

    let context = userData.assumingMemoryBound(to: TaskListContext.self)
    let taskInfo = taskInfoPtr.assumingMemoryBound(to: FFTaskInfo.self)
    let task = TaskInfo(from: taskInfo.pointee)
    context.pointee.tasks.pointee.append(task)
}

/// Callback for volume list
private func volumeListCallback(
    _ volumeInfoPtr: UnsafeRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let volumeInfoPtr = volumeInfoPtr,
          let userData = userData else { return }

    let context = userData.assumingMemoryBound(to: VolumeListContext.self)
    let volumeInfo = volumeInfoPtr.assumingMemoryBound(to: FFVolumeInfo.self)
    let volume = VolumeInfo(from: volumeInfo.pointee)
    context.pointee.volumes.pointee.append(volume)
}

// MARK: - Callback Contexts

/// Context for collecting directory entries via callback
private struct EntryCollectorContext {
    var entries: [FileEntry] = []
}

/// Context for thumbnail generation callback
private struct ThumbnailContext {
    let completion: (String?) -> Void
}

/// Context for task list callback
private struct TaskListContext {
    let tasks: UnsafeMutablePointer<[TaskInfo]>
}

/// Box holding an optional Swift progress closure for parallel batch operations.
/// Stored on the heap so a `@convention(c)` FFI callback can recover it via
/// `Unmanaged` and invoke the closure from worker threads.
private final class ProgressBox {
    let handler: ((Int, Int) -> Void)?
    init(handler: ((Int, Int) -> Void)?) { self.handler = handler }
}

/// Context for volume list callback
private struct VolumeListContext {
    let volumes: UnsafeMutablePointer<[VolumeInfo]>
}

// MARK: - CoreBridge

/// Thread-safe bridge for communicating with the Rust core via FFI
public final class CoreBridge {

    // MARK: - Singleton

    /// Shared instance of CoreBridge
    static let shared = CoreBridge()

    // MARK: - Properties

    /// Thread-safe access to the last error message
    private let lastErrorMessage = ThreadSafeFFIResult<String>()

    /// Serial queue for FFI operations to ensure thread safety
    private let ffiQueue = DispatchQueue(label: "com.flowfinder.ffi", qos: .userInitiated)

    /// 目录列举专用并发队列（活体死锁热修）：ff_list_dir 为无共享状态的纯函数
    /// （路径进、条目出，Rust 侧经审计确认无锁），独立队列防止慢目录
    /// （iCloud/网络盘卡住的阻塞 syscall）冻结共享 ffiQueue 波及全部 FFI
    /// （实测 iCloud Desktop 卡顿曾致全局死锁）。并发属性使一个慢目录只占用
    /// 一个工作线程，不连累其他目录的列举。Rust 侧 L1/L2 缓存自带内部锁
    /// （dir_cache Mutex / sqlite 连接池 Mutex），与其他队列上的
    /// ff_cache_invalidate 并发安全（终审复核确认）。
    private static let directoryListQueue = DispatchQueue(label: "com.flowfinder.dirlist", qos: .userInitiated, attributes: .concurrent)

    /// FSEvents watcher 句柄（由 ff_fsevents_start 返回）
    private var fseventsWatcherHandle: Int32 = 0

    /// FSEvents 回调上下文（持有 changeHandler 闭包，防止被释放）
    private var fseventsContext: FSEventsContext?

    /// FSEvents watcher 生命周期专用串行队列（Wave1 P0-1）：
    /// 「stop 旧 watcher + start 新 watcher + 等握手」整体在此后台执行，
    /// 主线程不再同步等待握手（ff_fsevents_start 内部握手最长可等 10s）。
    /// 串行保证先后两次 start 按序完成，避免旧 context 被并发覆盖导致 use-after-free。
    private let fseventsLifecycleQueue = DispatchQueue(label: "com.flowfinder.fsevents.lifecycle", qos: .userInitiated)

    /// FSEvents watcher 状态缓存（Wave1 P0-1）：由启动/停止流程在握手完成后于
    /// 后台线程写入，任意线程（含主线程）读取零阻塞。取代旧实现
    /// fseventsWatcherStatus() 的 ffiQueue.sync 轮询（主线程查询需等待 FFI）。
    private let fseventsStatusCache = ThreadSafeFFIResult<FSEventsStatus>()

    // MARK: - Initialization

    private init() {}

    // MARK: - Directory Operations

    /// List directory contents via FFI
    ///
    /// Two-tier cache lookup: the L1 (in-memory) and L2 (SQLite persistent)
    /// caches are consulted first via `ff_cache_get`. On a cache hit the
    /// entries are delivered directly from the cache, skipping the live
    /// filesystem scan. On a cache miss the directory is scanned with
    /// `ff_list_dir` and, on success, the result is written back to the
    /// cache via `ff_cache_put` so subsequent navigations hit the cache.
    /// - Parameter path: Directory path to list
    /// - Returns: Array of FileEntry objects
    /// - Throws: CoreBridgeError if operation fails
    func listDirectory(path: String) throws -> [FileEntry] {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath(path)
        }

        // Verify path exists
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else {
            throw CoreBridgeError.invalidPath("Path does not exist: \(path)")
        }

        var entries: [FileEntry] = []

        // 目录列举走专用并发队列（directoryListQueue），不再进共享 ffiQueue：
        // 慢目录（iCloud/网络盘）的阻塞 syscall 不得拖累其余 FFI 操作。
        var ffiResult: Int32 = -1
        var ffiEntries: [FileEntry] = []

        // 等待 FFI 结果（活体死锁热修：10 秒超时兜底——阻塞 syscall 无法中断，
        // 超时后卡住的队列线程泄漏属可接受代价，见 wave1 报告）
        let semaphore = DispatchSemaphore(value: 0)

        Self.directoryListQueue.async {
            defer { semaphore.signal() }

            // ── L1 + L2 cache lookup ───────────────────────────────────
            // ff_cache_get delivers cached entries through the same
            // entryCallback used by ff_list_dir. A return of FF_OK (0) with
            // a non-empty entry list is a cache hit — skip the live scan.
            // Any other return (including FF_ERR_NOT_FOUND) is a miss.
            var cacheContext = EntryCollectorContext()
            cacheContext.entries = []
            let cacheResult = path.withCString { cPath in
                withUnsafeMutablePointer(to: &cacheContext) { contextPtr in
                    ff_cache_get(cPath, entryCallback, contextPtr)
                }
            }

            if cacheResult == 0 && !cacheContext.entries.isEmpty {
                // Cache hit — use the cached entries directly.
                ffiResult = 0
                ffiEntries = cacheContext.entries
                FFDebug.log("[CACHE-DIAG] listDirectory: 缓存命中 path=\(path) entries=\(cacheContext.entries.count) 首项=\(cacheContext.entries.first?.name ?? "nil")")
                return
            }
            FFDebug.log("[CACHE-DIAG] listDirectory: 缓存未命中，实时扫描 path=\(path) cacheResult=\(cacheResult)")

            // ── Cache miss — live scan via ff_list_dir ─────────────────
            var scanContext = EntryCollectorContext()
            scanContext.entries = []
            let result = path.withCString { cPath in
                withUnsafeMutablePointer(to: &scanContext) { contextPtr in
                    ff_list_dir(cPath, entryCallback, contextPtr)
                }
            }

            ffiResult = result
            ffiEntries = scanContext.entries

            // On a successful scan, populate the cache (best-effort) so the
            // next navigation hits the cache. Failures are swallowed —
            // cache write errors must not break directory listing.
            if result == 0 && !scanContext.entries.isEmpty {
                self.populateCache(path: path, entries: scanContext.entries)
            }
        }

        let waitOutcome = semaphore.wait(timeout: .now() + 10)

        guard waitOutcome == .success else {
            // 超时兜底（活体死锁热修）：本线程立即抛错返回，调用方（PaneState
            // loadDirectory 的 catch）会回主线程清除 isLoading 并走既有错误浮层。
            // 迟到的列举结果因等待线程已解除等待而永远不会被消费（结构性丢弃），
            // 用户重试导航时 loadGeneration 代次守卫会再兜一层。
            throw CoreBridgeError.directoryListTimeout("目录读取超时")
        }

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }

        entries = ffiEntries

        // 大目录优化：移除此处冗余排序。
        // PaneState.sortEntries 已包含"文件夹优先 + 用户排序字段"逻辑，
        // 此处排序结果会被 PaneState 覆盖，造成 O(n log n) 浪费。
        // 缓存写入（populateCache）不依赖排序顺序。

        return entries
    }

    /// Best-effort cache population. Builds an `FFEntryRef` array (with
    /// heap-allocated C strings) from `entries` and calls `ff_cache_put`.
    /// All allocations are freed before returning; cache write failures
    /// are silently ignored — navigation must not fail because the cache
    /// could not be written.
    private func populateCache(path: String, entries: [FileEntry]) {
        var refs: [FFEntryRef] = []
        refs.reserveCapacity(entries.count)
        var allocated: [UnsafeMutablePointer<CChar>] = []
        allocated.reserveCapacity(entries.count * 3)

        for entry in entries {
            guard let namePtr = strdup(entry.name),
                  let pathPtr = strdup(entry.path),
                  let extPtr = strdup(entry.fileExtension) else {
                // Allocation failed — free what we have and bail out
                // (best-effort: skip caching this directory).
                for p in allocated { free(p) }
                return
            }
            allocated.append(namePtr)
            allocated.append(pathPtr)
            allocated.append(extPtr)

            refs.append(FFEntryRef(
                name: namePtr,
                path: pathPtr,
                `extension`: extPtr,
                isDir: entry.isDirectory,
                isFile: entry.isFile,
                isSymlink: entry.isSymlink,
                isHidden: entry.isHidden,
                isSystemProtected: entry.isSystemProtected,
                size: entry.size,
                modified: Int64(entry.modificationDate.timeIntervalSince1970),
                created: Int64(entry.creationDate.timeIntervalSince1970)
            ))
        }

        // ff_cache_put copies the entries into Rust-owned memory, so the
        // C strings we allocated are safe to free immediately after the call.
        let _ = path.withCString { cPath in
            refs.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                ff_cache_put(cPath, baseAddress, refs.count)
            }
        }

        for p in allocated { free(p) }
    }

    // MARK: - File Operations

    /// Copy a file from src to dst
    /// - Parameters:
    ///   - src: Source file path
    ///   - dst: Destination file path
    /// - Throws: CoreBridgeError if operation fails
    func copyFile(src: String, dst: String) throws {
        guard !src.isEmpty, !dst.isEmpty else {
            throw CoreBridgeError.invalidPath("Source or destination path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = src.withCString { cSrc in
                dst.withCString { cDst in
                    ff_copy_file(cSrc, cDst)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Move a file or directory from src to dst
    /// - Parameters:
    ///   - src: Source path
    ///   - dst: Destination path
    /// - Throws: CoreBridgeError if operation fails
    func moveFile(src: String, dst: String) throws {
        guard !src.isEmpty, !dst.isEmpty else {
            throw CoreBridgeError.invalidPath("Source or destination path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = src.withCString { cSrc in
                dst.withCString { cDst in
                    ff_move_file(cSrc, cDst)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Delete a file at path
    /// - Parameter path: File path to delete
    /// - Throws: CoreBridgeError if operation fails
    func deleteFile(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_delete_file(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Delete a directory and all its contents at path
    /// - Parameter path: Directory path to delete
    /// - Throws: CoreBridgeError if operation fails
    func deleteDirectory(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_delete_dir(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Create a directory and all parent directories at path
    /// - Parameter path: Directory path to create
    /// - Throws: CoreBridgeError if operation fails
    func createDirectory(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_create_dir(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Rename a file or directory from src to dst
    /// - Parameters:
    ///   - src: Source path
    ///   - dst: Destination path
    /// - Throws: CoreBridgeError if operation fails
    func renameFile(src: String, dst: String) throws {
        guard !src.isEmpty, !dst.isEmpty else {
            throw CoreBridgeError.invalidPath("Source or destination path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = src.withCString { cSrc in
                dst.withCString { cDst in
                    ff_rename(cSrc, cDst)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    // MARK: - Parallel Batch File Operations

    /// No-op C callback used when the caller does not supply a progress handler.
    private static let noopBatchProgress: FFBatchProgressCallback = { _, _, _, _ in }

    /// Parallel copy multiple files into a destination directory (rayon-backed).
    ///
    /// Each source file is copied (CoW when possible) into `dstDir` keeping its
    /// basename. Partial failures are reported via the return value.
    ///
    /// - Parameters:
    ///   - srcs: Array of source file paths.
    ///   - dstDir: Destination directory path.
    ///   - progress: Optional `(completed, total)` callback invoked from worker threads.
    /// - Returns: Number of successfully copied files.
    /// - Throws: `CoreBridgeError.ffiError` if FFI returns a negative error code.
    func parallelCopy(srcs: [String], dstDir: String, progress: ((Int, Int) -> Void)? = nil) throws -> Int {
        guard !dstDir.isEmpty else {
            throw CoreBridgeError.invalidPath("Destination directory is empty")
        }
        if srcs.isEmpty { return 0 }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        // Allocate C string pointers (`strdup`) so the array remains valid
        // across the FFI call. Cleanup happens after `semaphore.wait()`.
        let cStringPtrs: [UnsafeMutablePointer<CChar>?] = srcs.map { strdup($0) }
        defer {
            for p in cStringPtrs { if let p = p { free(p) } }
        }

        // Bridge the optional Swift closure to a C function pointer via a
        // context box. When `progress` is nil, a no-op callback is used.
        let progressBox = ProgressBox(handler: progress)
        let progressCallback: FFBatchProgressCallback = { completed, total, _, userData in
            guard let userData = userData else { return }
            let box = Unmanaged<ProgressBox>.fromOpaque(userData).takeUnretainedValue()
            box.handler?(completed, total)
        }

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = dstDir.withCString { cDstDir in
                cStringPtrs.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else { return Int32(0) }
                    return baseAddress.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: cStringPtrs.count) { reboundPtr in
                        ff_parallel_copy(
                            reboundPtr,
                            cStringPtrs.count,
                            cDstDir,
                            progressBox.handler != nil ? progressCallback : CoreBridge.noopBatchProgress,
                            Unmanaged.passUnretained(progressBox).toOpaque()
                        )
                    }
                }
            }
            ffiResult = result
            // I3: capture ff_last_error() on this FFI thread so callers on
            // the UI thread can retrieve partial-failure details ("N/M
            // failed: …") via getLastError(). Only stored when non-empty so
            // a fully-successful batch does not mask a later error.
            let captured = self.captureLastErrorFFI()
            if !captured.isEmpty {
                self.lastErrorMessage.set(captured)
            }
        }

        semaphore.wait()

        guard ffiResult >= 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
        return Int(ffiResult)
    }

    /// Parallel move multiple files into a destination directory (rayon-backed).
    ///
    /// Same semantics as `parallelCopy`, but moves files instead. Falls back
    /// to copy-then-delete for cross-volume moves.
    func parallelMove(srcs: [String], dstDir: String, progress: ((Int, Int) -> Void)? = nil) throws -> Int {
        guard !dstDir.isEmpty else {
            throw CoreBridgeError.invalidPath("Destination directory is empty")
        }
        if srcs.isEmpty { return 0 }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        let cStringPtrs: [UnsafeMutablePointer<CChar>?] = srcs.map { strdup($0) }
        defer {
            for p in cStringPtrs { if let p = p { free(p) } }
        }

        let progressBox = ProgressBox(handler: progress)
        let progressCallback: FFBatchProgressCallback = { completed, total, _, userData in
            guard let userData = userData else { return }
            let box = Unmanaged<ProgressBox>.fromOpaque(userData).takeUnretainedValue()
            box.handler?(completed, total)
        }

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = dstDir.withCString { cDstDir in
                cStringPtrs.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else { return Int32(0) }
                    return baseAddress.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: cStringPtrs.count) { reboundPtr in
                        ff_parallel_move(
                            reboundPtr,
                            cStringPtrs.count,
                            cDstDir,
                            progressBox.handler != nil ? progressCallback : CoreBridge.noopBatchProgress,
                            Unmanaged.passUnretained(progressBox).toOpaque()
                        )
                    }
                }
            }
            ffiResult = result
            // I3: capture ff_last_error() on this FFI thread so callers on
            // the UI thread can retrieve partial-failure details ("N/M
            // failed: …") via getLastError(). Only stored when non-empty so
            // a fully-successful batch does not mask a later error.
            let captured = self.captureLastErrorFFI()
            if !captured.isEmpty {
                self.lastErrorMessage.set(captured)
            }
        }

        semaphore.wait()

        guard ffiResult >= 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
        return Int(ffiResult)
    }

    // MARK: - Cache Operations

    /// Initialize the L2 persistent (SQLite) directory cache.
    ///
    /// Must be called once at app startup with a writable filesystem path.
    /// After this call succeeds, `ff_cache_get`/`ff_cache_put`/`ff_cache_invalidate`
    /// additionally consult/persist to the SQLite database (best-effort).
    /// Safe to call multiple times — subsequent calls are no-ops if already
    /// initialized.
    /// - Parameter dbPath: Filesystem path to the SQLite database file
    /// - Throws: CoreBridgeError if initialization fails
    func initCache(dbPath: String) throws {
        guard !dbPath.isEmpty else {
            throw CoreBridgeError.invalidPath("dbPath is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }
            let result = dbPath.withCString { cPath in
                ff_cache_init(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Invalidate the directory cache for a specific path
    /// - Parameter path: Directory path to invalidate
    /// - Throws: CoreBridgeError if operation fails
    func invalidateCache(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }
            let result = path.withCString { cPath in
                ff_cache_invalidate(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// 异步失效目录缓存：不阻塞主线程；完成后回主线程回调。
    /// 用于「先失效再重新加载」的刷新路径，保持顺序而不让 UI 等 FFI。
    func invalidateCacheAsync(path: String, completion: (() -> Void)? = nil) {
        guard !path.isEmpty else {
            DispatchQueue.main.async { completion?() }
            return
        }
        ffiQueue.async {
            _ = path.withCString { ff_cache_invalidate($0) }
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    // MARK: - FSEvents Watcher (Sub-project 5)

    /// Start watching a path for filesystem changes（Wave1 P0-1：启动握手异步化）
    ///
    /// 旧实现在调用线程（主线程）上用 semaphore 同步等待「stop 旧 watcher +
    /// ff_fsevents_start + 状态确认」全流程，而 ff_fsevents_start 内部握手
    /// （rust-core fsevents.rs SETUP_TIMEOUT）最长可等 10s，高负载/网络目录下
    /// 会冻结主线程。现把整个生命周期流程放入专用后台串行队列
    /// fseventsLifecycleQueue：主线程立即返回，completion 固定回主线程上报
    /// active（成功）或 failed（失败）；失败路径与旧实现的 throw → 上层错误
    /// 日志链路一致，保持可观察。
    ///
    /// - Parameters:
    ///   - path: Directory path to watch
    ///   - changeHandler: Called when a change is detected（Rust worker 线程触发，
    ///     调用方需自行切回主线程处理 UI）
    ///   - completion: 主线程回调，上报启动结果（成功 = watcher 已进入 active）
    func startFSEventsWatcher(path: String,
                              changeHandler: @escaping (String) -> Void,
                              completion: @escaping (Result<Void, Error>) -> Void) {
        guard !path.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(CoreBridgeError.invalidPath("Path is empty")))
            }
            return
        }

        fseventsLifecycleQueue.async { [weak self] in
            guard let self = self else { return }

            // 防止重复启动：若已有 watcher 运行（context 或 handle 非空），先停止。
            // 否则旧 context 会被下面 `self.fseventsContext = context` 覆盖并释放，
            // 而 Rust 侧仍持有旧 context 的 userData 指针，导致 use-after-free。
            // 整段流程在串行生命周期队列上执行：stop 完成后才继续 start。
            if self.fseventsContext != nil || self.fseventsWatcherHandle != 0 {
                self.stopFSEventsWatcher()
            }

            // 创建上下文并保留引用，防止被释放
            let context = FSEventsContext(changeHandler: changeHandler)
            self.fseventsContext = context
            // passUnretained：不增加 retain count，依赖 self.fseventsContext 的强引用保持存活。
            // stopFSEventsWatcher 会先调用 ff_fsevents_stop（Rust 清理状态、停止回调），
            // 再置空 self.fseventsContext，确保回调期间 context 不会被释放。
            let contextPtr = Unmanaged.passUnretained(context).toOpaque()

            // 活体死锁热修：fsevents FFI 自带独立线程与内部状态锁（WATCHER_STATUS），
            // 与 list_dir 无共享，直接在本生命周期队列上调用，避免列举卡死拖死
            // watcher 生命周期（原实现经共享 ffiQueue + semaphore 中转，慢目录
            // 列举冻结 ffiQueue 时 start/stop 会被永久卡住）。
            let ffiResult: Int32 = path.withCString { cPath in
                ff_fsevents_start(cPath, fseventsCallback, contextPtr)
            }
            // 握手返回时 Rust 侧状态已定格（active/failed/stopped），随即读取
            // （写入状态缓存用）。
            let statusRaw: Int32 = ff_fsevents_status()

            // 成功契约：ff_error_t 中负值表示错误（FF_ERR_INVALID_PATH = -2 等），
            // 非负值（>= 0）表示成功。当前 Rust 实现返回 0，但若未来 Rust 改为
            // 返回正数 handle，此处 >= 0 仍能正确接受并把返回值作为 handle 存储。
            let status = FSEventsStatus(rawValue: statusRaw) ?? .failed
            guard ffiResult >= 0, status == .active else {
                self.fseventsContext = nil
                self.fseventsWatcherHandle = 0
                // 状态缓存如实记录观测值（failed/stopped），失败保持可观察
                self.fseventsStatusCache.set(status)
                // 旧实现此处 throw（"did not reach active state" / FFI 错误），
                // 异步化后经主线程 completion 上报，上层错误日志链路不变
                let errorMessage = ffiResult >= 0
                    ? "FSEvents watcher did not reach active state"
                    : getLastError()
                DispatchQueue.main.async {
                    completion(.failure(CoreBridgeError.ffiError(errorMessage)))
                }
                return
            }

            // 存储 ff_fsevents_start 返回的真实 handle（当前实现为 0，未来可能为正数），
            // stopFSEventsWatcher 会使用此 handle 调用 ff_fsevents_stop。
            self.fseventsWatcherHandle = ffiResult
            self.fseventsStatusCache.set(.active)

            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    /// Stop the FSEvents watcher
    ///
    /// Wave1 P0-1：改为 private——全工程唯一调用方是 startFSEventsWatcher 的
    /// 后台生命周期流程。必须在 fseventsLifecycleQueue 上调用（context/handle/
    /// 状态缓存的访问由该队列串行化）；本方法阻塞当前线程直至 ff_fsevents_stop
    /// 返回（Rust 侧已 join worker，返回后不再有任何回调）。
    private func stopFSEventsWatcher() {
        let handle = self.fseventsWatcherHandle

        // 活体死锁热修：直接在本生命周期队列上调用 stop（理由同 startFSEventsWatcher），
        // 不再经共享 ffiQueue + semaphore 中转。
        // 使用 startFSEventsWatcher 存储的真实 handle（而非硬编码 0），
        // 确保 Rust 侧能正确识别要停止的 watcher。
        // 显式标注 Int32：ff_fsevents_stop 同时存在 C 头文件与 @_silgen_name
        // 两份声明，无类型上下文的裸调用会因二义性编译失败。
        let stopResult: Int32 = ff_fsevents_stop(handle)
        // 0 = 有 watcher 已停止；-1 = 本就无 watcher（幂等 stop 的合法情形），
        // 两种结果均已保证 Rust 侧不再产生回调，无需按错误处理
        _ = stopResult
        // stop 返回后状态已定格，读取以更新状态缓存
        // （显式标注 Int32：ff_fsevents_status 同样存在两份声明，需类型上下文消歧）
        let statusRaw: Int32 = ff_fsevents_status()

        // 清理上下文和句柄：必须在 ff_fsevents_stop 返回之后（Rust 已停止回调），
        // 否则并发回调可能访问已释放的 context。
        self.fseventsContext = nil
        self.fseventsWatcherHandle = 0
        self.fseventsStatusCache.set(FSEventsStatus(rawValue: statusRaw) ?? .stopped)
    }

    /// 查询 FSEvents watcher 生命周期状态（区分 failed 与 active）。
    /// Wave1 P0-1：改为读取后台维护的状态缓存（启动/停止流程在握手完成后写入），
    /// 不再 ffiQueue.sync——主线程调用零阻塞，也杜绝了对共享 ffiQueue 的干扰。
    func fseventsWatcherStatus() -> FSEventsStatus {
        fseventsStatusCache.get() ?? .stopped
    }

    // MARK: - Batch Rename & Organize (Sub-project 6)

    /// Batch rename files
    /// - Parameters:
    ///   - items: Array of (originalPath, newName) tuples
    /// - Returns: Number of successful renames
    /// - Throws: CoreBridgeError if operation fails
    func batchRename(items: [(String, String)]) throws -> Int {
        guard !items.isEmpty else {
            throw CoreBridgeError.invalidPath("Items array is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        // Convert items to C-compatible format
        var cItems: [FFRenameItem] = []
        var allocated: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = []
        for (original, newName) in items {
            // strdup 在内存不足时可能返回 nil，避免强制解包导致崩溃。
            let originalPtr = strdup(original)
            let newNamePtr = strdup(newName)
            guard let op = originalPtr, let np = newNamePtr else {
                // 分配失败：释放本次已分配的单个字符串，以及之前累积的所有字符串。
                if let opToFree = originalPtr { free(opToFree) }
                if let npToFree = newNamePtr { free(npToFree) }
                for (a, b) in allocated { free(a); free(b) }
                throw CoreBridgeError.ffiError("内存分配失败：strdup 返回 nil")
            }
            allocated.append((op, np))
            cItems.append(FFRenameItem(originalPath: op, newName: np))
        }

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = cItems.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return Int32(0) }
                return ff_batch_rename(baseAddress, cItems.count)
            }
            ffiResult = result
        }

        semaphore.wait()

        // Free allocated strings
        for item in cItems {
            free(item.originalPath)
            free(item.newName)
        }

        guard ffiResult >= 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }

        return Int(ffiResult)
    }

    // MARK: - Thumbnail Generation (Sub-project 7)

    /// Generate a thumbnail for an image file
    /// - Parameters:
    ///   - path: Image file path
    ///   - maxSize: Maximum width/height of the thumbnail
    ///   - completion: Called with the thumbnail path on success
    /// - Throws: CoreBridgeError if operation fails
    func generateThumbnail(path: String, maxSize: UInt32, completion: @escaping (String?) -> Void) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        ffiQueue.async {
            var context = ThumbnailContext(completion: completion)

            let result = path.withCString { cPath in
                ff_generate_thumbnail(cPath, maxSize, thumbnailCallback, &context)
            }

            if result != 0 {
                _ = self.getLastError()
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Error Handling

    /// Get the last error message from the Rust core.
    ///
    /// Rust stores `last_error` in thread-local storage, so a direct
    /// `ff_last_error()` call only returns a value when called on the same
    /// thread that ran the FFI function. Because every CoreBridge FFI call
    /// runs on the serial `ffiQueue`, calling `ff_last_error()` from the
    /// UI thread returns nothing.
    ///
    /// To bridge that gap, the parallel batch methods (parallelCopy /
    /// parallelMove) capture `ff_last_error()` on the
    /// FFI thread right after the call and stash the result in
    /// `lastErrorMessage`. This getter prefers that captured value
    /// (read-once: it is cleared after being returned so subsequent calls
    /// do not observe a stale message) and falls back to a direct
    /// `ff_last_error()` call for non-parallel methods.
    /// - Returns: Error message string
    func getLastError() -> String {
        // Prefer the captured error from the FFI thread (set by parallel ops).
        // Read-once: clear after reading so stale messages don't leak across
        // unrelated operations.
        if let captured = lastErrorMessage.get() {
            lastErrorMessage.clear()
            if !captured.isEmpty {
                return captured
            }
        }

        guard let cString = ff_last_error() else {
            return "Unknown error"
        }

        // Safely convert C string to Swift String
        let message = String(cString: cString)

        // Free the C string allocated by Rust
        ff_free_string(UnsafeMutablePointer(mutating: cString))

        return message
    }

    /// Capture the current thread's `ff_last_error()` as a Swift String.
    /// Must be called on the same thread that ran the FFI function (i.e.
    /// inside `ffiQueue.async`). Returns an empty string when no error is
    /// set. The C string returned by Rust is freed before returning.
    private func captureLastErrorFFI() -> String {
        guard let cString = ff_last_error() else {
            return ""
        }
        let message = String(cString: cString)
        ff_free_string(UnsafeMutablePointer(mutating: cString))
        return message
    }

    // MARK: - Settings & Configuration (Sub-project 8)

    /// Get a specific setting value by key
    /// - Parameter key: Setting key
    /// - Returns: Setting value string, or empty if not found
    func getSetting(key: String) -> String {
        var resultString: String = ""
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            guard let cString = ff_settings_get(key) else {
                return
            }
            resultString = String(cString: cString)
            ff_free_string(cString)
        }

        semaphore.wait()
        return resultString
    }

    /// Set a specific setting value
    /// - Parameters:
    ///   - key: Setting key
    ///   - value: Setting value
    /// - Throws: CoreBridgeError if operation fails
    func setSetting(key: String, value: String) throws {
        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = key.withCString { cKey in
                value.withCString { cValue in
                    ff_settings_set(cKey, cValue)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    // MARK: - Task Scheduler (Sub-project 9)

    /// 取消正在运行或等待中的任务
    /// - Parameter taskId: 任务 ID 字符串
    /// - Throws: CoreBridgeError if operation fails
    func cancelTask(taskId: String) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var ffiResult: Int32 = -1

        ffiQueue.async {
            defer { semaphore.signal() }
            taskId.withCString { cTaskId in
                ffiResult = ff_task_cancel(cTaskId)
            }
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// List all tasks
    /// - Returns: Array of TaskInfo objects
    func listTasks() -> [TaskInfo] {
        var tasks: [TaskInfo] = []
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            withUnsafeMutablePointer(to: &tasks) { tasksPtr in
                var context = TaskListContext(tasks: tasksPtr)
                let _ = withUnsafeMutablePointer(to: &context) { contextPtr in
                    ff_task_list(taskListCallback, contextPtr)
                }
            }
        }

        semaphore.wait()
        return tasks
    }

    /// 清除任务历史中已完成/失败的任务（保留正在执行及取消的任务）
    /// - Throws: CoreBridgeError if operation fails
    func clearCompletedTasks() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var ffiResult: Int32 = -1

        ffiQueue.async {
            defer { semaphore.signal() }
            ffiResult = ff_task_clear_history()
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    // MARK: - Volume Management (Sub-project 10)

    /// List all mounted volumes
    /// - Returns: Array of VolumeInfo objects
    func listVolumes() -> [VolumeInfo] {
        var volumes: [VolumeInfo] = []
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            withUnsafeMutablePointer(to: &volumes) { volumesPtr in
                var context = VolumeListContext(volumes: volumesPtr)
                let _ = withUnsafeMutablePointer(to: &context) { contextPtr in
                    ff_volume_list(volumeListCallback, contextPtr)
                }
            }
        }

        semaphore.wait()
        return volumes
    }

    // MARK: - AI Tag Generation (Task 14)

    /// 为指定文件生成 AI 分类标签。
    ///
    /// 调用 Rust 规则分类引擎，根据文件扩展名、大小、是否为目录等特征
    /// 自动生成分类标签（如「图片」「视频」「大文件」「文件夹」）。
    ///
    /// - Parameter path: 文件或目录的绝对路径
    /// - Returns: 生成的标签列表（可能为空，表示文件存在但无匹配规则）
    /// - Throws: CoreBridgeError（文件不存在、路径无效、FFI 调用失败）
    func generateAITags(path: String) throws -> [GeneratedTag] {
        var resultString: String = ""
        let semaphore = DispatchSemaphore(value: 0)
        var didError = false
        var errorMessage = ""

        ffiQueue.async {
            defer { semaphore.signal() }

            let cString = path.withCString { cPath in
                ff_generate_tags(cPath)
            }

            guard let cString = cString else {
                errorMessage = self.captureLastErrorFFI()
                didError = true
                return
            }

            resultString = String(cString: cString)
            ff_free_string(cString)
        }

        semaphore.wait()

        if didError {
            throw CoreBridgeError.ffiError(errorMessage.isEmpty ? "AI 标签生成失败" : errorMessage)
        }

        // 解码 JSON 数组 → [GeneratedTag]
        guard let data = resultString.data(using: .utf8) else {
            throw CoreBridgeError.stringConversionFailed
        }

        do {
            return try JSONDecoder().decode([GeneratedTag].self, from: data)
        } catch {
            throw CoreBridgeError.ffiError("AI 标签 JSON 解码失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Entry Collector Context

}


