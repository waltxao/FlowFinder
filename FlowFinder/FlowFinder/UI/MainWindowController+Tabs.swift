import Cocoa

// MARK: - 标签页集成（2026-10-18 #7）

extension MainWindowController: PaneTabStripDelegate {

    // MARK: 初始化

    /// 在两侧面板创建完成后建立标签集合（每个面板至少一个标签）
    func installTabStrips() {
        guard leftTabsStore == nil else { return }
        leftTabsStore = PaneTabsStore(initial: PaneTabSession(state: leftPaneViewModel.captureSession()))
        rightTabsStore = PaneTabsStore(initial: PaneTabSession(state: rightPaneViewModel.captureSession()))
        refreshTabStrip(side: .left)
        refreshTabStrip(side: .right)
    }

    // MARK: 访问器

    /// 刷新一侧的标签条：内容 + 可见性。
    /// 2026-10-18 #3：只有一个标签时不显示标签条（高度收 0，工具栏顶到卡片顶部），
    /// 第二个标签出现时再展开。新建标签入口保留在「文件 → 新建标签页 ⌘T」
    /// 与侧栏右键「在新标签页中打开」。
    func refreshTabStrip(side: PaneSide) {
        guard let store = tabsStore(for: side) else { return }
        let strip = tabStrip(for: side)
        strip?.refresh(sessions: store.tabs, activeIndex: store.activeIndex)
        // 2026-10-20 #1：标签条常显（原来只有 ≥2 个标签才显示）。
        // 它现在是面板唯一的拖动把手，也是红绿灯的对齐基准，必须始终在场。
        let heightConstraint = (side == .left) ? leftTabStripHeight : rightTabStripHeight
        heightConstraint?.constant = MainWindowController.tabStripHeight
        // 2026-10-20 #3：标签条是窗口级浮层，位置由 updateTabStripFrames 计算
        updateTabStripFrames()
    }

    func viewModel(for side: PaneSide) -> PaneViewModel {
        side == .left ? leftPaneViewModel : rightPaneViewModel
    }

    func tabsStore(for side: PaneSide) -> PaneTabsStore? {
        side == .left ? leftTabsStore : rightTabsStore
    }

    func tabStrip(for side: PaneSide) -> PaneTabStripView? {
        side == .left ? leftTabStrip : rightTabStrip
    }

    /// 面板状态变化（导航/排序/筛选/选中）后同步到激活标签并刷新标题
    func syncTabStrip(side: PaneSide, state: PaneState) {
        guard let store = tabsStore(for: side) else { return }
        store.updateActiveState(state)
        refreshTabStrip(side: side)
    }

    // MARK: 标签操作

    /// 新建标签：默认沿用当前路径（与访达「新建标签页」后仍是同一目录的直觉一致）
    @discardableResult
    func newTab(in side: PaneSide, path: String? = nil) -> Bool {
        guard let store = tabsStore(for: side) else { return false }
        let vm = viewModel(for: side)
        store.updateActiveState(vm.captureSession())

        var state = vm.captureSession()
        if let path = path, !path.isEmpty {
            state.path = path
            state.history = [path]
            state.historyIndex = 0
            state.files = []
            state.selectedFiles = []
            state.searchQuery = ""
            state.tagFilter = nil
        }
        store.add(PaneTabSession(state: state))
        loadActiveTab(side: side)
        return true
    }

    func selectTab(side: PaneSide, index: Int) {
        guard let store = tabsStore(for: side), store.select(index) else { return }
        loadActiveTab(side: side)
    }

    func closeTab(side: PaneSide, index: Int) {
        guard let store = tabsStore(for: side), store.close(at: index) else { return }
        loadActiveTab(side: side)
    }

    func moveTab(side: PaneSide, from: Int, to: Int) {
        guard let store = tabsStore(for: side), store.move(from: from, to: to) else { return }
        refreshTabStrip(side: side)
    }

    /// 接收一个标签（拖到本面板的标签条上）。
    ///
    /// 2026-10-20 #1：跨面板的标签拖放已退役（拖标签现在＝搬整块面板），
    /// 这里只保留「插入到指定位置」这一条路径。
    func receiveTab(side: PaneSide, session: PaneTabSession, at index: Int) {
        guard let store = tabsStore(for: side) else { return }
        store.insert(session, at: index)
        loadActiveTab(side: side)
    }

