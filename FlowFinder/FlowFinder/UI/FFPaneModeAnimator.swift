import AppKit

/// 单/双面板切换的过渡动画（2026-10-20 #2）。
///
/// 规格：0.36s 弹性（带轻微过冲），宽度、透明度、缩放一起动，窗口宽度同步。
///
/// 为什么不用 `NSView.animator()` 直接动布局：面板显隐是
/// `NSSplitView` 的 arranged subview 增删，`NSSplitView` 不参与隐式动画，
/// 动不了。这里的做法是：
///   1. 结构变更瞬时完成（保证布局正确，不留中间态）
///   2. 窗口宽度用 `NSAnimationContext` 同曲线插值（这是唯一能真动画的部分）
///   3. contentView 叠一层 opacity 关键帧（1 → 0.72 → 1），做出「推挤 + 回弹」的观感
///
/// 代价：面板本身没有位移动画。这是 `NSSplitView` 的硬限制——
/// 想做出「面板滑出」必须放弃 NSSplitView 自己排布局，属于更大的改动。
enum FFPaneModeAnimator {

    /// 总时长（秒）
    static let duration: TimeInterval = 0.36

    /// 弹性曲线：前段快、末端轻微过冲
    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.32, 1.28, 0.48, 1.0)
    }

    /// 执行一次切换
    /// - Parameters:
    ///   - toSingle: true = 双 → 单；false = 单 → 双
    ///   - window: 用于取 contentView 加淡入淡出
    ///   - changes: 结构变更闭包（同步执行）
    static func animate(toSingle: Bool, window: NSWindow?, changes: () -> Void) {
        // 结构变更先落地：动画只负责「观感」，不承担正确性
        changes()

        guard let layer = window?.contentView?.layer else { return }

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        if toSingle {
            fade.values = [1.0, 0.72, 1.0]
            fade.keyTimes = [0, 0.42, 1]
        } else {
            fade.values = [0.78, 1.0]
            fade.keyTimes = [0, 1]
        }
        fade.duration = duration
        fade.timingFunction = timingFunction
        layer.add(fade, forKey: "ffPaneModeFade")
    }
}

// MARK: - 图二布局诊断（Phase 0）

/// 只读布局快照：捕捉「操作区空白 / 详情栏悬空」出现的瞬间。
///
/// 不调用 `layoutSubtreeIfNeeded`、不改帧、不重绘——诊断本身不能改变被诊断的状态。
enum FFLayoutDiagnostics {
    static func logTransition(_ tag: String, _ controller: MainWindowController) {
        #if DEBUG
        let anomalies = controller.layoutAnomalies(phase: tag)
        let verdict = anomalies.isEmpty
            ? "OK"
            : "ANOMALY \(anomalies.count): \(anomalies.joined(separator: " | "))"
        FFDebug.log("[LAYOUT] \(tag) \(controller.layoutSummary()) → \(verdict)")
        #endif
    }

    #if DEBUG
    /// 每个窗口只保留最后一次「下一拍」快照，避免连续切换时日志互相错位。
    private static var pendingNextRunLoopTags: [ObjectIdentifier: String] = [:]
    #endif

    /// 过渡完成后的下一拍再取一次快照，捕捉异步 setPosition / 约束收敛。
    static func logNextRunLoop(_ tag: String, _ controller: MainWindowController) {
        #if DEBUG
        let key = ObjectIdentifier(controller)
        pendingNextRunLoopTags[key] = tag
        DispatchQueue.main.async { [weak controller] in
            guard let controller,
                  let pending = pendingNextRunLoopTags.removeValue(forKey: key) else { return }
            logTransition(pending, controller)
        }
        #endif
    }
}

extension MainWindowController {
    /// 一行帧摘要（窗口 / 分栏 / 两块面板 / 详情栏 / 列表）。
    func layoutSummary() -> String {
        func size(_ rect: NSRect?) -> String {
            guard let rect else { return "nil" }
            return "\(Int(rect.width))x\(Int(rect.height))@\(Int(rect.minX)),\(Int(rect.minY))"
        }
        let panes = [("L", leftPaneWrapper), ("R", rightPaneWrapper)].map { name, wrapper in
            guard let wrapper else { return "\(name):nil" }
            let state = wrapper.superview == nil ? "out" : (wrapper.isHidden ? "hidden" : "in")
            return "\(name):\(size(wrapper.frame)):\(state)"
        }.joined(separator: " ")
        let details = [("L", detailsBar(for: .left)), ("R", detailsBar(for: .right))].map { name, bar in
            "\(name):\(size(bar?.frame))"
        }.joined(separator: " ")
        let lists = [("L", leftFileListView), ("R", rightFileListView)].map { name, list in
            "\(name):\(size(list?.frame))"
        }.joined(separator: " ")
        return "window=\(size(window?.frame)) visible=\(window?.isVisible ?? false) "
            + "sidebar=\(isSidebarVisible ? "on" : "off") single=\(isSinglePaneMode) active=\(activePane) "
            + "split=\(size(paneSplitView?.bounds)) panes=[\(panes)] details=[\(details)] lists=[\(lists)]"
    }

