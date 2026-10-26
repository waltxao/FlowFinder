import Foundation

// MARK: - J3-10 批量整理：计划纯函数
//
// 只做纯计算：给定顶层可见文件条目与模式，产出「移动计划 + 重名冲突」。
// 不做任何 I/O；目录枚举（candidates）与执行（PaneViewModel.performOrganize）分离。

enum FFOrganizeDateFormat: String, CaseIterable {
    case ymd = "YYYY/MM/DD"
    case ym = "YYYY/MM"
    case year = "YYYY"
}

enum FFOrganizeMode: Equatable {
    case date(FFOrganizeDateFormat)
    case type
}

/// 中文 9 类类别文件夹（rawValue 即文件夹名）
enum FFOrganizeCategory: String, CaseIterable {
    case image = "图片"
    case document = "文档"
    case spreadsheet = "表格"
    case presentation = "演示"
    case audio = "音频"
    case video = "视频"
    case archive = "压缩包"
    case application = "应用"
    case other = "其他"

    static func category(forExtension rawExt: String) -> FFOrganizeCategory {
        switch rawExt.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff", "svg":
            return .image
        case "pdf", "doc", "docx", "md", "txt", "rtf", "pages", "epub":
            return .document
        case "xls", "xlsx", "csv", "numbers":
            return .spreadsheet
        case "key", "ppt", "pptx":
            return .presentation
        case "mp3", "wav", "aac", "flac", "m4a", "ogg":
            return .audio
        case "mp4", "mov", "avi", "mkv", "webm", "m4v":
            return .video
        case "zip", "tar", "gz", "7z", "rar", "bz2", "xz":
            return .archive
        case "dmg", "app", "pkg", "ipa":
            return .application
        default:
            return .other
        }
    }
}

struct FFOrganizeMove: Equatable {
    let sourcePath: String
    let fileName: String
    let targetDirectory: String

    var targetPath: String {
        (targetDirectory as NSString).appendingPathComponent(fileName)
    }
}

struct FFOrganizeConflict: Equatable {
    let fileName: String
    let targetDirectory: String

    var reason: String { "已存在同名，跳过" }
}

struct FFOrganizePlan: Equatable {
    let moves: [FFOrganizeMove]
    let conflicts: [FFOrganizeConflict]

    var isEmpty: Bool { moves.isEmpty && conflicts.isEmpty }
}

enum FFOrganizePlanner {

    /// 生成整理计划。entries 只应包含顶层可见文件（candidates 的输出）。
    /// 目标已存在同名文件时不移动、记入 conflicts（与 Rust 核心行为一致：永不覆盖）。
    static func plan(mode: FFOrganizeMode,
                     directory: String,
                     entries: [FileEntry],
                     calendar: Calendar = .current,
                     fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> FFOrganizePlan {
        var moves: [FFOrganizeMove] = []
        var conflicts: [FFOrganizeConflict] = []
        for entry in entries where !entry.isDirectory {
            let sub = subdirectory(for: mode, entry: entry, calendar: calendar)
            let targetDirectory = (directory as NSString).appendingPathComponent(sub)
            let targetPath = (targetDirectory as NSString).appendingPathComponent(entry.name)
            if fileExists(targetPath) {
                conflicts.append(FFOrganizeConflict(fileName: entry.name, targetDirectory: targetDirectory))
            } else {
                moves.append(FFOrganizeMove(sourcePath: entry.path,
                                            fileName: entry.name,
                                            targetDirectory: targetDirectory))
            }
        }
        return FFOrganizePlan(moves: moves, conflicts: conflicts)
    }

    /// 单个文件的归入子目录名：日期按格式取修改日期；类型按扩展名映射中文类别。
    static func subdirectory(for mode: FFOrganizeMode, entry: FileEntry, calendar: Calendar = .current) -> String {
        switch mode {
        case .date(let format):
            let comps = calendar.dateComponents([.year, .month, .day], from: entry.modificationDate)
            let year = String(format: "%04d", comps.year ?? 0)
            let month = String(format: "%02d", comps.month ?? 0)
            let day = String(format: "%02d", comps.day ?? 0)
            switch format {
            case .ymd: return "\(year)/\(month)/\(day)"
            case .ym: return "\(year)/\(month)"
            case .year: return year
            }
        case .type:
            return FFOrganizeCategory.category(forExtension: entry.fileExtension).rawValue
        }
    }

    /// 枚举目录顶层可见文件（排除子文件夹与隐藏文件，如 .DS_Store）。
    static func candidates(inDirectory directory: String,
                           fileManager: FileManager = .default) throws -> [FileEntry] {
        let names = try fileManager.contentsOfDirectory(atPath: directory)
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .compactMap { name -> FileEntry? in
                let path = (directory as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                    return nil
                }
                let attrs = try? fileManager.attributesOfItem(atPath: path)
                let modified = (attrs?[.modificationDate] as? Date) ?? Date()
                return FileEntry(path: path, name: name, isDirectory: false, modificationDate: modified)
            }
    }
}