    // MARK: - 面板拖放（2026-10-20 #1 重做）
    //
    // 语义：**拖标签 = 搬整块面板**（SPEC-2026-10-20 §1.8）。
    //   单栏 + 拖到操作区右半区 → 面板挪到右槽，原槽空掉，窗口收窄（仍是单栏）
    //   双栏 + 拖到对面面板     → 两块合并成一个（标签并集），窗口变单栏
    //   窗口外                  → 整块面板拆成独立新窗口
    //   其它                    → 回原位

    /// 搬整块面板的落点（窗口内）
    func handlePanelMove(toWindowPoint point: NSPoint, from source: PaneSide) {
        if isSinglePaneMode {
            // 单栏：操作区被分成左右两个槽位，落点在哪一半就挪到哪一槽
            let target: PaneSide = isInOperationHalf(windowX: point.x, side: .left) ? .left : .right
            guard target != source else {
                FFDebug.log("[PANEMOVE] 落在本侧，回原位")
                return
            }
            movePaneToSlot(from: source, to: target)
        } else {
            // 双栏：落在对面面板 → 合并
            let target = nearestPane(forWindowX: point.x)
            guard target != source else {
                FFDebug.log("[PANEMOVE] 落在本侧，回原位")
                return
            }
            mergePanes(from: source, into: target)
        }
    }

    /// 搬整块面板落到窗口外 → 整块面板拆成独立新窗口
    func handlePanelMoveOutside(screenPoint: NSPoint, from side: PaneSide) {
        guard let store = tabsStore(for: side), store.count >= 1 else { return }
        detachPaneToNewWindow(from: side, atScreenPoint: screenPoint)
    }

    /// 把面板整组挪到另一个槽位（原槽的内容与目标槽的内容互换）
    private func movePaneToSlot(from source: PaneSide, to target: PaneSide) {
        guard let src = tabsStore(for: source), let dst = tabsStore(for: target) else { return }
        let srcTabs = src.tabs
        let dstTabs = dst.tabs
        // 目标槽原本是空的（占位），把它挪回源槽
        src.replaceAll(dstTabs.isEmpty ? [PaneTabSession(state: placeholderState())] : dstTabs)
        dst.replaceAll(srcTabs)
        activePane = target
        isSinglePaneMode = true
        UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        loadActiveTab(side: target)
        FFDebug.log("[PANEMOVE] 面板挪到 \(target) 槽，窗口单栏")
    }

    /// 两块面板合并成一个：被拖面板的标签追加到目标面板末尾，窗口变单栏
    private func mergePanes(from source: PaneSide, into target: PaneSide) {
        guard let src = tabsStore(for: source), let dst = tabsStore(for: target) else { return }
        let merged = dst.tabs + src.tabs
        dst.replaceAll(merged, activeAt: max(merged.count - 1, 0))
        src.resetToPlaceholder(PaneTabSession(state: placeholderState()))
        activePane = target
        isSinglePaneMode = true
        UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        loadActiveTab(side: target)
        FFDebug.log("[PANEMOVE] 两块面板合并成一个，共 \(merged.count) 个标签")
    }

    /// 整块面板拆成独立新窗口
    private func detachPaneToNewWindow(from side: PaneSide, atScreenPoint point: NSPoint) {
        guard let src = tabsStore(for: side) else { return }
        let tabs = src.tabs
        let activeID = src.active.id
        src.resetToPlaceholder(PaneTabSession(state: placeholderState()))
        if isSinglePaneMode {
            // 源槽空了，窗口保持单栏（显示另一槽）
        } else {
            isSinglePaneMode = true
            UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
            applyPaneMode()
        }

        let controller = MainWindowController()
        controller.leftTabsStore?.replaceAll(tabs)
        if let idx = tabs.firstIndex(where: { $0.id == activeID }) {
            controller.leftTabsStore?.select(idx)
        }
        controller.refreshTabStrip(side: .left)
        if let newWindow = controller.window {
            newWindow.setFrameOrigin(NSPoint(x: point.x - 60, y: point.y - 60))
        }
        (NSApp.delegate as? AppDelegate)?.registerWindowController(controller)
        controller.showWindow(nil)
        controller.loadActiveTab(side: .left)
        FFDebug.log("[PANEMOVE] 整块面板拆成独立窗口（\(tabs.count) 个标签）")
    }

    /// 落点是否在操作区的某一侧（左半 / 右半）
    private func isInOperationHalf(windowX x: CGFloat, side: PaneSide) -> Bool {
        guard let cv = window?.contentView else { return false }
        let localX = cv.convert(NSPoint(x: x, y: 0), from: nil).x
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        let midX = (sidebarRight + cv.bounds.maxX) / 2
        return side == .left ? localX < midX : localX >= midX
    }


