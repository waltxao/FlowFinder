import Foundation
import AppKit
import QuickLook

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
            var progressContext = DedupProgressContext(progressHandler: progressHandler)
            var groupContext = DedupGroupContext(groupHandler: groupHandler)

            let result = path.withCString { cPath in
                ff_scan_duplicates(
                    cPath,
                    dedupProgressCallback,
                    dedupGroupCallback,
                    &groupContext
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

    /// Cancel an ongoing duplicate scan
    public func cancelScan() {
        ff_cancel_scan()
    }

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
            var context = SearchContext(resultHandler: resultHandler)

            let result = path.withCString { cPath in
                query.withCString { cQuery in
                    ff_search(cPath, cQuery, searchCallback, &context)
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

    /// Search for files with advanced filters
    /// - Parameters:
    ///   - path: Root directory path
    ///   - query: Search query string
    ///   - filters: Search filter criteria
    ///   - resultHandler: Called for each matching result
    ///   - completion: Called when search completes or errors
    public func searchWithFilters(
        path: String,
        query: String,
        filters: FFSearchFilters,
        resultHandler: @escaping (FFSearchResult) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        ffiQueue.async {
            var context = SearchContext(resultHandler: resultHandler)

            // Build C-compatible filters
            var cFilters = FFSearchFilters_C(
                file_types: nil,
                min_size: filters.minSize ?? 0,
                max_size: filters.maxSize ?? 0,
                modified_after: filters.modifiedAfter ?? 0,
                modified_before: filters.modifiedBefore ?? 0,
                has_file_types: filters.fileTypes != nil,
                has_min_size: filters.minSize != nil,
                has_max_size: filters.maxSize != nil,
                has_modified_after: filters.modifiedAfter != nil,
                has_modified_before: filters.modifiedBefore != nil
            )

            if let fileTypes = filters.fileTypes {
                let cFileTypes = fileTypes.withCString { ptr in
                    return strdup(ptr)
                }
                cFilters.file_types = cFileTypes
            }

            let result = path.withCString { cPath in
                query.withCString { cQuery in
                    ff_search_with_filters(cPath, cQuery, &cFilters, searchCallback, &context)
                }
            }

            if cFilters.file_types != nil {
                free(cFilters.file_types)
            }

            if result == 0 {
                completion(nil)
            } else {
                let errorMessage = self.getLastError()
                completion(CoreBridgeError.ffiError(errorMessage))
            }
        }
    }

    private func getLastError() -> String {
        guard let cString = ff_last_error() else {
            return "Unknown error"
        }
        let message = String(cString: cString)
        ff_free_string(UnsafeMutablePointer(mutating: cString))
        return message
    }
}

// MARK: - C-compatible Search Filters

/// Internal C-compatible search filters structure
private struct FFSearchFilters_C {
    var file_types: UnsafeMutablePointer<CChar>?
    var min_size: UInt64
    var max_size: UInt64
    var modified_after: Int64
    var modified_before: Int64
    var has_file_types: Bool
    var has_min_size: Bool
    var has_max_size: Bool
    var has_modified_after: Bool
    var has_modified_before: Bool
}

// MARK: - Callback Contexts

private struct DedupProgressContext {
    var progressHandler: (Int, Int) -> Void
}

private struct DedupGroupContext {
    var groupHandler: (FFDuplicateGroup) -> Void
}

private struct SearchContext {
    var resultHandler: (FFSearchResult) -> Void
}

// MARK: - C Callbacks

private func dedupProgressCallback(scanned: Int, total: Int, userData: UnsafeMutableRawPointer?) {
    guard let userData = userData else { return }
    let context = userData.withMemoryRebound(to: DedupProgressContext.self, capacity: 1) { $0 }
    DispatchQueue.main.async {
        context.pointee.progressHandler(scanned, total)
    }
}

private func dedupGroupCallback(groupPtr: UnsafeRawPointer?, userData: UnsafeMutableRawPointer?) {
    guard let groupPtr = groupPtr,
          let userData = userData else { return }

    let context = userData.withMemoryRebound(to: DedupGroupContext.self, capacity: 1) { $0 }

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

    DispatchQueue.main.async {
        context.pointee.groupHandler(group)
    }
}

private func searchCallback(resultPtr: UnsafeRawPointer?, userData: UnsafeMutableRawPointer?) {
    guard let resultPtr = resultPtr,
          let userData = userData else { return }

    let context = userData.withMemoryRebound(to: SearchContext.self, capacity: 1) { $0 }

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

    DispatchQueue.main.async {
        context.pointee.resultHandler(result)
    }
}
