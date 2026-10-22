import AppKit

/// 批次 1 B1-04：GitHub Releases 检查更新（只提示，不下载）。
final class FFUpdateChecker {

    static let shared = FFUpdateChecker()

    static let releasesURL = URL(string: "https://github.com/waltxao/FlowFinder/releases")!
    private static let apiURL = URL(string: "https://api.github.com/repos/waltxao/FlowFinder/releases/latest")!
    private static let lastCheckKey = "last_update_check_at"
    private static let interval: TimeInterval = 24 * 60 * 60

    private var isChecking = false

    private init() {}

    /// 启动时调用：受开关与 24h 节流约束，失败静默。
    func checkOnLaunchIfNeeded() {
        guard FFAppSettings.checkUpdateOnStartup() else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last >= Self.interval else { return }
        fetch(userInitiated: false)
    }

    /// 关于页手动检查：不受开关与节流限制。
    func checkManually() {
        fetch(userInitiated: true)
    }

    // MARK: - Private

    private func fetch(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: Self.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FlowFinder", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isChecking = false
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if userInitiated { self.presentFailure() }
                    return
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970,
                                          forKey: Self.lastCheckKey)
                let tag = json["tag_name"] as? String ?? ""
                let name = json["name"] as? String ?? ""
                let body = json["body"] as? String ?? ""
                let html = (json["html_url"] as? String).flatMap(URL.init(string:))

                let verdict = FFUpdateDecision.evaluate(
                    localMarketing: FFBuildInfo.marketingVersion,
                    localBuild: FFBuildInfo.buildNumber,
                    releaseText: name + "\n" + body,
                    releaseTag: tag)

                switch verdict {
                case .updateAvailable(let remote):
                    self.presentUpdate(remote: remote, url: html ?? Self.releasesURL)
                case .upToDate:
                    if userInitiated { self.presentUpToDate() }
                case .unknown:
                    if userInitiated { self.presentFailure() }
                }
                _ = error
            }
        }.resume()
    }

    private func presentUpdate(remote: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(remote)"
        alert.informativeText = "当前版本 \(FFBuildInfo.displayVersion)。前往 GitHub Releases 下载。"
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "当前版本 \(FFBuildInfo.displayVersion)。"
        alert.addButton(withTitle: "好")
        present(alert) { _ in }
    }

    private func presentFailure() {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = "无法连接 GitHub，请稍后重试。"
        alert.addButton(withTitle: "好")
        present(alert) { _ in }
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