    //
    // 语义：**拖操作面板 = 拖它当前那个标签**（SPEC-2026-10-20 §1.4）。
    //   - 双面板：落在对面面板 → 只搬当前标签；源面板被搬空才消失（合并成单面板）
    //   - 单面板 + 多标签：窗口右半区 → 拆出右面板
    //   - 窗口外：独立成新窗口
    //   - 其余：回原位

    /// 面板拖动落在窗口内时的分流
    private func nearestPane(forWindowX x: CGFloat) -> PaneSide {
        guard let cv = window?.contentView else { return activePane }
        guard leftPaneWrapper.superview != nil, rightPaneWrapper.superview != nil else {
            return activePane
        }
        let localX = cv.convert(NSPoint(x: x, y: 0), from: nil).x
        let leftMax = cv.convert(leftPaneWrapper.frame, from: leftPaneWrapper.superview).maxX
        let rightMin = cv.convert(rightPaneWrapper.frame, from: rightPaneWrapper.superview).minX
        return localX < (leftMax + rightMin) / 2 ? .left : .right
    }

    private func placeholderState() -> PaneState {
        var state = PaneState()
        state.path = NSHomeDirectory()
        state.history = [state.path]
        state.historyIndex = 0
        return state
    }

    /// 把标签快照载入面板（切换标签的唯一入口）
    private func loadActiveTab(side: PaneSide) {
        guard let store = tabsStore(for: side) else { return }
        let vm = viewModel(for: side)
        vm.restoreSession(store.active.state)
        refreshTabStrip(side: side)
    }

    // MARK: 菜单

    @objc func menuNewTab(_ sender: Any?) {
        newTab(in: activePane)
    }

    @objc func menuCloseTab(_ sender: Any?) {
        guard let store = tabsStore(for: activePane), store.canClose else {
            // 最后一个标签：退回关窗语义
            window?.performClose(sender)
            return
        }
        closeTab(side: activePane, index: store.activeIndex)
    }

    // MARK: PaneTabStripDelegate

    func tabStripDidRequestNewTab(_ strip: PaneTabStripView) {
        newTab(in: strip.side)
    }

    func tabStrip(_ strip: PaneTabStripView, didSelect index: Int) {
        selectTab(side: strip.side, index: index)
    }

    func tabStrip(_ strip: PaneTabStripView, didClose index: Int) {
        closeTab(side: strip.side, index: index)
    }

    func tabStrip(_ strip: PaneTabStripView, didMoveTabFrom from: Int, to: Int) {
        moveTab(side: strip.side, from: from, to: to)
    }

    func tabStrip(_ strip: PaneTabStripView, didReceive session: PaneTabSession, at index: Int) {
        receiveTab(side: strip.side, session: session, at: index)
    }
}

// MARK: - 拖放落点自检（仅 Debug，环境变量 FF_SELFTEST=1 时启动）

#if DEBUG
extension MainWindowController {

