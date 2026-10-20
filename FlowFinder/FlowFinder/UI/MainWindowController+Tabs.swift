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
        // 2026-10-20 #1：单面板且只有一个标签时，拖面板 = 拖窗口
        // （没有第二个标签可搬，语义上退化成拖整个窗口）
        let toolbar = (side == .left) ? leftPaneToolbar : rightPaneToolbar
        toolbar?.dragsWindowInstead = isSinglePaneMode && store.count <= 1
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

