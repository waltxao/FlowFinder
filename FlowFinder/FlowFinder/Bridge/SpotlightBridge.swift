import Foundation

/// Spotlight 全局搜索桥接
public final class SpotlightBridge {
    public static let shared = SpotlightBridge()

    private var query: NSMetadataQuery?
    private var resultHandler: (([FFSearchResult]) -> Void)?

    private init() {}

    /// 启动 Spotlight 搜索
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - scopes: 搜索范围（如 [NSMetadataQueryUserHomeScope]）
    ///   - resultHandler: 结果回调（主线程）
    public func search(
        query: String,
        scopes: [String] = [NSMetadataQueryUserHomeScope],
        resultHandler: @escaping ([FFSearchResult]) -> Void
    ) {
        cancel()

        self.resultHandler = resultHandler
        let metadataQuery = NSMetadataQuery()
        metadataQuery.searchScopes = scopes
        metadataQuery.predicate = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", query)
        metadataQuery.notificationBatchingInterval = 0.5

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery
        )

        self.query = metadataQuery
        metadataQuery.start()
    }

    /// 取消搜索
    public func cancel() {
        if let query = query {
            query.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
            self.query = nil
        }
        resultHandler = nil
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }

        var results: [FFSearchResult] = []
        query.disableUpdates()

        for i in 0..<query.resultCount {
            let item = query.result(at: i) as? NSMetadataItem
            guard let item = item else { continue }

            let path = item.value(forAttribute: "kMDItemPath") as? String ?? ""
            let name = item.value(forAttribute: "kMDItemDisplayName") as? String ?? ""
            let size = (item.value(forAttribute: "kMDItemFSSize") as? NSNumber)?.uint64Value ?? 0
            let modified = (item.value(forAttribute: "kMDItemFSContentChangeDate") as? Date)?.timeIntervalSince1970 ?? 0
            let isDir = (item.value(forAttribute: "kMDItemContentType") as? String) == "public.folder"

            results.append(FFSearchResult(
                path: path,
                name: name,
                size: size,
                modified: Int64(modified),
                isDir: isDir
            ))
        }

        query.enableUpdates()
        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        self.query = nil

        DispatchQueue.main.async { [weak self] in
            self?.resultHandler?(results)
            self?.resultHandler = nil
        }
    }
}