    /// 面板拖动模型自检（2026-10-20 #1 重做后）
    ///
    /// 合成鼠标事件驱动不了「拖出条 → 搬面板」的浮层与落点，
    /// 但落点分流本身是可以直接调用的（`handlePanelMove` / `handlePanelMoveOutside`），
    /// 所以这里直接调真实代码路径来验证状态机。
    func runDragSelfTest() {
        guard let leftStore = tabsStore(for: .left),
              let rightStore = tabsStore(for: .right) else {
            FFDebug.log("[SELFTEST] 缺少标签组，跳过")
            return
        }

        // 准备：双栏，左 2 个标签、右 1 个标签
        if isSinglePaneMode {
            isSinglePaneMode = false
            UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
            applyPaneMode()
        }
        while leftStore.count > 2 { leftStore.close(at: leftStore.count - 1) }
        while leftStore.count < 2 { _ = newTab(in: .left) }
        while rightStore.count > 1 { rightStore.close(at: rightStore.count - 1) }
        window?.contentView?.layoutSubtreeIfNeeded()

        // ① 双栏：把左面板拖到右面板 → 两块合并成一个（标签并集），窗口变单栏
        let leftBefore = leftStore.count
        let rightBefore = rightStore.count
        handlePanelMove(toWindowPoint: windowPointInPane(.right), from: .left)
        let mergedOK = isSinglePaneMode
            && (rightStore.count == rightBefore + leftBefore)
            && (leftStore.count == 1)   // 源槽只剩占位
        FFDebug.log("[SELFTEST] ① 拖到对面合并 \(mergedOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) 左=\(leftStore.count) 右=\(rightStore.count) 期望右=\(rightBefore + leftBefore)")

        // ② 双栏：拖到自己这半 → 回原位（两块内容都不变）
        isSinglePaneMode = false
        UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        let l2 = leftStore.count, r2 = rightStore.count
        handlePanelMove(toWindowPoint: windowPointInPane(.left), from: .left)
        let sameSideOK = !isSinglePaneMode && leftStore.count == l2 && rightStore.count == r2
        FFDebug.log("[SELFTEST] ② 落在本侧回原位 \(sameSideOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) 左=\(leftStore.count) 右=\(rightStore.count)")

        // ③ 单栏：把面板拖到操作区右半 → 面板挪到右槽，窗口仍是单栏
        isSinglePaneMode = true
        UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        let srcSide = activePane
        let srcCountBefore = tabsStore(for: srcSide)?.count ?? 0
        let otherSide: PaneSide = srcSide == .left ? .right : .left
        handlePanelMove(toWindowPoint: windowPointInOperationHalf(side: otherSide), from: srcSide)
        let movedOK = isSinglePaneMode
            && activePane == otherSide
            && (tabsStore(for: otherSide)?.count ?? 0) == srcCountBefore
        FFDebug.log("[SELFTEST] ③ 单栏拖到右半挪槽 \(movedOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) 活动面板=\(activePane) 目标组=\(tabsStore(for: otherSide)?.count ?? -1) 期望=\(srcCountBefore)")

        // ④ 拖出窗口 → 整块面板拆成独立新窗口，源槽清空
        let before4 = tabsStore(for: activePane)?.count ?? 0
        handlePanelMoveOutside(screenPoint: NSPoint(x: -2000, y: -2000), from: activePane)
        let detachedOK = (tabsStore(for: activePane)?.count ?? 0) == 1   // 只剩占位
        FFDebug.log("[SELFTEST] ④ 拖出窗口独立成窗 \(detachedOK ? "PASS" : "FAIL") 源组=\(tabsStore(for: activePane)?.count ?? -1) 期望=1（占位）原=\(before4)")
    }

    /// 交互决策表穷举自检（2026-10-20 #3）
    ///
    /// 决策表是纯函数（不依赖 AppKit），因此可以在启动时把
    /// 「区域 × 状态」的所有组合跑一遍，逐条断言结果符合预期。
    /// 漏掉一个组合 = 少一行表格 = 以后会变成一个 bug。
    func runInteractionPolicySelfTest() {
        var pass = 0
        var fail = 0

        /// 断言：某区域在某状态下应得到某意图
        func expect(_ region: FFRegion, _ state: FFInteractionState, _ want: FFIntent,
                    _ label: String) {
            let got = FFInteractionPolicy.intent(region: region, state: state)
            if got == want {
                pass += 1
            } else {
                fail += 1
                FFDebug.log("[POLICY] FAIL \(label)：\(region) + \(state) 期望 \(want) 实得 \(got)")
            }
        }

        for state in FFInteractionState.allCombinations {
            let tag = "侧栏\(state.sidebarVisible ? "可见" : "隐藏")/单栏\(state.singlePane ? "是" : "否")/缓冲内\(state.pointerInsideTabBuffer ? "是" : "否")"

            // ① 窗口区 → 拖窗口（状态无关）
            expect(.window, state, .dragWindow, "窗口区→拖窗口 [\(tag)]")

            // ② 标题区 → 拖窗口（性质等同系统标题栏）
            expect(.title, state, .dragWindow, "标题区→拖窗口 [\(tag)]")

            // ③ 面板区 → 按压反馈，不产生拖动
            expect(.panel, state, .pressFeedback, "面板区→按压反馈 [\(tag)]")

            // ④ 标签本体：缓冲内=重排 / 出缓冲=搬面板
            expect(.tab, state,
                   state.pointerInsideTabBuffer ? .reorderTab : .dragPane,
                   "标签本体 [\(tag)]")
        }

        // ⑤ 每条规则都必须至少命中一次（防止规则写了但永远走不到）
        for rule in FFInteractionPolicy.rules {
            var hit = false
            for region in FFRegion.allCases {
                for state in FFInteractionState.allCombinations {
                    if FFInteractionPolicy.matchedRuleName(region: region, state: state) == rule.name {
                        hit = true
                        break
                    }
                }
                if hit { break }
            }
            if hit {
                pass += 1
            } else {
                fail += 1
                FFDebug.log("[POLICY] FAIL 规则「\(rule.name)」在任何组合下都命中不到")
            }
        }

        // ⑥ 几何常量：避让量与标题区高度
        if FFInteractionPolicy.titleContentInset(sidebarVisible: true) == 8,
           FFInteractionPolicy.titleContentInset(sidebarVisible: false) == 106,
           FFInteractionPolicy.titleBandHeight == 36 {
            pass += 1
        } else {
            fail += 1
            FFDebug.log("[POLICY] FAIL 几何常量：避让量应为 8/106，标题区 36")
        }

        FFDebug.log("[POLICY] 决策表穷举自检 通过\(pass) 失败\(fail)（区域\(FFRegion.allCases.count) × 状态\(FFInteractionState.allCombinations.count) + 规则可达性）")
    }

