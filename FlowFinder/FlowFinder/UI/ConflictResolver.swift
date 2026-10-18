import AppKit

// MARK: - ConflictResolver

/// 复制/移动冲突解决器（任务 10）
/// 目标目录存在同名文件时弹窗询问：替换 / 保留两者 / 跳过。
/// 批量时支持"应用于所有冲突"。
enum ConflictResolution {
    case replace      // 替换：覆盖同名目标
    case keepBoth     // 保留两者：源自动改名"名称 副本.扩展名"
    case skip         // 跳过：不处理该文件
}

enum ConflictResolver {

    /// 一次批量操作的冲突处理结果。
    ///
    /// - `normalSrcs`: 无冲突 / 选择"替换"的源路径，保留原名，交给批量 parallelCopy/parallelMove。
    /// - `keepBoth`: 选择"保留两者"的 (源路径, 新目标文件名) 对。由于批量接口的目标名
    ///   固定取源文件的 lastPathComponent，无法表达改名，因此这些文件需要逐项
    ///   以 `destDir + "/" + dstName` 作为目标调用 copyFile/moveFile。
    struct Plan {
        let normalSrcs: [String]
        let keepBoth: [(src: String, dstName: String)]

        var isEmpty: Bool { normalSrcs.isEmpty && keepBoth.isEmpty }
        var count: Int { normalSrcs.count + keepBoth.count }
    }

    /// 检查冲突并弹窗询问，返回处理计划。
    /// - Parameters:
    ///   - srcPaths: 待复制/移动的源绝对路径
    ///   - destDir: 目标目录绝对路径
    ///   - window: 弹窗依附窗口（当前 runModal 为 app-modal，暂不使用，保留参数便于后续改为 sheet）
    /// - Returns: 冲突处理计划（替换/无冲突进 normalSrcs；保留两者进 keepBoth；跳过直接剔除）
    static func resolveConflicts(srcPaths: [String], destDir: String, window: NSWindow?) -> Plan {
        var normal: [String] = []
        var keepBoth: [(src: String, dstName: String)] = []
        // 本批次内已占用的目标文件名（含其它源的原名与已生成的"副本"名），
        // 避免两个同名源在"保留两者"时生成相同的副本名。
        var takenNames = Set(srcPaths.map { ($0 as NSString).lastPathComponent })
        var applyToAll = false
        var globalChoice: ConflictResolution?

        for src in srcPaths {
            let name = (src as NSString).lastPathComponent
            let dst = (destDir as NSString).appendingPathComponent(name)

            // 无冲突：直接放行
            if !FileManager.default.fileExists(atPath: dst) {
                normal.append(src)
                continue
            }

            // 冲突：决定策略（勾选"应用于所有冲突"后沿用首个选择）
            let choice: ConflictResolution
            if applyToAll, let g = globalChoice {
                choice = g
            } else {
                choice = presentConflictDialog(name: name, window: window, applyToAll: &applyToAll)
                if applyToAll {
                    globalChoice = choice
                }
            }

            switch choice {
            case .replace:
                normal.append(src)
            case .skip:
                break
            case .keepBoth:
                if let newName = uniqueDestinationName(srcPath: src, destDir: destDir, taken: &takenNames) {
                    keepBoth.append((src: src, dstName: newName))
                    takenNames.insert(newName)
                }
            }
        }
        return Plan(normalSrcs: normal, keepBoth: keepBoth)
    }

    /// 生成不冲突的目标文件名（"名称 副本.扩展名"，重名加序号）。
    /// 同时避开本批次内其它文件已占用的名字（`taken`）。
    private static func uniqueDestinationName(srcPath: String, destDir: String, taken: inout Set<String>) -> String? {
        let name = (srcPath as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension

        var index = 1
        while true {
            let suffix = index == 1 ? "副本" : "副本 \(index)"
            let candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            let dst = (destDir as NSString).appendingPathComponent(candidate)
            if !taken.contains(candidate) && !FileManager.default.fileExists(atPath: dst) {
                return candidate
            }
            index += 1
        }
    }

    /// 冲突弹窗（NSAlert 三按钮 + "应用于所有冲突"复选框）。
    ///
    /// 模态方式选择：**同步 `alert.runModal()`**（app-modal）。
    /// - `beginSheetModal` 是异步回调式，会让 `resolveConflicts` 被迫变成异步
    ///   （破坏同步返回接口，调用方需改为回调式，侵入面大）；
    /// - `runModal` 以同步方式返回用户选择，调用方代码保持简单。
    private static func presentConflictDialog(name: String, window: NSWindow?, applyToAll: inout Bool) -> ConflictResolution {
        let alert = NSAlert()
        alert.messageText = "“\(name)”已存在"
        alert.informativeText = "目标位置已存在同名文件。您想要如何处理？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: "跳过")

        // "应用于所有冲突"复选框
        let checkbox = NSButton(checkboxWithTitle: "应用于所有冲突", target: nil, action: nil)
        checkbox.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        alert.accessoryView = checkbox

        _ = window // 当前为 app-modal runModal；保留参数以便后续切换为 sheet

        let response = alert.runModal()
        applyToAll = checkbox.state == .on

        switch response {
        case .alertFirstButtonReturn:  return .replace
        case .alertSecondButtonReturn: return .keepBoth
        default:                       return .skip
        }
    }
}
