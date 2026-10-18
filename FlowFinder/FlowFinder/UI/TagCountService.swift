import Foundation

/// 目录内标签计数（DESIGN-SPEC §5.2）
///
/// 语义：**当前目录内**带某标签的项目数，不是全库统计。原因：
/// 项目没有标签倒排索引（Rust 侧只有 `ff_generate_tags` 规则生成，无标签查询），
/// 全库统计要遍历整个文件系统逐个 `getxattr`，SMB 下是分钟级，不可接受。
/// 访达的标签侧栏也不显示计数，此处是增值信息，宁缺（不显示）也不给估算值。
final class TagCountService {

    static let shared = TagCountService()

    /// 超过该文件数不做统计：本地 5k 文件约 20–100ms，SMB 秒级；
    /// 超过上限返回空字典，侧栏不显示计数（而不是显示错误的 0）
    static let maxFileCount = 5000

    /// 并发度：xattr 读取是阻塞系统调用，适度并发可显著缩短大目录耗时
    private let maxConcurrency = 8

    private let queue = DispatchQueue(label: "com.flowfinder.tagcount", qos: .utility)

    private init() {}

    /// 统计各标签出现次数，key 为标签名。
    ///
    /// - 标签名而非 id：原生标签（`_kMDItemUserTags`）每次读取生成随机 id，
    ///   不能作稳定 key（与 `TagBridge` 的合并去重口径一致）。
    /// - 回调固定回主线程。
    /// - 调用方需自行做代次校验（导航期间旧结果可能晚于新结果到达）。
    func count(paths: [String], completion: @escaping ([String: Int]) -> Void) {
        guard !paths.isEmpty, paths.count <= Self.maxFileCount else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        queue.async {
            var merged: [String: Int] = [:]
            let lock = NSLock()
            let chunk = max(1, Int(ceil(Double(paths.count) / Double(self.maxConcurrency))))

            DispatchQueue.concurrentPerform(iterations: self.maxConcurrency) { index in
                let start = min(index * chunk, paths.count)
                let end = min(start + chunk, paths.count)
                guard start < end else { return }

                var local: [String: Int] = [:]
                for path in paths[start..<end] {
                    for tag in TagBridge.shared.getTags(path: path) {
                        local[tag.name, default: 0] += 1
                    }
                }
                guard !local.isEmpty else { return }
                lock.lock()
                for (name, value) in local {
                    merged[name, default: 0] += value
                }
                lock.unlock()
            }

            DispatchQueue.main.async { completion(merged) }
        }
    }

    /// 纯函数：由每个文件的标签数组聚合出计数表。抽出来便于单测，
    /// 也便于未来接入索引时替换数据来源而不改聚合语义。
    static func counts(from tagsByPath: [[Tag]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for tags in tagsByPath {
            for tag in tags {
                result[tag.name, default: 0] += 1
            }
        }
        return result
    }
}
