import Foundation

// MARK: - Duplicate Scan Bridge

/// Thread-safe bridge for duplicate file detection via FFI
public final class DuplicateScanBridge {

    public static let shared = DuplicateScanBridge()

    private let ffiQueue = DispatchQueue(label: "com.flowfinder.dedup", qos: .userInitiated)

    private init() {}

    /// Scan for duplicate files under a path
    /// - Parameters:
    ///   - path: Root directory path to scan
    ///   - progressHandler: Called with (scanned, total) progress updates
    ///   - groupHandler: Called for each duplicate group found
    ///   - completion: Called when scan completes or errors
    public func scanDuplicates(
        path: String,
        progressHandler: @escaping (Int, Int) -> Void,
        groupHandler: @escaping (FFDuplicateGroup) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        ffiQueue.async {
            // 使用 Unmanaged 管理生命周期：将 context 作为类（引用类型），
            // 通过 passRetained 增加 retain count，确保 Rust 异步回调时对象仍存活。
            // FFI 调用返回后立即 release，与 passRetained 配对，避免泄漏。
            // 即便 Rust 当前是同步调用，这也是防御性写法，避免未来 Rust 改为异步时崩溃。
            // 注意：ff_scan_duplicates 只接受单个 userData，故 progress 与 group 回调
            // 共享同一个 DedupScanContext，各自解读自己关心的字段。
            let context = DedupScanContext(
                progressHandler: progressHandler,
                groupHandler: groupHandler
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            // 必须在 FFI 返回后释放，确保同步回调期间指针有效；若 Rust 改为异步，
            // 应改为在最后一次回调中 takeRetainedValue 释放。
            defer {
                Unmanaged<DedupScanContext>.fromOpaque(contextPtr).release()
            }

            // Rust 在扫描开始前把本次扫描的句柄写入 outHandle，主线程的
            // cancelScan() 借它调用 ff_cancel_scan_by_id 只取消这一次扫描。
            // 写入是单字对齐写，跨线程读在 macOS 上是良性竞态，不会撕裂。
            let handlePtr = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
            handlePtr.initialize(to: 0)
            self.currentScanHandlePtr = handlePtr
            defer {
                self.currentScanHandlePtr = nil
                handlePtr.deallocate()
            }

            let result = path.withCString { cPath in
                ff_scan_duplicates_ex(
                    cPath,
                    dedupProgressCallback,
                    dedupGroupCallback,
                    contextPtr,
                    handlePtr
                )
            }

            if result == 0 {
                completion(nil)
            } else {
                let errorMessage = self.getLastError()
                completion(CoreBridgeError.ffiError(errorMessage))
            }
        }
    }

    /// Cancel the ongoing scan by its per-scan handle (falls back to the
    /// legacy whole-API cancel when the handle is not yet registered).
    public func cancelScan() {
        if let handlePtr = currentScanHandlePtr, handlePtr.pointee != 0 {
            ff_cancel_scan_by_id(handlePtr.pointee)
        } else {
            ff_cancel_scan()
        }
    }

    private var currentScanHandlePtr: UnsafeMutablePointer<UInt64>?

    private func getLastError() -> String {
        guard let cString = ff_last_error() else {
            return "Unknown error"
        }
        let message = String(cString: cString)
        ff_free_string(UnsafeMutablePointer(mutating: cString))
        return message
    }
}

// MARK: - Search Bridge

/// Thread-safe bridge for file search via FFI
public final class SearchBridge {

    public static let shared = SearchBridge()

    private let ffiQueue = DispatchQueue(label: "com.flowfinder.search", qos: .userInitiated)

    private init() {}

    /// Search for files matching query under path
    /// - Parameters:
    ///   - path: Root directory path
    ///   - query: Search query string
    ///   - resultHandler: Called for each matching result
    ///   - completion: Called when search completes or errors
    public func search(
        path: String,
        query: String,
        resultHandler: @escaping (FFSearchResult) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        ffiQueue.async {
            // 使用 Unmanaged.passRetained 把 context 作为引用类型保留，
            // 避免 &context 栈指针在异步回调时失效（use-after-free）。
            // FFI 返回后立即 release 配平 retain count。
            let context = SearchContext(resultHandler: resultHandler)
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            defer {
                Unmanaged<SearchContext>.fromOpaque(contextPtr).release()
            }

            // Same per-search handle box as the scan bridge: Rust writes the
            // handle before the walk starts so cancelSearch() can cancel only
            // this search via ff_cancel_search_by_id.
            let handlePtr = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
            handlePtr.initialize(to: 0)
            self.currentSearchHandlePtr = handlePtr
            defer {
                self.currentSearchHandlePtr = nil
                handlePtr.deallocate()
            }

            // ff_search (legacy) used Rust's default of 500 results; keep that
            // behaviour explicitly here with the same option values.
            var options = FFSearchOptions_C(max_results: 500, max_depth: 0)

            let result = path.withCString { cPath in
                query.withCString { cQuery in
                    withUnsafePointer(to: &options) { optPtr in
                        ff_search_ex(cPath, cQuery, optPtr, handlePtr, searchCallback, contextPtr)
                    }
                }
            }

            if result == 0 {
                completion(nil)
            } else {
                let errorMessage = self.getLastError()
                completion(CoreBridgeError.ffiError(errorMessage))
            }
        }
    }

