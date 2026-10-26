import Cocoa

// MARK: - 启动期文件访问权限集中请求（2026-10-19 需求 #3）

/// macOS 的 TCC 只在**首次访问某个受保护目录**时弹窗。文件管理器逐目录浏览时，
/// 用户体感就是「每打开一个文件夹都被问一次」；更糟的是弹窗未应答期间目录列举的
/// 系统调用会一直阻塞，Swift 侧 10s 超时后误报「目录响应超时」。
///
/// 这里在启动阶段**并发**触碰全部受保护目录：系统会把同一进程短时间内的多次访问
/// 合并成一个「文件与文件夹」授权对话框（macOS 13+），一次点完即可；
/// 已拒绝时系统不再弹窗、直接返回 EPERM，此时给一次性引导跳转系统设置。
///
/// 说明：本工程为本机 ad-hoc 签名，每次重新构建 CDHash 都会变，系统会把新构建
/// 当成新 App 重新询问。要彻底免询问，需要在「完全磁盘访问权限」里授权，
/// 或使用固定开发者证书签名（见 docs/HANDOVER.md）。
final class FFPermissionGate {

    struct Location {
        let path: String
        let title: String
    }

    struct Report {
        var denied: [Location] = []
        var timedOut: Bool = false
        var needsAttention: Bool { !denied.isEmpty || timedOut }

        var deniedTitles: String {
            denied.map(\.title).joined(separator: "、")
        }
    }

    static let shared = FFPermissionGate()
    private init() {}

    /// 同一次进程生命周期内只集中请求一次
    private var didRequest = false
    /// 引导弹窗每次启动最多出现一次，避免反复打扰
    private var didShowGuidance = false

    /// 需要预授权的标准位置（与 Info.plist 的用途说明一一对应）
    var locations: [Location] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            Location(path: home + "/Desktop", title: "桌面"),
            Location(path: home + "/Documents", title: "文稿"),
            Location(path: home + "/Downloads", title: "下载"),
            Location(path: "/Volumes", title: "外置磁盘"),
        ]
    }

    // MARK: 请求

    /// 并发触碰受保护目录，等系统授权对话框走完再回调（主线程）。
    /// - Parameter timeout: 兜底时长；用户长时间不应答时也不要把启动卡死。
    func requestAccess(timeout: TimeInterval = 30,
                       completion: @escaping (Report) -> Void) {
        guard !didRequest else {
            DispatchQueue.main.async { completion(Report()) }
            return
        }
        didRequest = true

        let targets = locations.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !targets.isEmpty else {
            DispatchQueue.main.async { completion(Report()) }
            return
        }

        let lock = NSLock()
        var denied: [Location] = []
        let group = DispatchGroup()

        for location in targets {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    // 只要真的去列目录，系统就会在需要时抛出授权对话框；
                    // 已授权则立即返回，未授权则抛 EPERM。
                    _ = try FileManager.default.contentsOfDirectory(atPath: location.path)
                } catch {
                    lock.lock()
                    denied.append(location)
                    lock.unlock()
                }
            }
        }

        // group.wait 不能占主线程：TCC 对话框是系统模态，等待期间主线程仍要能响应点击
        DispatchQueue.global(qos: .userInitiated).async {
            let waitResult = group.wait(timeout: .now() + timeout)
            var report = Report()
            lock.lock()
            let deniedSnapshot = denied
            lock.unlock()

            // 关键：并发请求时系统是**逐个**弹框的，先返回的 EPERM 往往是
            // 「对话框还没轮到」而不是真拒绝。这里对被判失败的目录做两次复查，
            // 只有复查仍失败才算拒绝——否则会在系统弹框上再叠一个引导弹窗。
            var stillDenied: [Location] = []
            for attempt in 0..<2 {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.6) }
                stillDenied = deniedSnapshot.filter { !Self.isReadable($0.path) }
                if stillDenied.isEmpty { break }
            }
            report.denied = stillDenied
            // 复查没有结论（仍在阻塞）说明「授权状态未确认」，不能当成已授权：
            // 首启时 TCC 未应答会让目录枚举一直卡住，此时界面必须显示「待确认」。
            report.timedOut = (waitResult == .timedOut) && stillDenied.isEmpty
            DispatchQueue.main.async { completion(report) }
        }
    }

    /// 受保护目录当前是否可读（已授权 / 不需要授权 → true）
    private static func isReadable(_ path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    /// 手动复查（菜单「检查文件访问权限…」）：重置一次性标记后重新请求
    func recheck(completion: @escaping (Report) -> Void) {
        didRequest = false
        requestAccess(completion: completion)
    }

    // MARK: 引导

    /// 有目录被拒（或用户一直没应答）时给一次性引导
    func presentGuidanceIfNeeded(_ report: Report, in window: NSWindow?) {
        guard report.needsAttention else { return }
        guard !didShowGuidance else { return }
        didShowGuidance = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要文件访问权限"

        var details: [String] = []
        if !report.denied.isEmpty {
            details.append("以下位置还没有授权：\(report.deniedTitles)。")
        }
        if report.timedOut {
            details.append("授权对话框似乎没有应答。")
        }
        details.append("""
        FlowFinder 需要访问桌面、文稿、下载与外置磁盘才能浏览和整理文件。

        在「系统设置 → 隐私与安全性 → 文件与文件夹」里勾选 FlowFinder 即可；\
        勾选「完全磁盘访问权限」可以一次性覆盖所有位置，之后不再逐个询问。
        """)
        alert.informativeText = details.joined(separator: "\n\n")

        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            Self.openPrivacySettings(pane: "Privacy_FilesAndFolders")
        }

        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    /// 打开「隐私与安全性」指定分区
    static func openPrivacySettings(pane: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 供菜单/状态栏复用

extension FFPermissionGate {
    /// 启动加载前统一请求：完成回调一定在主线程
    ///
    /// `FF_SKIP_PERMISSION_GATE=1` 时直接放行：自动化截图 / 自检场景下
    /// 系统授权框会挡住界面，而合成点击事件投不进 TCC 对话框（系统安全限制），
    /// 没办法自动应答。该开关只影响启动期的预请求，不改变各处真实读取的权限行为。
    /// 启动权限门最多阻塞 3 秒：TCC 无应答时也要让首屏先加载，
    /// 否则用户会长时间看到「此文件夹为空」而不是真实目录。
    static let launchGateTimeout: TimeInterval = 3

    func prepareBeforeInitialLoad(window: NSWindow?,
                                  timeout: TimeInterval = FFPermissionGate.launchGateTimeout,
                                  completion: @escaping () -> Void) {
        if ProcessInfo.processInfo.environment["FF_SKIP_PERMISSION_GATE"] == "1" {
            FFDebug.log("[PERM] 跳过启动权限门（FF_SKIP_PERMISSION_GATE=1）")
            completion()
            return
        }
        requestAccess(timeout: timeout) { [weak self] report in
            completion()
            self?.presentGuidanceIfNeeded(report, in: window)
        }
    }
}