    /// 返回不符合布局不变量的描述；空数组 = 健康。
    func layoutAnomalies(phase: String) -> [String] {
        // 窗口尚未完成首轮布局时帧全是 0，不能据此判定异常。
        guard let split = paneSplitView, split.bounds.width > 1, split.bounds.height > 1 else {
            return []
        }
        var issues: [String] = []
        let expectedCount = isSinglePaneMode ? 1 : 2
        let arranged = split.arrangedSubviews
        if arranged.count != expectedCount {
            issues.append("排列面板数 \(arranged.count) ≠ \(expectedCount)")
        }
        for wrapper in arranged {
            let name = wrapper === leftPaneWrapper ? "左" : "右"
            if wrapper.isHidden { issues.append("\(name)面板标记隐藏") }
            if wrapper.frame.width < 100 {
                issues.append("\(name)面板宽度 \(Int(wrapper.frame.width))")
            }
            if abs(wrapper.frame.height - split.bounds.height) > 1 {
                issues.append("\(name)面板高度 \(Int(wrapper.frame.height)) ≠ 分栏 \(Int(split.bounds.height))")
            }
        }
        if isSinglePaneMode, arranged.count == 1,
           abs(arranged[0].frame.width - split.bounds.width) > 1 {
            issues.append("单栏面板未填满分栏 \(Int(arranged[0].frame.width)) ≠ \(Int(split.bounds.width))")
        }
        if !isSinglePaneMode, arranged.count == 2 {
            let total = arranged.reduce(0) { $0 + $1.frame.width }
            if total < split.bounds.width - 2 {
                issues.append("双栏面板总宽 \(Int(total)) < 分栏 \(Int(split.bounds.width))")
            }
        }

        let panes: [(String, NSView?, PaneSide, NSView?, NSView?, NSView?)] = [
            ("左", leftPaneWrapper, .left, leftPaneToolbar, leftFileListView, leftFileGridView),
            ("右", rightPaneWrapper, .right, rightPaneToolbar, rightFileListView, rightFileGridView),
        ]
        for (name, wrapper, side, toolbar, list, grid) in panes {
            guard let wrapper, wrapper.superview != nil, !wrapper.isHidden else { continue }
            guard let container = wrapper.subviews.first(where: { view in
                view.subviews.contains { $0 is FFPaneContentClipView }
            }) else {
                issues.append("\(name)面板缺少内容容器")
                continue
            }
            let containerSize = container.frame.size
            if containerSize.width < 100 || containerSize.height < 100 {
                issues.append("\(name)卡片尺寸 \(Int(containerSize.width))x\(Int(containerSize.height))")
            }
            if let clip = container.subviews.compactMap({ $0 as? FFPaneContentClipView }).first {
                if clip.frame.width < 100 || clip.frame.height < 100 {
                    issues.append("\(name)内容裁切层 \(Int(clip.frame.width))x\(Int(clip.frame.height))")
                }
            } else {
                issues.append("\(name)缺少内容裁切层")
            }
            if let toolbar, toolbar.frame.height < 10 {
                issues.append("\(name)工具栏高度 \(Int(toolbar.frame.height))")
            }
            let fileAreaHeight = max(list?.frame.height ?? 0, grid?.frame.height ?? 0)
            if fileAreaHeight < 60 {
                issues.append("\(name)文件区高度 \(Int(fileAreaHeight))")
            }
            if let details = detailsBar(for: side) {
                if details.frame.height < 40 {
                    issues.append("\(name)详情栏高度 \(Int(details.frame.height))")
                }
                if details.frame.minY > containerSize.height / 2 {
                    issues.append("\(name)详情栏悬空到顶部 y=\(Int(details.frame.minY)) 卡片高 \(Int(containerSize.height))")
                } else if abs(details.frame.minY - 8) > 2 {
                    issues.append("\(name)详情栏未贴底 y=\(Int(details.frame.minY))")
                }
            }
        }
        _ = phase
        return issues
    }
}