    /// Cancel the ongoing search by its per-search handle.
    public func cancelSearch() {
        if let handlePtr = currentSearchHandlePtr, handlePtr.pointee != 0 {
            ff_cancel_search_by_id(handlePtr.pointee)
        }
    }

    private var currentSearchHandlePtr: UnsafeMutablePointer<UInt64>?

    private func getLastError() -> String {
        guard let cString = ff_last_error() else {
            return "Unknown error"
        }
        let message = String(cString: cString)
        ff_free_string(UnsafeMutablePointer(mutating: cString))
        return message
    }
}

// MARK: - Callback Contexts

/// 引用类型上下文：使用 Unmanaged.passRetained 传给 FFI 时，
/// retain count 会被增加，确保 Rust 异步回调时对象仍存活。
/// 闭包本身是引用计数类型，从 context 提取后即使 context 被释放也不会失效。

private final class DedupScanContext {
    let progressHandler: (Int, Int) -> Void
    let groupHandler: (FFDuplicateGroup) -> Void
    init(progressHandler: @escaping (Int, Int) -> Void,
         groupHandler: @escaping (FFDuplicateGroup) -> Void) {
        self.progressHandler = progressHandler
        self.groupHandler = groupHandler
    }
}

private final class SearchContext {
    let resultHandler: (FFSearchResult) -> Void
    init(resultHandler: @escaping (FFSearchResult) -> Void) {
        self.resultHandler = resultHandler
    }
}

// MARK: - C Callbacks

private func dedupProgressCallback(scanned: Int, total: Int, userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    // takeUnretainedValue：不增加 retain count，由调用方（scanDuplicates）负责 release。
    let context = Unmanaged<DedupScanContext>.fromOpaque(userData).takeUnretainedValue()
    // 在 dispatch 前提取闭包，避免 DispatchQueue.main.async 内访问 context 字段时
    // 出现延迟解引用造成的潜在 use-after-free（闭包是引用类型，捕获后自行持有）。
    let handler = context.progressHandler
    DispatchQueue.main.async {
        handler(scanned, total)
    }
}

private func dedupGroupCallback(groupPtr: UnsafeRawPointer?, userData: UnsafeMutableRawPointer?) {
    guard let groupPtr = groupPtr,
          let userData = userData else { return }

    let context = Unmanaged<DedupScanContext>.fromOpaque(userData).takeUnretainedValue()

    // 解析 C 结构体 FFDuplicateGroup_C
    let cGroup = groupPtr.assumingMemoryBound(to: FFDuplicateGroup_C.self).pointee

    let groupId = cGroup.id.map { String(cString: $0) } ?? ""
    let hash = cGroup.hash.map { String(cString: $0) } ?? ""
    let groupSize = cGroup.size
    let fileCount = Int(cGroup.file_count)

    // 解析文件数组
    var files: [FFDuplicateFile] = []
    if let filesPtr = cGroup.files {
        for i in 0..<fileCount {
            let filePtr = filesPtr.advanced(by: i)
            let cFile = filePtr.pointee
            let fileId = cFile.id.map { String(cString: $0) } ?? ""
            let path = cFile.path.map { String(cString: $0) } ?? ""
            let name = cFile.name.map { String(cString: $0) } ?? ""
            files.append(FFDuplicateFile(
                id: fileId.isEmpty ? path : fileId,
                path: path,
                name: name,
                size: cFile.size,
                modified: cFile.modified
            ))
        }
    }

    let group = FFDuplicateGroup(
        id: groupId.isEmpty ? hash : groupId,
        hash: hash,
        size: groupSize,
        files: files
    )

    // 提取闭包后再 dispatch，避免延迟解引用 context。
    let handler = context.groupHandler
    DispatchQueue.main.async {
        handler(group)
    }
}

private func searchCallback(resultPtr: UnsafeRawPointer?, userData: UnsafeMutableRawPointer?) {
    guard let resultPtr = resultPtr,
          let userData = userData else { return }

    let context = Unmanaged<SearchContext>.fromOpaque(userData).takeUnretainedValue()

    // 解析 C 结构体 FFSearchResult_C
    let cResult = resultPtr.assumingMemoryBound(to: FFSearchResult_C.self).pointee

    let path = cResult.path.map { String(cString: $0) } ?? ""
    let name = cResult.name.map { String(cString: $0) } ?? ""

    let result = FFSearchResult(
        path: path,
        name: name,
        size: cResult.size,
        modified: cResult.modified,
        isDir: cResult.is_dir
    )

    // 提取闭包后再 dispatch，避免延迟解引用 context。
    let handler = context.resultHandler
    DispatchQueue.main.async {
        handler(result)
    }
}
