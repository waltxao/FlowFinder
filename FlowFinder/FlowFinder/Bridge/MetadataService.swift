import AppKit
import Foundation
import ImageIO

struct FFFileMetadata: Equatable {
    let path: String
    let kind: String
    let size: UInt64
    let modified: Date?
    let created: Date?
    let pageCount: Int?
    let duration: TimeInterval?
    let finderComment: String?
    let folderItemCount: Int?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?

    init(path: String, kind: String, size: UInt64,
         modified: Date? = nil, created: Date? = nil,
         pageCount: Int? = nil, duration: TimeInterval? = nil,
         finderComment: String? = nil, folderItemCount: Int? = nil,
         imagePixelWidth: Int? = nil, imagePixelHeight: Int? = nil) {
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
        self.created = created
        self.pageCount = pageCount
        self.duration = duration
        self.finderComment = finderComment
        self.folderItemCount = folderItemCount
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
    }
}

protocol FFMetadataProviding {
    @discardableResult
    func load(path: String, completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID
    func cancel(_ token: UUID)
}

/// 默认实现：只读文件系统属性，全部在后台；不碰 PDF/AV/网络。
final class FFDefaultMetadataProvider: FFMetadataProviding {
    private let queue = DispatchQueue(label: "com.flowfinder.metadata", qos: .utility)
    private let lock = NSLock()
    private var cancelled = Set<UUID>()

    func load(path: String, completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID {
        let token = UUID()
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isCancelled = self.cancelled.contains(token)
            self.lock.unlock()
            guard !isCancelled else { return }

            let url = URL(fileURLWithPath: path)
            do {
                let values = try url.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                    .creationDateKey, .localizedNameKey
                ])
                let isDirectory = values.isDirectory ?? false
                let size = UInt64(values.fileSize ?? 0)
                let kind = isDirectory ? "文件夹" : (url.pathExtension.isEmpty ? "文件" : "\(url.pathExtension.uppercased()) 文件")
                var folderCount: Int?
                if isDirectory {
                    folderCount = (try? FileManager.default.contentsOfDirectory(atPath: path).count)
                }
                var pixelWidth: Int?
                var pixelHeight: Int?
                if !isDirectory,
                   let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
                    pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
                }
                let metadata = FFFileMetadata(
                    path: path,
                    kind: kind,
                    size: size,
                    modified: values.contentModificationDate,
                    created: values.creationDate,
                    folderItemCount: folderCount,
                    imagePixelWidth: pixelWidth,
                    imagePixelHeight: pixelHeight
                )
                DispatchQueue.main.async { completion(.success(metadata)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        return token
    }

    func cancel(_ token: UUID) {
        lock.lock()
        cancelled.insert(token)
        lock.unlock()
    }
}

/// 带 generation 的门面：旧请求的结果不会覆盖新请求。
final class FFMetadataService: FFMetadataProviding {
    private let provider: FFMetadataProviding
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var currentProviderToken: UUID?

    init(provider: FFMetadataProviding = FFDefaultMetadataProvider()) {
        self.provider = provider
    }

    @discardableResult
    func load(path: String, completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID {
        let signpost = FFPerf.begin("Details.load")
        lock.lock()
        generation += 1
        let gen = generation
        lock.unlock()

        let token = UUID()
        let inner = provider.load(path: path) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                FFPerf.end("Details.load", signpost)
                self.lock.lock()
                let valid = self.generation == gen
                self.lock.unlock()
                guard valid else { return }
                completion(result)
            }
        }
        lock.lock()
        currentProviderToken = inner
        lock.unlock()
        return token
    }

    func cancel(_ token: UUID) {
        lock.lock()
        generation += 1
        let inner = currentProviderToken
        currentProviderToken = nil
        lock.unlock()
        if let inner { provider.cancel(inner) }
    }
}
