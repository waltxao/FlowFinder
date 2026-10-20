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
        defer { ctx.clear() }

        // 0) 2026-10-20 #1：拖的是操作面板（语义上等于拖当前那个标签）
        if ctx.isPaneDrag {
            handlePaneDrop(atWindowPoint: point)
            return
        }

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

    // MARK: - 面板拖放（2026-10-20 #1）
    //
    // 语义：**拖操作面板 = 拖它当前那个标签**（SPEC-2026-10-20 §1.4）。
    //   - 双面板：落在对面面板 → 只搬当前标签；源面板被搬空才消失（合并成单面板）
    //   - 单面板 + 多标签：窗口右半区 → 拆出右面板
    //   - 窗口外：独立成新窗口
    //   - 其余：回原位

    /// 面板拖动落在窗口内时的分流
    private func handlePaneDrop(atWindowPoint point: NSPoint) {
        guard let source = PaneTabDragContext.shared.sourceSide,
              let sourceStore = tabsStore(for: source), sourceStore.count >= 1 else { return }
        let session = sourceStore.active

        if !isSinglePaneMode {
            // 双面板：落在对面面板上 → 只搬当前标签
            let target = nearestPane(forWindowX: point.x)
            if target != source {
                moveTabToOtherPane(from: source, to: target, session: session)
            } else {
                FFDebug.log("[PANEDROP] 落在本侧，回原位")
            }
            return
        }

        // 单面板 + 多标签：窗口右半区 → 拆出右面板
        if sourceStore.count >= 2, isInOperationRightHalf(windowX: point.x) {
            splitPaneTabOut(from: source, session: session)
            return
        }

        FFDebug.log("[PANEDROP] 无有效落点，回原位")
    }

    /// 把一个标签搬到对面面板。源面板被搬空 → 面板消失、窗口转单面板。
    private func moveTabToOtherPane(from source: PaneSide, to target: PaneSide, session: PaneTabSession) {
        guard let srcStore = tabsStore(for: source),
              let dstStore = tabsStore(for: target) else { return }
        guard srcStore.remove(sessionID: session.id) else { return }

        let sourceEmptied = srcStore.count == 0
        if sourceEmptied {
            srcStore.resetToPlaceholder(PaneTabSession(state: placeholderState()))
            isSinglePaneMode = true
            UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        }

        dstStore.insert(session, at: dstStore.count, activate: true)
        activatePane(target)
        applyPaneMode()
        if !sourceEmptied {
            loadActiveTab(side: source)
        }
        loadActiveTab(side: target)
        FFDebug.log("[PANEDROP] 并入对面 target=\(target) 源被搬空=\(sourceEmptied)")
    }

    /// 单面板把当前标签拆成独立的一栏：左边保留其余标签，右边是被拆出的标签。
    private func splitPaneTabOut(from source: PaneSide, session: PaneTabSession) {
        guard let srcStore = tabsStore(for: source) else { return }
        let opposite: PaneSide = source == .left ? .right : .left
        guard let oppStore = tabsStore(for: opposite) else { return }
        guard srcStore.remove(sessionID: session.id) else { return }

        if source == .left {
            // 左侧保留其余标签，右侧是被拆出的标签
            if srcStore.count == 0 { srcStore.resetToPlaceholder(PaneTabSession(state: placeholderState())) }
            oppStore.replaceAll([session])
        } else {
            // 源本来在右：剩余标签挪到左，被拆出的标签占右
            let remaining = srcStore.tabs
            srcStore.replaceAll([session])
            oppStore.replaceAll(remaining.isEmpty
                ? [PaneTabSession(state: placeholderState())]
                : remaining)
        }

        isSinglePaneMode = false
        UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        loadActiveTab(side: .left)
        loadActiveTab(side: .right)
        activatePane(.right)
        FFDebug.log("[PANEDROP] 拆出右面板")
    }

    /// 面板拖动结束（拖拽源回调）。落在窗口外 → 独立成新窗口。
    func handlePaneDragEnded(atScreenPoint point: NSPoint, side: PaneSide) {
        guard let window else { return }
        // 落在窗口内 → 落点已由窗口级接收器处理（handlePaneDrop）
        if window.frame.contains(point) { return }
        guard let store = tabsStore(for: side), store.count >= 1 else { return }
        let session = store.active
        detachTabToNewWindow(session: session, from: side, atScreenPoint: point)
    }

    /// 把标签从当前窗口摘出去，另开一个独立窗口承载它。
    private func detachTabToNewWindow(session: PaneTabSession, from side: PaneSide, atScreenPoint point: NSPoint) {
        guard let store = tabsStore(for: side) else { return }
        store.remove(sessionID: session.id)
        let emptied = store.count == 0
        if emptied {
            store.resetToPlaceholder(PaneTabSession(state: placeholderState()))
            isSinglePaneMode = true
            UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        }

        let controller = MainWindowController()
        controller.leftPaneViewModel.restoreSession(session.state)
        controller.leftTabsStore?.replaceAll([session])
        controller.refreshTabStrip(side: .left)
        if let newWindow = controller.window {
            // 鼠标落点附近开窗（AppKit 屏幕坐标为左下原点）
            newWindow.setFrameOrigin(NSPoint(x: point.x - 60, y: point.y - 60))
        }
        (NSApp.delegate as? AppDelegate)?.registerWindowController(controller)
        controller.showWindow(nil)
        controller.leftPaneViewModel.restoreSession(session.state)
        controller.loadActiveTab(side: .left)

        if emptied {
            applyPaneMode()
        } else {
            loadActiveTab(side: side)
        }
        FFDebug.log("[PANEDROP] 拆成独立窗口 title=\(session.title)")
    }

    /// 落点是否在操作区（去掉侧栏）的右半边
    private func isInOperationRightHalf(windowX x: CGFloat) -> Bool {
        guard let cv = window?.contentView else { return false }
        let localX = cv.convert(NSPoint(x: x, y: 0), from: nil).x
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        return localX >= (sidebarRight + cv.bounds.maxX) / 2
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
        guard let cv = window?.contentView else { return nil }

        // 2026-10-20 #1：面板拖动 → 高亮操作区右半边（松开即拆出右面板）
        if PaneTabDragContext.shared.isPaneDrag {
            guard isSinglePaneMode else { return nil }
            let sidebarRight = sidebarView.flatMap { view in
                view.superview.map { cv.convert(view.frame, from: $0).maxX }
            } ?? 0
            let midX = (sidebarRight + cv.bounds.maxX) / 2
            return NSRect(x: midX, y: 0,
                          width: cv.bounds.maxX - midX,
                          height: cv.bounds.height)
        }

        guard isSinglePaneMode, !PaneTabDragContext.shared.isGroupMerge,
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

        // 吐出关键几何（窗口坐标），供自动化拖拽测试定位起手点
        if let cv = window?.contentView {
            func frame(_ v: NSView?) -> String {
                guard let v, let sp = v.superview else { return "nil" }
                let r = cv.convert(v.frame, from: sp)
                return "x=\(Int(r.minX))..\(Int(r.maxX)) y=\(Int(r.minY))..\(Int(r.maxY))"
            }
            FFDebug.log("[GEO] card=\(frame(leftPaneToolbar?.superview)) toolbar=\(frame(leftPaneToolbar)) strip=\(frame(leftTabStrip)) sidebar=\(frame(sidebarView))")
        }

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

        // ─────────────────────────────────────────────────────────────
        // 2026-10-20 #1：面板拖动模型（拖面板 = 拖当前标签）
        // ─────────────────────────────────────────────────────────────

        // ⑥ 面板拖到对面面板：源面板还剩别的标签 → 只搬当前标签，仍是双面板
        // 前提是双面板——第 ⑤ 项结束时是单窗，这里先切回双窗
        if isSinglePaneMode {
            isSinglePaneMode = false
            UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
            applyPaneMode()
        }
        while leftStore.count > 2 { leftStore.close(at: leftStore.count - 1) }
        while leftStore.count < 2 { _ = newTab(in: .left) }
        while rightStore.count > 1 { rightStore.close(at: rightStore.count - 1) }
        window?.contentView?.layoutSubtreeIfNeeded()

        let leftBeforePaneDrag = leftStore.count
        let rightBeforePaneDrag = rightStore.count
        beginPaneDrag(from: .left)
        handleTabDrop(atWindowPoint: windowPointInPane(.right))
        let paneMergeOK = !isSinglePaneMode
            && leftStore.count == leftBeforePaneDrag - 1
            && rightStore.count == rightBeforePaneDrag + 1
        FFDebug.log("[SELFTEST] ⑥ 面板拖动并入对面 \(paneMergeOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) left=\(leftStore.count) right=\(rightStore.count)")

        // ⑦ 面板拖动把源面板搬空 → 源面板消失，窗口转单面板
        while leftStore.count > 1 { leftStore.close(at: leftStore.count - 1) }
        window?.contentView?.layoutSubtreeIfNeeded()
        let rightBeforeEmpty = rightStore.count
        beginPaneDrag(from: .left)
        handleTabDrop(atWindowPoint: windowPointInPane(.right))
        let paneCollapseOK = isSinglePaneMode && rightStore.count == rightBeforeEmpty + 1
        FFDebug.log("[SELFTEST] ⑦ 源面板搬空合并 \(paneCollapseOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) right=\(rightStore.count)")

        // ⑧ 单面板 + 多标签 → 拖到操作区右半边 → 拆出右面板
        isSinglePaneMode = true
        UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        let srcSide = activePane
        guard let srcStore = tabsStore(for: srcSide) else {
            FFDebug.log("[SELFTEST] ⑧ 缺少源标签组")
            return
        }
        while srcStore.count < 2 { _ = newTab(in: srcSide) }
        window?.contentView?.layoutSubtreeIfNeeded()
        let srcBeforeSplit = srcStore.count
        let paneDraggedID = srcStore.active.id
        beginPaneDrag(from: srcSide)
        handleTabDrop(atWindowPoint: windowPointInOperationRightHalf())
        // 拆分规则固定：左边保留其余标签，右边是被拆出的那一个
        let rightAfter = tabsStore(for: .right)
        let leftAfter = tabsStore(for: .left)
        let paneSplitOK = !isSinglePaneMode
            && (rightAfter?.count ?? 0) == 1
            && (rightAfter?.tabs.first?.id == paneDraggedID)
            && (leftAfter?.count ?? 0) == srcBeforeSplit - 1
        FFDebug.log("[SELFTEST] ⑧ 右半区拆出右面板 \(paneSplitOK ? "PASS" : "FAIL") single=\(isSinglePaneMode) 左=\(leftAfter?.count ?? -1) 右=\(rightAfter?.count ?? -1) 期望左=\(srcBeforeSplit - 1)")
    }

    /// 模拟一次「拖操作面板」会话（合成鼠标事件驱动不了 NSDraggingSession 的落点更新，
    /// 这里直接写入拖拽上下文，落点仍走真实的 handleTabDrop 分流）
    private func beginPaneDrag(from side: PaneSide) {
        let ctx = PaneTabDragContext.shared
        ctx.isPaneDrag = true
        ctx.isGroupMerge = false
        ctx.session = nil
        ctx.sourceSide = side
        ctx.sourceIndex = nil
    }

    /// 操作区右半边的一个窗口坐标点
    private func windowPointInOperationRightHalf() -> NSPoint {
        guard let cv = window?.contentView else { return NSPoint(x: 100, y: 100) }
        let sidebarRight = sidebarView.flatMap { view in
            view.superview.map { cv.convert(view.frame, from: $0).maxX }
        } ?? 0
        let midX = (sidebarRight + cv.bounds.width) / 2
        return cv.convert(NSPoint(x: midX + 60, y: cv.bounds.midY), to: nil)
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
