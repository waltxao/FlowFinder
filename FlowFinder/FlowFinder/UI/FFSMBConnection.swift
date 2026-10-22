import Foundation

// MARK: - SMB 连接持久化（批次 1 B1-08）

struct FFSavedSMBConnection: Codable, Equatable {
    let url: String
    let mountPoint: String?
    let volumeName: String
}

enum FFSMBConnectionStore {

    static let storageKey = "saved_smb_connections"

    static func load(defaults: UserDefaults = .standard) -> [FFSavedSMBConnection] {
        guard let data = defaults.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([FFSavedSMBConnection].self, from: data) else {
            return []
        }
        return list
    }

    static func save(_ connection: FFSavedSMBConnection, defaults: UserDefaults = .standard) {
        var list = load(defaults: defaults).filter { $0.url != connection.url }
        list.append(connection)
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func remove(url: String, defaults: UserDefaults = .standard) {
        let list = load(defaults: defaults).filter { $0.url != url }
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - SMB URL 组装（B1-07 默认域）

enum FFSMBURL {

    /// `smb://domain;user:password@host:port/share`；无域时退回 `smb://user@host`。
    static func build(server: String,
                      port: String = "",
                      share: String = "",
                      user: String = "",
                      password: String = "",
                      domain: String = "") -> URL? {
        guard !server.isEmpty else { return nil }
        var urlString = "smb://"

        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDomain.isEmpty {
            urlString += trimmedDomain.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? trimmedDomain
            urlString += ";"
            urlString += trimmedUser.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? trimmedUser
        } else if !trimmedUser.isEmpty {
            urlString += trimmedUser.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? trimmedUser
        }

        if !trimmedUser.isEmpty && !password.isEmpty {
            urlString += ":" + (password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password)
        }
        if !trimmedUser.isEmpty || !trimmedDomain.isEmpty {
            urlString += "@"
        }

        urlString += server
        if !port.isEmpty { urlString += ":" + port }
        if !share.isEmpty {
            urlString += "/" + (share.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? share)
        }
        return URL(string: urlString)
    }
}

// MARK: - 状态栏文案

enum FFSMBStatusText {
    static func reconnecting(volume: String, attempt: Int, max: Int) -> String {
        "正在重连「\(volume)」（\(attempt)/\(max)）"
    }
    static func reconnected(volume: String) -> String { "「\(volume)」已重新连接" }
    static func failed(volume: String) -> String { "「\(volume)」重连失败" }
}
