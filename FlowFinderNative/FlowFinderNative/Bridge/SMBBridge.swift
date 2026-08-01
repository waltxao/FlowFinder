import Foundation
import NetFS
import Darwin

/// SMB 网络挂载桥接
///
/// 功能：
/// - SMB/NFS 网络卷挂载与卸载
/// - 已挂载卷列表刷新
/// - **断连自动检测**：定时健康检查（statfs + 目录列举）
/// - **自动重连**：检测到断连后，使用存储的连接信息指数退避重试
/// - **重试机制**：最多 3 次，延迟 2s/5s/10s
public final class SMBBridge {
    public static let shared = SMBBridge()

    /// 已挂载的 SMB 卷列表
    private(set) var mountedVolumes: [SMBVolume] = []
    private let lock = NSLock()

    // MARK: - 断连重连

    /// 存储连接信息，用于断连后自动重连
    private struct ConnectionInfo {
        let url: String
        let mountPoint: String?
        let volumeName: String
    }

    /// 挂载点路径 → 连接信息（仅存储通过本 API 挂载的卷）
    private var connectionInfos: [String: ConnectionInfo] = [:]

    /// 健康检查定时器
    private var healthCheckTimer: DispatchSourceTimer?

    /// 健康检查间隔（秒）
    private let healthCheckInterval: TimeInterval = 30

    /// 最大重连次数
    private let maxReconnectAttempts = 3

    /// 指数退避重连延迟（秒）
    private let reconnectDelays: [TimeInterval] = [2.0, 5.0, 10.0]

    /// 正在重连的卷路径集合（避免重复重连）
    private var reconnectingPaths = Set<String>()

    private init() {
        refreshMountedVolumes()
        startHealthCheck()
    }

    // MARK: - 挂载

