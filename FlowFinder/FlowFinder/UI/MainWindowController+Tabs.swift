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
        let showsTabs = store.count > 1
        strip?.isHidden = !showsTabs
        let heightConstraint = (side == .left) ? leftTabStripHeight : rightTabStripHeight
        heightConstraint?.constant = showsTabs ? MainWindowController.tabStripHeight : 0
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

    /// 跨面板接收标签（B5 修订）：合并保留落点面板——被拖标签追加到落点面板
    /// 最后并激活，落点面板成为活动面板。`at` 仅在同面板降级路径使用；
    /// strip 的跨面板分支固定传 items.count（排最后）。
    func receiveTab(side: PaneSide, session: PaneTabSession, at index: Int) {
        guard let store = tabsStore(for: side) else { return }
        let ctx = PaneTabDragContext.shared

        // 同组落点只做重排：早期实现会 insert 一份副本，拖一下标签就多出一个，
        // 这也是「拖拽功能像没实现」的直接原因之一。
        if ctx.sourceSide == side, let from = ctx.sourceIndex {
            if store.move(from: from, to: index) {
                refreshTabStrip(side: side)
            }
            ctx.clear()
            return
        }

        if let sourceSide = ctx.sourceSide, sourceSide != side {
            // 源面板至少保留一个标签（只剩 1 个时 item 层已禁止发起拖拽，此处兜底）
            guard let sourceIndex = PaneTabDragContext.shared.sourceIndex,
                  let sourceStore = tabsStore(for: sourceSide), sourceStore.canClose else {
                PaneTabDragContext.shared.clear()
                return
            }
            let wasActive = (sourceIndex == sourceStore.activeIndex)
            if sourceStore.close(at: sourceIndex) {
                if wasActive {
                    // 源面板激活标签被移走 → 载入它的新激活标签
                    loadActiveTab(side: sourceSide)
                } else {
                    refreshTabStrip(side: sourceSide)
                }
            }
            // 追加到落点面板最后并激活（确认过的合并行为：不按鼠标位置插队）
            store.insert(session, at: store.count, activate: true)
            loadActiveTab(side: side)
            // 落点面板成为活动面板（焦点 / 发光 / 侧栏标签高亮一起切过去）
            activatePane(side)
        } else {
            store.insert(session, at: index)
            loadActiveTab(side: side)
        }
        PaneTabDragContext.shared.clear()
    }

    // MARK: B5 面板合并（窗口级落点）

    /// 标签拖到窗口级落点（面板内容区 / 卡片缝隙 / 边缘留白）松手的统一入口。
    /// 按拖拽类型与当前面板模式分流：
    /// - 整组合并（拖工具栏空白，#5b）：双窗时并入对侧 → 单窗
    /// - 单标签 + 双窗：并入最近侧面板标签组末尾（细节确认 #2）
    /// - 单标签 + 单窗：拖到另一半 → 拆出新面板（#5c）
    /// 标签拖动松手的统一入口（窗口坐标，由 `PaneTabDropReceiver` 透传）。
    /// 分流顺序：整组合并 → 标签条内（重排 / 跨组）→ 单窗拆分 → 双窗并入最近侧。
    func handleTabDrop(atWindowPoint point: NSPoint) {
        let ctx = PaneTabDragContext.shared
        FFDebug.log("[DROP] point=\(point) group=\(ctx.isGroupMerge) hasSession=\(ctx.session != nil) srcSide=\(String(describing: ctx.sourceSide)) srcIdx=\(String(describing: ctx.sourceIndex)) single=\(isSinglePaneMode)")
        defer { ctx.clear() }

        // 1) 整组拖动（拖工具栏空白）：并入对侧后切单窗
        if ctx.isGroupMerge {
            guard !isSinglePaneMode, let source = ctx.sourceSide else { return }
            let target = nearestPane(forWindowX: point.x)
            if target != source { mergeWholePane(from: source, into: target) }
            return
        }

        guard let session = ctx.session, let sourceSide = ctx.sourceSide else { return }

        // 2) 落在某个可见标签条上：组内重排 / 跨组追加到末尾
        for side in [PaneSide.left, .right] {
            guard let strip = tabStrip(for: side), !strip.isHidden,
                  let index = strip.insertionIndex(atWindowPoint: point),
                  let store = tabsStore(for: side) else { continue }
            if side == sourceSide {
                if let from = ctx.sourceIndex, store.move(from: from, to: index) {
                    refreshTabStrip(side: side)
                }
            } else {
                receiveTab(side: side, session: session, at: store.count)
            }
            return
        }

        // 3) 单窗：拖到另一半 → 拆出新面板
        if isSinglePaneMode {
            guard let side = splitTargetSide(forWindowX: point.x), side != activePane else { return }
            splitActiveTab(to: side, session: session)
            return
        }

        // 4) 双窗：并入鼠标最近的一侧面板末尾
        mergeDroppedTab(into: nearestPane(forWindowX: point.x))
    }

    private func mergeDroppedTab(into side: PaneSide) {
        guard let session = PaneTabDragContext.shared.session,
              let store = tabsStore(for: side) else { return }
        receiveTab(side: side, session: session, at: store.count)
    }

    /// 落点侧判定：以两卡片在 contentView 坐标里的中线分界；单窗模式（另一侧
    /// 已移出分栏）并入活动面板。
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

    // MARK: B5 #5c 拆分（单窗 → 双窗）

    /// 单窗时标签的可拆落点：以「侧栏右缘 + 窗口右缘」的中线分界，
    /// 保证操作区两半各占一半。返回 nil 表示不在可拆区。
    private func splitTargetSide(forWindowX x: CGFloat) -> PaneSide? {
        guard let cv = window?.contentView else { return nil }
        let localX = cv.convert(NSPoint(x: x, y: 0), from: nil).x
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        let midX = (sidebarRight + cv.bounds.maxX) / 2
        return localX < midX ? .left : .right
    }

    /// 拆分投放区提示（拖动期间高亮对侧半区）；拖在自己半区不高亮。
    func splitDropZone(forWindowX x: CGFloat) -> NSRect? {
        guard isSinglePaneMode, !PaneTabDragContext.shared.isGroupMerge,
              let cv = window?.contentView,
              let side = splitTargetSide(forWindowX: x), side != activePane else { return nil }
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        let midX = (sidebarRight + cv.bounds.maxX) / 2
        let left = side == .left
        return NSRect(x: left ? 0 : midX, y: 0,
                      width: left ? midX : cv.bounds.maxX - midX,
                      height: cv.bounds.height)
    }

    /// 把被拖标签从当前组取走，落到对侧成为新面板的唯一标签，恢复双窗。
    func splitActiveTab(to side: PaneSide, session: PaneTabSession) {
        guard isSinglePaneMode, side != activePane,
              let sourceStore = tabsStore(for: activePane),
              let targetStore = tabsStore(for: side) else { return }
        guard sourceStore.remove(sessionID: session.id) else { return }
        // 理论上被拖走的不是最后一个（canDragOut 已拦截），保底补占位
        if sourceStore.count == 0 {
            sourceStore.resetToPlaceholder(PaneTabSession(state: placeholderState()))
        }
        targetStore.replaceAll([session])

        isSinglePaneMode = false
        UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        loadActiveTab(side: activePane)
        activatePane(side)
        loadActiveTab(side: side)
    }

    // MARK: B5 #5b 整组合并（双窗 → 单窗）

    /// 把 source 面板整组并入 target（被拖组标签按原顺序追加到末尾，
    /// 被拖组激活标签立即激活），随后切到单窗（被并侧收起）。
    func mergeWholePane(from source: PaneSide, into target: PaneSide) {
        guard source != target,
              let srcStore = tabsStore(for: source),
              let dstStore = tabsStore(for: target) else { return }

        let newActiveIndex = dstStore.absorb(srcStore)
        // 被并侧补占位（单窗期间不可见，切回双窗时保底有会话）
        srcStore.resetToPlaceholder(PaneTabSession(state: placeholderState()))

        isSinglePaneMode = true
        UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        activatePane(target)
        applyPaneMode()
        loadActiveTab(side: target)
        refreshTabStrip(side: source)
        _ = newActiveIndex
    }

    /// 占位会话：主目录 + 列表视图（与新建标签的默认直觉一致，但路径固定，
    /// 避免「合并后占位标签显示被并前的旧路径」造成困惑）
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

    /// 自检入口：验证「组内重排 / 跨组移动 / 不产生重复标签」三条落点逻辑。
    /// 合成鼠标事件驱动不了 NSDraggingSession 的落点更新，所以这里直接调用
    /// `handleTabDrop`，用真实视图坐标算出的落点覆盖分流分支。
    func runDragSelfTest() {
        // 自检前置条件（2026-10-20 补）：
        // 1) 标签条在「标签数 ≤ 1」时高度约束为 0，新建标签后必须等一次布局才有真实高度。
        //    此前自检直接跑，`windowPointPastLastTab()` 算在 bounds.height == 0 的条上，
        //    落点永远 miss（日志表现为 local.y = -29、bounds 高度 0），五个用例连锁失败。
        // 2) 单窗模式下没有「对侧面板」，跨组移动 / 拆分两块用例的前提不成立。
        if isSinglePaneMode {
            FFDebug.log("[SELFTEST] 当前为单窗，先切双窗再跑用例")
            isSinglePaneMode = false
            UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
            applyPaneMode()
        }
        window?.contentView?.layoutSubtreeIfNeeded()

        guard let leftStrip = tabStrip(for: .left),
              let leftStore = tabsStore(for: .left),
              let rightStore = tabsStore(for: .right) else {
            FFDebug.log("[SELFTEST] 缺少标签条/标签组，跳过")
            return
        }

        // 左侧补到 3 个标签
        var guardCount = 0
        while leftStore.count < 3 && guardCount < 5 {
            _ = newTab(in: .left)
            guardCount += 1
        }
        leftStore.updateActiveState(viewModel(for: .left).captureSession())
        // 新建标签会改标签条高度约束（1 → 3 个，0 → 32pt），必须布局后才可算落点
        window?.contentView?.layoutSubtreeIfNeeded()
        let beforeCount = leftStore.count
        let beforeIDs = leftStore.tabs.map { $0.id }
        let draggedID = beforeIDs[0]
        let activeBefore = leftStore.tabs[leftStore.activeIndex].id
        FFDebug.log("[SELFTEST] 起始 count=\(beforeCount) active=\(leftStore.activeIndex) stripH=\(leftStrip.bounds.height)")

        // ① 组内重排：把第 1 个标签拖到最后一个之后
        guard let dropPastLast = leftStrip.windowPointPastLastTab() else {
            FFDebug.log("[SELFTEST] 无法计算落点，终止")
            return
        }
        PaneTabDragContext.shared.session = leftStore.tabs[0]
        PaneTabDragContext.shared.sourceSide = .left
        PaneTabDragContext.shared.sourceIndex = 0
        PaneTabDragContext.shared.isGroupMerge = false
        handleTabDrop(atWindowPoint: dropPastLast)

        let afterIDs = leftStore.tabs.map { $0.id }
        // 断言：数量不变、被拖标签落到末尾、原本激活的标签仍激活
        let reorderOK = leftStore.count == beforeCount
            && afterIDs.last == draggedID
            && leftStore.tabs[leftStore.activeIndex].id == activeBefore
        FFDebug.log("[SELFTEST] ① 组内重排 \(reorderOK ? "PASS" : "FAIL") count=\(leftStore.count) active=\(leftStore.activeIndex) 末位是被拖标签=\(afterIDs.last == draggedID)")

        // ② 跨组移动：把左侧最后一个标签拖到右侧面板主体
        let rightPoint = windowPointInPane(.right)
        let sourceIndex = leftStore.count - 1
        let sourceTitle = leftStore.tabs[sourceIndex].title
        PaneTabDragContext.shared.session = leftStore.tabs[sourceIndex]
        PaneTabDragContext.shared.sourceSide = .left
        PaneTabDragContext.shared.sourceIndex = sourceIndex
        PaneTabDragContext.shared.isGroupMerge = false
        let rightBefore = rightStore.count
        handleTabDrop(atWindowPoint: rightPoint)

        let crossOK = rightStore.count == rightBefore + 1
            && leftStore.count == beforeCount - 1
            && rightStore.tabs.last?.title == sourceTitle
        FFDebug.log("[SELFTEST] ② 跨组移动 \(crossOK ? "PASS" : "FAIL") left=\(leftStore.count) right=\(rightStore.count) last=\(rightStore.tabs.last?.title ?? "nil")")

        // ③ 同组重复拖入不得产生副本
        let countBeforeNoop = leftStore.count
        PaneTabDragContext.shared.session = leftStore.tabs[0]
        PaneTabDragContext.shared.sourceSide = .left
        PaneTabDragContext.shared.sourceIndex = 0
        handleTabDrop(atWindowPoint: windowPointInPane(.left))
        let noDupOK = leftStore.count == countBeforeNoop
        FFDebug.log("[SELFTEST] ③ 同组落点不复制 \(noDupOK ? "PASS" : "FAIL") count=\(leftStore.count)")

        // ④ 单窗拆分：切单窗后把活动面板首标签拖到另一半
        isSinglePaneMode = true
        UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        window?.contentView?.layoutSubtreeIfNeeded()

        let splitSource = activePane
        let splitTarget: PaneSide = splitSource == .left ? .right : .left
        guard let srcStore = tabsStore(for: splitSource),
              let dstStore = tabsStore(for: splitTarget),
              srcStore.count >= 2 else {
            FFDebug.log("[SELFTEST] ④ 单窗拆分 SKIP 源标签不足")
            return
        }
        let splitID = srcStore.tabs[0].id
        let splitSrcCount = srcStore.count
        PaneTabDragContext.shared.session = srcStore.tabs[0]
        PaneTabDragContext.shared.sourceSide = splitSource
        PaneTabDragContext.shared.sourceIndex = 0
        PaneTabDragContext.shared.isGroupMerge = false
        handleTabDrop(atWindowPoint: windowPointInSplitHalf(oppositeTo: splitSource))

        let splitOK = !isSinglePaneMode
            && dstStore.count == 1
            && dstStore.tabs.first?.id == splitID
            && srcStore.count == splitSrcCount - 1
        FFDebug.log("[SELFTEST] ④ 单窗拆分 \(splitOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) 目标组=\(dstStore.count) 源组=\(srcStore.count)")

        // ⑤ 整组合并：把右组拖到左组，应合为一组并切单窗
        window?.contentView?.layoutSubtreeIfNeeded()
        let leftCountBefore = tabsStore(for: .left)?.count ?? 0
        let rightCountBefore = tabsStore(for: .right)?.count ?? 0
        PaneTabDragContext.shared.isGroupMerge = true
        PaneTabDragContext.shared.session = nil
        PaneTabDragContext.shared.sourceSide = .right
        PaneTabDragContext.shared.sourceIndex = nil
        handleTabDrop(atWindowPoint: windowPointInPane(.left))
        let mergeOK = isSinglePaneMode
            && (tabsStore(for: .left)?.count ?? 0) == leftCountBefore + rightCountBefore
        FFDebug.log("[SELFTEST] ⑤ 整组合并 \(mergeOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) left=\(tabsStore(for: .left)?.count ?? -1) 期望=\(leftCountBefore + rightCountBefore)")
    }

    /// 单窗模式下「另一半」的一个窗口坐标点（对面半区中线过 40pt）
    private func windowPointInSplitHalf(oppositeTo side: PaneSide) -> NSPoint {
        guard let cv = window?.contentView else { return NSPoint(x: 100, y: 100) }
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        let midX = (sidebarRight + cv.bounds.width) / 2
        let x = side == .left ? midX + 40 : midX - 40
        return cv.convert(NSPoint(x: x, y: cv.bounds.midY), to: nil)
    }

    /// 右侧面板主体的一个窗口坐标点
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
