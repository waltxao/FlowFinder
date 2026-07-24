import Foundation
import NetFS
import Darwin

/// SMB 网络挂载桥接
public final class SMBBridge {
    public static let shared = SMBBridge()

    /// 已挂载的 SMB 卷列表
    private(set) var mountedVolumes: [SMBVolume] = []
    private let lock = NSLock()

    private init() {
        refreshMountedVolumes()
    }

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

        // CFDictionaryCreateMutable 在 malloc 失败时可能返回 nil（极罕见），
        // 避免强制解包导致崩溃；失败时直接回调错误。
        guard let openOptions = CFDictionaryCreateMutable(nil, 0, nil, nil),
              let mountOptions = CFDictionaryCreateMutable(nil, 0, nil, nil) else {
            completion(.failure(SMBError.mountFailed(code: -1)))
            return
        }

        let mountPath = mountPoint ?? "/Volumes"

        // NetFSMountURLSync 签名：
        // int NetFSMountURLSync(CFURLRef url, CFURLRef mountPath,
        //   CFStringRef user, CFStringRef passwd,
        //   CFMutableDictionaryRef openOptions,
        //   CFMutableDictionaryRef mountOptions,
        //   CFArrayRef *mountpoints)
        //
        // mountpoints 是 +1 retain 的输出参数（caller 必须释放）。
        // 无论成功或失败都必须调用 takeRetainedValue() 平衡 retain count，
        // 否则在错误路径上会泄漏 CFArray。
        var mountpoints: Unmanaged<CFArray>?

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = NetFSMountURLSync(
                cfURL,
                URL(fileURLWithPath: mountPath) as CFURL,
                nil,  // 用户名（URL 中已包含）
                nil,  // 密码（URL 中已包含）
                openOptions,
                mountOptions,
                &mountpoints
            )

            DispatchQueue.main.async {
                // 始终消费 mountpoints 以平衡 NetFSMountURLSync 的 +1 retain，
                // 防止错误路径上泄漏 CFArray（防御性：即便 Rust 侧通常只在成功时设置）。
                let mountpointsArray = mountpoints?.takeRetainedValue() as? [String]

                if result == 0 {
                    // 获取挂载点路径
                    var mountedPath = mountPath
                    if let mps = mountpointsArray {
                        mountedPath = mps.first ?? mountPath
                    }

                    self?.refreshMountedVolumes()
                    completion(.success(mountedPath))
                } else {
                    completion(.failure(SMBError.mountFailed(code: result)))
                }
            }
        }
    }

    /// 卸载 SMB 卷
    public func unmount(mountPoint: String, completion: @escaping (Result<Void, Error>) -> Void) {
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
            // 检查是否是网络卷
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

    // MARK: - Private

    private func isNetworkVolume(path: String) -> Bool {
        // 检查 statfs 的 f_fstypename
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
        // 使用 unmount(2) 系统调用 (Darwin.unmount to disambiguate from instance method)
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
