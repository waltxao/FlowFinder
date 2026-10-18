import Foundation

// MARK: - Content Index Stats

/// Parsed snapshot of the content-index stats JSON returned by
/// `ff_content_index_stats` (§7.3 of the content-index contract).
public struct ContentIndexStats {
    public let status: ContentIndexStatus
    public let paused: Bool
    public let documentCount: Int
    public let totalCandidates: Int
    public let processed: Int
    public let checkpointPath: String?
    public let lastBuildAt: Int64?
    public let rootPath: String?
    public let error: String?

    /// Decode the raw JSON produced by `ff_content_index_stats`. Returns nil
    /// when the JSON is malformed or the `status` field is not a known
    /// `ContentIndexStatus` raw value.
    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusRaw = (obj["status"] as? NSNumber)?.int32Value,
              let status = ContentIndexStatus(rawValue: statusRaw) else {
            return nil
        }
        self.status = status
        self.paused = (obj["paused"] as? NSNumber)?.boolValue ?? false
        self.documentCount = (obj["document_count"] as? NSNumber)?.intValue ?? 0
        self.totalCandidates = (obj["total_candidates"] as? NSNumber)?.intValue ?? 0
        self.processed = (obj["processed"] as? NSNumber)?.intValue ?? 0
        self.checkpointPath = obj["checkpoint_path"] as? String
        self.lastBuildAt = (obj["last_build_at"] as? NSNumber)?.int64Value
        self.rootPath = obj["root_path"] as? String
        self.error = obj["error"] as? String
    }
}

// MARK: - Content Index Bridge

/// Thread-safe bridge for the independent FTS5 content index (Wave2 T7).
///
/// Wraps the nine `ff_content_index_*` FFI entry points behind the same
/// `ffiQueue` / `Unmanaged` callback-context pattern used by `SearchBridge`
/// and `CoreBridge`. C-string arguments are borrowed (`withCString`, valid
/// only for the duration of the call); the single owned out-string
/// (`ff_content_index_stats`) is freed with `ff_free_string`.
public final class ContentIndexBridge {

    public static let shared = ContentIndexBridge()

    private let ffiQueue = DispatchQueue(label: "com.flowfinder.contentindex", qos: .userInitiated)

    /// Handle of the currently-active build. Rust writes it before the build
    /// starts; cancel/pause/resume target it. Read/written only on `ffiQueue`.
    private var currentBuildHandle: UInt64?

    private init() {}

    // MARK: - Lifecycle

    /// Initialize the independent content index at `dbPath`.
    ///
    /// Mirrors `CoreBridge.initCache`. Failure must not block app startup —
    /// callers log and continue.
    func initialize(dbPath: String) throws {
        guard !dbPath.isEmpty else {
            throw CoreBridgeError.invalidPath("dbPath is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }
            ffiResult = dbPath.withCString { cPath in
                ff_content_index_init(cPath)
            }
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            throw CoreBridgeError.ffiError(getLastError())
        }
    }

    /// Current lifecycle status.
    func status() -> ContentIndexStatus {
        ffiQueue.sync {
            ContentIndexStatus(rawValue: ff_content_index_status()) ?? .empty
        }
    }

    /// Latest stats snapshot (progress, document count, paused flag). Nil when
    /// the underlying JSON is unavailable or malformed.
    func stats() -> ContentIndexStats? {
        ffiQueue.sync {
            guard let cString = ff_content_index_stats() else { return nil }
            defer { ff_free_string(cString) }
            return ContentIndexStats(json: String(cString: cString))
        }
    }

    // MARK: - Build control

    /// Start a build on a Rust background thread. Returns the cancel handle
    /// (nil on failure). Status advances to `.indexing` and then to
    /// `.ready` / `.cancelled` / `.error` asynchronously.
    @discardableResult
    func start(rootPath: String, mode: ContentIndexMode) -> UInt64? {
        guard !rootPath.isEmpty else { return nil }

        var handle: UInt64?
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let handlePtr = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
            handlePtr.initialize(to: 0)
            defer { handlePtr.deallocate() }

            let result = rootPath.withCString { cRoot in
                ff_content_index_start(cRoot, mode.rawValue, handlePtr)
            }

            if result == 0, handlePtr.pointee != 0 {
                handle = handlePtr.pointee
                self.currentBuildHandle = handle
            }
        }

        semaphore.wait()
        return handle
    }

    /// Cancel the active build (cooperative, batch-boundary).
    func cancel() {
        ffiQueue.async {
            guard let handle = self.currentBuildHandle else { return }
            _ = ff_content_index_cancel(handle)
        }
    }

    /// Pause the active build (cooperative, batch-boundary).
    func pause() {
        ffiQueue.async {
            guard let handle = self.currentBuildHandle else { return }
            _ = ff_content_index_pause(handle)
        }
    }

    /// Resume a paused build.
    func resume() {
        ffiQueue.async {
            guard let handle = self.currentBuildHandle else { return }
            _ = ff_content_index_resume(handle)
        }
    }

    /// Mark a path dirty for the next incremental build (O(1), no I/O).
    /// Forwarded from the single global FSEvents watcher.
    func markDirty(path: String) {
        guard !path.isEmpty else { return }
        ffiQueue.async {
            _ = path.withCString { cPath in
                ff_content_index_mark_dirty(cPath)
            }
        }
    }

    // MARK: - Query

    /// Run a one-shot content query, collecting matching absolute paths into a
    /// `Set<String>`. A non-ready index returns `FF_ERR_NOT_FOUND`, surfaced
    /// as `.failure` so the UI presents the status instead of reading files.
    func query(
        _ query: String,
        maxResults: Int = 500,
        completion: @escaping (Result<Set<String>, Error>) -> Void
    ) {
        ffiQueue.async {
            let context = ContentQueryContext()
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            defer { Unmanaged<ContentQueryContext>.fromOpaque(contextPtr).release() }

            let result = query.withCString { cQuery in
                ff_content_index_query(
                    cQuery,
                    maxResults,
                    contentQueryCallback,
                    contextPtr
                )
            }

            if result == 0 {
                completion(.success(context.matches))
            } else {
                completion(.failure(CoreBridgeError.ffiError(self.getLastError())))
            }
        }
    }

    // MARK: - Error

    private func getLastError() -> String {
        guard let cString = ff_last_error() else {
            return "Unknown error"
        }
        let message = String(cString: cString)
        ff_free_string(UnsafeMutablePointer(mutating: cString))
        return message
    }
}

// MARK: - Callback Context

/// Reference-type context passed through the FFI callback. The `matches` set
/// is mutated on the FFI thread during `ff_content_index_query` (synchronous)
/// and read back on the same thread after the call returns.
private final class ContentQueryContext {
    var matches: Set<String> = []
}

// MARK: - C Callback

/// C callback for `ff_content_index_query`. Reads the borrowed `path` field
/// during the callback only (the Rust side drops the backing `CString` as soon
/// as the callback returns).
private func contentQueryCallback(resultPtr: UnsafeRawPointer?, userData: UnsafeMutableRawPointer?) {
    guard let resultPtr = resultPtr, let userData = userData else { return }
    let context = Unmanaged<ContentQueryContext>.fromOpaque(userData).takeUnretainedValue()
    let cResult = resultPtr.assumingMemoryBound(to: FFSearchResult_C.self).pointee
    if let cPath = cResult.path {
        context.matches.insert(String(cString: cPath))
    }
}