    /// 挂载 SMB 共享
    /// - Parameters:
    ///   - url: SMB 地址，如 "smb://user:pass@server/share"
    ///   - mountPoint: 挂载点路径（nil 则自动选择）
    ///   - completion: 完成回调（主线程）
    public func mount(
        url: String,
        mountPoint: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let cfURL = URL(string: url) as CFURL?
        guard let cfURL = cfURL else {
            completion(.failure(SMBError.invalidURL))
            return
        }

        guard let openOptions = CFDictionaryCreateMutable(nil, 0, nil, nil),
              let mountOptions = CFDictionaryCreateMutable(nil, 0, nil, nil) else {
            completion(.failure(SMBError.mountFailed(code: -1)))
            return
        }

        let mountPath = mountPoint ?? "/Volumes"

        var mountpoints: Unmanaged<CFArray>?

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = NetFSMountURLSync(
                cfURL,
                URL(fileURLWithPath: mountPath) as CFURL,
                nil,
                nil,
                openOptions,
                mountOptions,
                &mountpoints
            )

            DispatchQueue.main.async {
                let mountpointsArray = mountpoints?.takeRetainedValue() as? [String]

                if result == 0 {
                    var mountedPath = mountPath
                    if let mps = mountpointsArray {
                        mountedPath = mps.first ?? mountPath
                    }

                    self?.refreshMountedVolumes()

                    // 存储连接信息用于自动重连
                    let volumeName = URL(string: url)?.lastPathComponent ?? "unknown"
                    self?.lock.lock()
                    self?.connectionInfos[mountedPath] = ConnectionInfo(
                        url: url,
                        mountPoint: mountPoint,
                        volumeName: volumeName
                    )
                    self?.lock.unlock()

                    completion(.success(mountedPath))
                } else {
                    completion(.failure(SMBError.mountFailed(code: result)))
                }
            }
        }
    }

    /// 卸载 SMB 卷
    public func unmount(mountPoint: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // 清除连接信息，防止健康检查触发重连
        lock.lock()
        connectionInfos.removeValue(forKey: mountPoint)
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.unmountVolume(at: mountPoint) ?? -1

            DispatchQueue.main.async {
                if result == 0 {
                    self?.refreshMountedVolumes()
                    completion(.success(()))
                } else {
                    completion(.failure(SMBError.unmountFailed(code: result)))
                }
            }
        }
    }

    /// 列出已挂载的 SMB 卷
    public func listMounted() -> [SMBVolume] {
        lock.lock()
        defer { lock.unlock() }
        return mountedVolumes
    }

    /// 刷新已挂载卷列表
    public func refreshMountedVolumes() {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeLocalizedFormatDescriptionKey], options: []) ?? []

        var smbVolumes: [SMBVolume] = []
        for volumeURL in volumes {
            let path = volumeURL.path
            if isNetworkVolume(path: path) {
                let name = (try? volumeURL.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? volumeURL.lastPathComponent
                smbVolumes.append(SMBVolume(
                    path: path,
                    name: name,
                    url: "smb://\(name)",
                    isMounted: true
                ))
            }
        }

        lock.lock()
        mountedVolumes = smbVolumes
        lock.unlock()
    }

    // MARK: - 健康检查

    /// 启动定时健康检查
    public func startHealthCheck() {
        guard healthCheckTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + healthCheckInterval, repeating: healthCheckInterval)
        timer.setEventHandler { [weak self] in
            self?.checkVolumesHealth()
        }
        timer.resume()
        healthCheckTimer = timer
    }

    /// 停止健康检查
    public func stopHealthCheck() {
        healthCheckTimer?.cancel()
        healthCheckTimer = nil
    }

    /// 检查所有已记录连接的卷的健康状态
    private func checkVolumesHealth() {
        lock.lock()
        let infos = connectionInfos
        let reconnecting = reconnectingPaths
        lock.unlock()

        for (path, _) in infos {
            if reconnecting.contains(path) { continue }
            if !isVolumeAccessible(path) {
                attemptReconnect(path: path)
            }
        }
    }

    /// 检查卷是否仍可访问
    private func isVolumeAccessible(_ path: String) -> Bool {
        // 1. statfs 检查文件系统是否仍然挂载
        var statbuf = statfs()
        let statResult = path.withCString { statfs($0, &statbuf) }
        if statResult != 0 {
            return false
        }
        // 2. 尝试列举目录验证可访问性（非空检查）
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return false
        }
        // 空目录也算可访问（新挂载的空共享）
        _ = contents
        return true
    }

    // MARK: - 自动重连

    /// 尝试重连断开的卷
    private func attemptReconnect(path: String) {
        lock.lock()
        if reconnectingPaths.contains(path) {
            lock.unlock()
            return
        }
        reconnectingPaths.insert(path)
        let info = connectionInfos[path]
        lock.unlock()

        guard let info = info else {
            lock.lock()
            reconnectingPaths.remove(path)
            lock.unlock()
            return
        }

        FFDebug.log("SMB 卷断连，开始自动重连: \(path) (\(info.volumeName))")

        // 通知 UI 断连
        DispatchQueue.main.async { [weak self] in
            self?.notifyReconnectStarted(path: path, volumeName: info.volumeName)
        }

        // 先卸载残留挂载点
        _ = unmountVolume(at: path)

        // 指数退避重试
        attemptMount(url: info.url, mountPoint: info.mountPoint, attempt: 0, path: path, volumeName: info.volumeName)
    }

    /// 递归重试挂载
    private func attemptMount(url: String, mountPoint: String?, attempt: Int, path: String, volumeName: String) {
        guard attempt < maxReconnectAttempts else {
            FFDebug.log("SMB 重连失败，已达最大重试次数 (\(maxReconnectAttempts)): \(path)")
            DispatchQueue.main.async { [weak self] in
                self?.notifyReconnectFailed(path: path, volumeName: volumeName)
            }
            lock.lock()
            reconnectingPaths.remove(path)
            lock.unlock()
            return
        }

        let delay = reconnectDelays[min(attempt, reconnectDelays.count - 1)]
        FFDebug.log("SMB 重连第 \(attempt + 1)/\(maxReconnectAttempts) 次，\(delay)s 后重试: \(path)")

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }

            self.mount(url: url, mountPoint: mountPoint) { result in
                switch result {
                case .success(let newPath):
                    FFDebug.log("SMB 重连成功: \(path) → \(newPath)")
                    self.refreshMountedVolumes()

                    // 更新连接信息（挂载点可能变化）
                    self.lock.lock()
                    self.connectionInfos.removeValue(forKey: path)
                    self.connectionInfos[newPath] = ConnectionInfo(
                        url: url,
                        mountPoint: mountPoint,
                        volumeName: volumeName
                    )
                    self.reconnectingPaths.remove(path)
                    self.lock.unlock()

                    self.notifyReconnectSucceeded(path: newPath, volumeName: volumeName)

                case .failure:
                    self.attemptMount(url: url, mountPoint: mountPoint, attempt: attempt + 1, path: path, volumeName: volumeName)
                }
            }
        }
    }

    // MARK: - 重连通知

    private func notifyReconnectStarted(path: String, volumeName: String) {
        NotificationCenter.default.post(
            name: .smbVolumeDisconnected,
            object: nil,
            userInfo: ["path": path, "volumeName": volumeName]
        )
    }

    private func notifyReconnectSucceeded(path: String, volumeName: String) {
        NotificationCenter.default.post(
            name: .smbVolumeReconnected,
            object: nil,
            userInfo: ["path": path, "volumeName": volumeName]
        )
    }

    private func notifyReconnectFailed(path: String, volumeName: String) {
        NotificationCenter.default.post(
            name: .smbVolumeReconnectFailed,
            object: nil,
            userInfo: ["path": path, "volumeName": volumeName]
        )
    }

    // MARK: - Private

    private func isNetworkVolume(path: String) -> Bool {
        var statbuf = statfs()
        let result = path.withCString { cPath in
            statfs(cPath, &statbuf)
        }
        if result == 0 {
            let fstype = withUnsafePointer(to: &statbuf.f_fstypename) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
            }
            return fstype == "smbfs" || fstype == "cifs" || fstype == "afpfs" || fstype == "nfs"
        }
        return false
    }

    private func unmountVolume(at path: String) -> Int32 {
        return path.withCString { cPath in
            Darwin.unmount(cPath, 0)
        }
    }
}

// MARK: - SMBVolume

public struct SMBVolume {
    public let path: String
    public let name: String
    public let url: String
    public let isMounted: Bool
}

// MARK: - SMBError

public enum SMBError: Error {
    case invalidURL
    case mountFailed(code: Int32)
    case unmountFailed(code: Int32)

    public var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "无效的 SMB 地址"
        case .mountFailed(let code):
            return "挂载失败（错误码：\(code)）"
        case .unmountFailed(let code):
            return "卸载失败（错误码：\(code)）"
        }
    }
}
