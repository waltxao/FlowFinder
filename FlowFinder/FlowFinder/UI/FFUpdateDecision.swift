import Foundation

/// 批次 1 B1-04：更新判定（纯函数，不发网络请求）。
enum FFUpdateVerdict: Equatable {
    case upToDate
    case updateAvailable(remoteVersion: String)
    case unknown
}

enum FFUpdateDecision {

    private static let stampRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d+\.\d+\.\d+)-(\d{8,})(?!\d)"#)
    private static let semverRegex = try! NSRegularExpression(
        pattern: #"(?<![\d.])(\d+)\.(\d+)\.(\d+)(?![\d.])"#)

    /// 优先比较完整版本戳（`0.8.0-26102301`），缺失时回退营销版本（`0.8.1`）。
    static func evaluate(localMarketing: String,
                         localBuild: String,
                         releaseText: String,
                         releaseTag: String) -> FFUpdateVerdict {
        let haystack = releaseText + " " + releaseTag

        if let best = stamps(in: haystack).max(by: { $0.build < $1.build }) {
            let local = Int(localBuild) ?? 0
            return best.build > local
                ? .updateAvailable(remoteVersion: best.display)
                : .upToDate
        }

        if let remote = highestSemver(in: haystack),
           isNewer(remote, than: semver(localMarketing)) {
            return .updateAvailable(remoteVersion: "\(remote.major).\(remote.minor).\(remote.patch)")
        }
        if highestSemver(in: haystack) != nil {
            return .upToDate
        }
        return .unknown
    }

    // MARK: - 解析

    private struct Stamp { let display: String; let build: Int }

    private static func stamps(in text: String) -> [Stamp] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return stampRegex.matches(in: text, range: range).compactMap { match in
            guard let full = Range(match.range, in: text),
                  let buildRange = Range(match.range(at: 2), in: text),
                  let build = Int(text[buildRange]) else { return nil }
            return Stamp(display: String(text[full]), build: build)
        }
    }

    private struct Semver { let major: Int; let minor: Int; let patch: Int }

    private static func semver(_ text: String) -> Semver {
        for match in semverRegex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            guard let a = Range(match.range(at: 1), in: text),
                  let b = Range(match.range(at: 2), in: text),
                  let c = Range(match.range(at: 3), in: text),
                  let major = Int(text[a]), let minor = Int(text[b]), let patch = Int(text[c]) else { continue }
            return Semver(major: major, minor: minor, patch: patch)
        }
        return Semver(major: 0, minor: 0, patch: 0)
    }

    private static func highestSemver(in text: String) -> Semver? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let all = semverRegex.matches(in: text, range: range).compactMap { match -> Semver? in
            guard let a = Range(match.range(at: 1), in: text),
                  let b = Range(match.range(at: 2), in: text),
                  let c = Range(match.range(at: 3), in: text),
                  let major = Int(text[a]), let minor = Int(text[b]), let patch = Int(text[c]) else { return nil }
            return Semver(major: major, minor: minor, patch: patch)
        }
        return all.max { lhs, rhs in
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    private static func isNewer(_ remote: Semver, than local: Semver) -> Bool {
        (remote.major, remote.minor, remote.patch) > (local.major, local.minor, local.patch)
    }
}