    /// 区域判定真机自检（2026-10-20 #3）
    ///
    /// 合成鼠标事件驱动不了「拖出条 → 搬面板」的浮层与落点，
    /// 而且事件链会经过系统标题栏带这一层——外部脚本测出来的结论不可靠。
    /// 这里改为**在应用内**直接对真实视图做 hitTest，验证
    /// 「这个窗口坐标点 → 哪个区域 → 什么意图」这条链路。
    func runRegionResolveSelfTest() {
        guard let window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()

        var pass = 0
        var fail = 0

        /// 断言：窗口坐标点应解析成某区域
        func expect(_ point: NSPoint, _ want: FFRegion, _ label: String) {
            let hit = contentView.hitTest(point)
            let got = FFAreaResolver.region(of: hit)
            if got == want {
                pass += 1
            } else {
                fail += 1
                FFDebug.log("[REGION] FAIL \(label)：点 \(point) 期望 \(want) 实得 \(String(describing: got)) 命中=\(String(describing: hit.map { String(describing: type(of: $0)) }))")
            }
        }

        // 找各区域的实际代表点（用真实视图 frame 反推，不靠硬编码坐标）
        let strip = leftTabStrip
        let toolbar = leftPaneToolbar
        let list = leftPaneContainer?.subviews.compactMap { $0 as? FileListView }.first

        if let strip, let frame = strip.superview?.convert(strip.frame, to: contentView) {
            // 标签条空白处（远离标签胶囊，取右端）
            let blank = NSPoint(x: frame.maxX - 12, y: frame.midY)
            expect(blank, .title, "标签条空白")
            // 标签胶囊本体
            if let item = strip.subviews.compactMap({ $0 as? PaneTabItemView }).first,
               let itemFrame = item.superview?.convert(item.frame, to: contentView) {
                expect(NSPoint(x: itemFrame.midX, y: itemFrame.midY), .tab, "标签胶囊")
            }
        }

        if let toolbar, let frame = toolbar.superview?.convert(toolbar.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.midY), .panel, "工具栏")
        }

        if let list, let frame = list.superview?.convert(list.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.midY), .panel, "文件列表")
        }

        // 侧栏空白（底部）
        if let sidebar = sidebarView, let frame = sidebar.superview?.convert(sidebar.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.minY + 20), .window, "侧栏底部空白")
        }

        // 卡片四周 8pt 留白（wrapper 左缘）
        if let wrapper = leftPaneWrapper, let frame = wrapper.superview?.convert(wrapper.frame, to: contentView) {
            expect(NSPoint(x: frame.minX + 3, y: frame.midY), .window, "卡片左缘留白")
        }

        FFDebug.log("[REGION] 区域解析自检 通过\(pass) 失败\(fail)")
    }

    /// 拖动行为自检（2026-10-20 #3）
    ///
    /// 覆盖「区域 → 意图 → 实际动作」这条链路的最后一段：
    /// 决策表给出意图后，控制器分别执行「拖窗口」「按压反馈」「不拖动」。
    ///
    /// 说明：这里**不构造并派发 NSEvent**——`addLocalMonitorForEvents` 只拦截
    /// 经由 NSApplication 派发的事件，程序内造的合成事件到不了 monitor
    /// （`window.sendEvent` 与 `postEvent` 都绕开），测出来的结论不可靠。
    /// 事件派发本身由 AppKit 负责，不是我们的逻辑，因此不测；
    /// 测的是「拿到某个意图之后，控制器做的是不是该做的事」。
    func runDragBehaviorSelfTest() {
        guard let window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()

        var pass = 0
        var fail = 0

        /// 断言：某点应解析成某意图
        func expect(_ point: NSPoint, _ want: FFIntent, _ label: String) {
            let hit = contentView.hitTest(point)
            let state = FFInteractionState(sidebarVisible: isSidebarVisible,
                                           singlePane: isSinglePaneMode,
                                           pointerInsideTabBuffer: true)
            let got = FFAreaResolver.intent(for: hit, state: state)
            if got == want {
                pass += 1
            } else {
                fail += 1
                FFDebug.log("[BEHAVIOR] FAIL \(label)：点 \(point) 期望 \(want) 实得 \(got)")
            }
        }

        // ① 工具栏 → 按压反馈（不产生拖动）
        if let toolbar = leftPaneToolbar,
           let frame = toolbar.superview?.convert(toolbar.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.midY), .pressFeedback, "工具栏→按压反馈")
        }

        // ② 侧栏空白 → 拖窗口
        if let sidebar = sidebarView,
           let frame = sidebar.superview?.convert(sidebar.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.minY + 20), .dragWindow, "侧栏空白→拖窗口")
        }

        // ③ 标签条空白 → 拖窗口
        if let strip = leftTabStrip,
           let frame = strip.superview?.convert(strip.frame, to: contentView) {
            expect(NSPoint(x: frame.maxX - 20, y: frame.midY), .dragWindow, "标签条空白→拖窗口")
        }

        // ④ 标签胶囊在缓冲内 → 重排；出缓冲 → 搬面板
        if let strip = leftTabStrip,
           let item = strip.subviews.compactMap({ $0 as? PaneTabItemView }).first,
           let itemFrame = item.superview?.convert(item.frame, to: contentView) {
            let p = NSPoint(x: itemFrame.midX, y: itemFrame.midY)
            let hit = contentView.hitTest(p)
            var inBuffer = FFInteractionState(sidebarVisible: isSidebarVisible,
                                              singlePane: isSinglePaneMode,
                                              pointerInsideTabBuffer: true)
            expect(p, .reorderTab, "标签胶囊缓冲内→重排")
            inBuffer.pointerInsideTabBuffer = false
            let outGot = FFAreaResolver.intent(for: hit, state: inBuffer)
            if outGot == .dragPane {
                pass += 1
            } else {
                fail += 1
                FFDebug.log("[BEHAVIOR] FAIL 标签胶囊出缓冲→搬面板：实得 \(outGot)")
            }
        }

        // ⑤ 文件列表 → 面板区（框选，不拖动）
        if let list = leftPaneContainer?.subviews.compactMap({ $0 as? FileListView }).first,
           let frame = list.superview?.convert(list.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.midY), .pressFeedback, "文件列表→不拖动")
        }

        FFDebug.log("[BEHAVIOR] 拖动行为自检 通过\(pass) 失败\(fail)")
    }

    /// 标签焊接自检（2026-10-20 #4）
    ///
    /// 验证「标签底边 = 面板顶边」「上方间隙 = 8」「非活动比活动矮 6」
    /// 「合并轮廓真的带凸起」这四件事。这些一旦错了，表现就是
    /// 「标签又浮起来了」或「发光不跟标签」，都是肉眼才能发现的问题。
    func runTabWeldSelfTest() {
        var pass = 0
        var fail = 0

        func check(_ ok: Bool, _ label: String) {
            if ok { pass += 1 } else { fail += 1; FFDebug.log("[WELD] FAIL \(label)") }
        }

        // ① 常量
        check(FFInteractionPolicy.titleBandHeight == 36, "标题带应为 36")
        check(FFInteractionPolicy.activeTabHeight == 28, "活动标签应为 28")
        check(FFInteractionPolicy.tabTopGap == 8, "上方间隙应为 8")
        check(FFInteractionPolicy.inactiveTabHeight == 22, "非活动标签应为 22")
        check(FFInteractionPolicy.tabTopGap
              + FFInteractionPolicy.inactiveTabHeight
              + FFInteractionPolicy.inactiveTabBottomGap
              == FFInteractionPolicy.titleBandHeight,
              "非活动：8 上间隙 + 22 高 + 6 下空隙 应等于 36")
        // 内凹不能压进面板圆角
        check(FFInteractionPolicy.tabInsetFromPanel
              >= FFTabSilhouette.panelCorner + FFInteractionPolicy.tabSeamFillet,
              "标签左缘退让 \(FFInteractionPolicy.tabInsetFromPanel) 应 ≥ 面板圆角 16 + 内凹 8")

        // ② 活动标签几何：底边贴 0、顶边 = 带高 − 上间隙
        for (name, strip) in [("左", leftTabStrip), ("右", rightTabStrip)] {
            guard let strip, let tab = strip.activeTabFrame else { continue }
            check(abs(tab.minY) < 0.5, "\(name)标签底边应贴 0（实为 \(tab.minY)）")
            check(abs(tab.maxY - (strip.bounds.height - FFInteractionPolicy.tabTopGap)) < 0.5,
                  "\(name)标签顶边应 = \(strip.bounds.height - FFInteractionPolicy.tabTopGap)（实为 \(tab.maxY)）")
            check(tab.minX >= FFInteractionPolicy.tabInsetFromPanel,
                  "\(name)标签左缘应 ≥ 退让量（实为 \(tab.minX)）")
        }

        // ③ 非活动标签：顶部与活动对齐，底边比活动高 6
        for (name, strip) in [("左", leftTabStrip), ("右", rightTabStrip)] {
            guard let strip, strip.subviews.count > 0 else { continue }
            let items = strip.allTabItems()
            guard items.count >= 2, let active = items.first(where: { $0.isActive }) else { continue }
            let inactive = items.filter { !$0.isActive }
            for item in inactive {
                let f = item.convert(item.bounds, to: strip)
                let a = active.convert(active.bounds, to: strip)
                check(abs(f.maxY - a.maxY) < 0.5, "\(name)非活动标签顶边应与活动对齐")
                check(abs(f.minY - FFInteractionPolicy.inactiveTabBottomGap) < 0.5,
                      "\(name)非活动标签底边应离面板 6（实为 \(f.minY)）")
            }
        }

        // ④ 不变量：发光收到的矩形 == 当前活动标签（换算到发光坐标系）
        if let strip = leftTabStrip, let glow = leftActiveBorder,
           let wrapper = leftPaneWrapper, let tab = strip.activeTabFrame {
            if let got = glow.tabRect {
                // 标签底边（minY）应等于面板顶边：wrapper 高 − 带高
                check(abs(got.minY - (glow.bounds.height - FFInteractionPolicy.titleBandHeight)) < 1,
                      "发光收到的标签底边应等于面板顶边（实为 \(got.minY) vs \(glow.bounds.height - FFInteractionPolicy.titleBandHeight)）")
                // 标签顶边应等于 视图高 − 上间隙
                check(abs(got.maxY - (glow.bounds.height - FFInteractionPolicy.tabTopGap)) < 1,
                      "发光收到的标签顶边应等于 视图高 − 上间隙（实为 \(got.maxY) vs \(glow.bounds.height - FFInteractionPolicy.tabTopGap)）")
                check(abs(got.width - tab.width) < 1, "发光收到的标签宽度应与标签一致")
                // 横向：与 activeTabFrame 换算后一致
                let converted = wrapper.convert(tab, from: strip)
                check(abs(got.minX - converted.minX) < 1, "发光横向位置应与标签一致")
            } else {
                check(false, "发光没收到标签矩形")
            }
        }

        // ⑤ 合并轮廓真的带凸起（不是退化成矩形）
        let panel = NSRect(x: 8, y: 8, width: 540, height: 800)
        let tab = NSRect(x: 34, y: panel.maxY, width: 120,
                         height: FFInteractionPolicy.activeTabHeight)
        let withTab = FFTabSilhouette.composite(panel: panel, tab: tab)
        let withoutTab = FFTabSilhouette.composite(panel: panel, tab: nil)
        check(withTab.bounds.height > withoutTab.bounds.height + 20,
              "有标签的轮廓应比无标签高出一个标签高度（\(withTab.bounds.height) vs \(withoutTab.bounds.height)）")

        FFDebug.log("[WELD] 标签焊接自检 通过\(pass) 失败\(fail)")
    }

    /// 列表列 / 窗口外壳 / 切换动画自检（2026-10-20 #3 #5 #2 #10）
    func runListShellSelfTest() {
        var pass = 0
        var fail = 0
        func check(_ ok: Bool, _ label: String) {
            if ok { pass += 1 } else { fail += 1; FFDebug.log("[SHELL] FAIL \(label)") }
        }

        // ① 列定义：默认四列、名称必选、大小右对齐
        let defaults = FFListColumn.allCases.filter { $0.defaultVisible }
        check(defaults == [.name, .kind, .size, .modified],
              "默认列应为 名称/类型/大小/修改日期（实为 \(defaults.map { $0.rawValue })）")
        check(FFListColumn.name.isRequired && !FFListColumn.kind.isRequired, "只有名称是必选列")
        check(FFListColumn.size.alignment == .right, "大小列应右对齐")
        check(FFListColumn.name.alignment == .left, "名称列应左对齐")

        // ② 可见性切换 + 持久化往返
        let original = FFListColumnsState.visibleColumns()
        // 断言「翻转」而不是「一定变为可见」——默认值可能是用户改过的
        let createdBefore = FFListColumnsState.isVisible(.created)
        FFListColumnsState.toggle(.created)
        check(FFListColumnsState.isVisible(.created) == !createdBefore,
              "切换创建日期应翻转可见性（前=\(createdBefore)）")
        FFListColumnsState.toggle(.created)
        FFListColumnsState.toggle(.name)   // 必选列：不应生效
        check(FFListColumnsState.isVisible(.name), "名称列不可关闭")
        FFListColumnsState.setVisible(original)
        check(FFListColumnsState.visibleColumns() == original, "可见列应能还原")

        // ③ 放不下时的收起顺序：说明 → 标签 → 创建日期 → 类型 → 大小 → 修改日期
        let all = FFListColumn.allCases
        let narrow = FFListColumnsState.columnsFitting(in: 380, from: all)
        check(narrow.contains(.name), "名称列永不被收起")
        check(!narrow.contains(.comment), "窄面板应先收起说明列")
        let wide = FFListColumnsState.columnsFitting(in: 2000, from: all)
        check(wide.count == all.count, "宽面板应显示全部列")

        // ④ 排序键：只有四个固定 key，可选列不给 prototype
        check(FFListColumn.kind.sortKey == "type" && FFListColumn.size.sortKey == "size",
              "类型/大小列排序键应为 type/size")
        check(FFListColumn.created.sortKey == nil && FFListColumn.comment.sortKey == nil,
              "创建日期/说明列不支持排序")

        // ⑤ 窗口圆角（半径 12 + 连续曲率）
        check(FFWindowShape.cornerRadius == 12, "窗口圆角应为 12")
        if let window, let layer = window.contentView?.layer {
            check(abs(layer.cornerRadius - 12) < 0.5, "窗口 contentView 应设 12 圆角")
            check(layer.cornerCurve == .continuous, "窗口圆角应为连续曲率（非圆弧）")
        }

        // ⑥ 切换动画参数
        check(abs(FFPaneModeAnimator.duration - 0.36) < 0.001, "切换时长应为 0.36s")

        // ⑦ 垂直中线：名称列图标/文字与各元信息列都用 centerY（R-10）
        if let list = leftPaneContainer?.subviews.compactMap({ $0 as? FileListView }).first {
            check(list.usesSharedRowMidline, "名称列图标与文字应共用行中线")
            check(list.visibleColumnIDs.contains(FFListColumn.size.rawValue)
                  || !FFListColumnsState.isVisible(.size),
                  "可见列与状态应一致")
        }

        // ⑧ 可选列真的能渲染出内容（不是空列）
        if let list = leftPaneContainer?.subviews.compactMap({ $0 as? FileListView }).first,
           list.tableRowCount > 0 {
            let kind = list.debugCellText(for: .kind, row: 0) ?? ""
            let size = list.debugCellText(for: .size, row: 0) ?? ""
            let modified = list.debugCellText(for: .modified, row: 0) ?? ""
            let created = list.debugCellText(for: .created, row: 0) ?? ""
            check(!kind.isEmpty, "类型列应有内容（实为「\(kind)」）")
            check(!size.isEmpty, "大小列应有内容")
            check(!modified.isEmpty, "修改日期列应有内容")
            check(!created.isEmpty, "创建日期列应有内容（可选列渲染路径）")
        }

        FFDebug.log("[SHELL] 列表与外壳自检 通过\(pass) 失败\(fail)")
    }

    /// 操作区左半 / 右半各取一个窗口坐标点
    private func windowPointInOperationHalf(side: PaneSide) -> NSPoint {
        guard let cv = window?.contentView else { return NSPoint(x: 100, y: 100) }
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        let midX = (sidebarRight + cv.bounds.width) / 2
        let x = side == .left ? (sidebarRight + midX) / 2 : (midX + cv.bounds.width) / 2
        return cv.convert(NSPoint(x: x, y: cv.bounds.midY), to: nil)
    }

    /// 某个面板主体的一个窗口坐标点
    private func windowPointInPane(_ side: PaneSide) -> NSPoint {
        let wrapper = side == .left ? leftPaneWrapper : rightPaneWrapper
        guard let cv = window?.contentView, let view = wrapper, view.superview != nil else {
            return NSPoint(x: 100, y: 100)
        }
        let frame = cv.convert(view.frame, from: view.superview)
        return cv.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
    }
}
#endif

