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
        // 2026-10-21 C2：标签条常显在全局顶栏内，位置由 updateTabStripFrames 计算。
        updateTabStripFrames()
        // 诊断：各标签的实际位置（自动化拖拽测试用）
        for (i, item) in (strip?.allTabItems() ?? []).enumerated() {
            FFDebug.log("[GEO] 标签 side=\(side) #\(i) frame=\(item.convert(item.bounds, to: nil))")
        }
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
        guard let store = tabsStore(for: side) else { return }
        if store.count <= 1 {
            window?.performClose(nil)
            return
        }
        guard store.close(at: index) else { return }
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

    // MARK: - 标签拖放（2026-10-20 #4 重做）
    //
    // 语义：**拖的对象是标签**（不是整块面板），落点决定标签去哪。
    //
    //   落在标签条          → 并入那个面板（末尾或指定位置）
    //   落在操作区（单栏）  → 拆出第二块面板（窗口自动加宽）
    //   落在操作区（双栏）  → 并入那一侧面板
    //   落在窗口外          → 独立成新窗口
    //   源面板被搬空        → 源窗口自动关闭
    //
    // 跨窗口由 `FFPaneDragController` 按屏幕坐标遍历已注册窗口判定落点，
    // 目标窗口负责最后的落地动作。

    /// 占位标签会话（带占位标记，用于判断面板是否被搬空）
    func placeholderSession() -> PaneTabSession {
        var session = PaneTabSession(state: placeholderState())
        session.isPlaceholder = true
        return session
    }

    /// 从源面板摘走一个标签，返回被摘走的会话
    @discardableResult
    func takeTabOut(side: PaneSide, index: Int) -> PaneTabSession? {
        guard let store = tabsStore(for: side), store.tabs.indices.contains(index) else { return nil }
        let session = store.tabs[index]
        if store.count > 1 {
            store.close(at: index)
        } else {
            store.resetToPlaceholder(placeholderSession())
        }
        refreshTabStrip(side: side)
        return session
    }

    /// 面板是否已被搬空（只剩占位）
    func isPaneEmpty(side: PaneSide) -> Bool {
        guard let store = tabsStore(for: side) else { return true }
        return store.tabs.allSatisfy { $0.isPlaceholder }
    }

    /// 拖动落点处理：把源面板的标签送到目标窗口的落点
    ///
    /// 2026-10-20 第五轮 C：**源面板被搬空 → 面板消失**（用户裁定）。
    ///   · 跨窗口：源窗口整个关掉（原有语义）
    ///   · 同窗口双栏：空面板折叠，窗口变单栏（此前空占位会留在原地）
    /// 注意 sourceEmpty 必须在 acceptTab **之后**计算——
    /// 同窗口拖回自己面板（重排）时，store 会先空再被填回，先算会误折叠。
    func transferTab(side: PaneSide, index: Int, to target: FFDropTarget) {
        guard let session = takeTabOut(side: side, index: index) else { return }
        target.window.acceptTab(session, into: target)
        guard isPaneEmpty(side: side) else { return }
        if target.window !== self {
            closeSelfAfterEmptyPane()
        } else if !isSinglePaneMode {
            // 同窗口双栏：折叠空面板，显示另一侧
            let revealed: PaneSide = side == .left ? .right : .left
            activePane = revealed
            isSinglePaneMode = true
            UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
            applyPaneMode()
            loadActiveTab(side: revealed)
            FFDebug.log("[TABDRAG] 源面板搬空 → 面板折叠，窗口变单栏（\(revealed)）")
        }
    }

    /// 接收一个落点标签（本窗口执行落地）
    func acceptTab(_ session: PaneTabSession, into target: FFDropTarget) {
        switch target {
        case .tabStrip(_, let side, let index):
            guard let store = tabsStore(for: side) else { return }
            store.insert(session, at: index ?? store.count)
            refreshTabStrip(side: side)
            loadActiveTab(side: side)
            activatePane(side)
        case .paneContent(_, let side):
            acceptTabIntoPane(session, side: side)
        }
    }

    /// 落在操作区：单栏 → 拆出第二块面板；双栏 → 并入那一侧
    ///
    /// 2026-10-20 第五轮 C：单栏时**新面板出现在落点那一侧**（拖右出右、拖左出左），
    /// 原面板挪到另一侧——旧实现固定出在活动面板对侧，与落点语义相反。
    private func acceptTabIntoPane(_ session: PaneTabSession, side: PaneSide) {
        if isSinglePaneMode {
            let active = activePane
            let otherSide: PaneSide = side == .left ? .right : .left
            guard let activeStore = tabsStore(for: active),
                  let newStore = tabsStore(for: side),
                  tabsStore(for: otherSide) != nil else { return }

            // 必须在 newStore.replaceAll 之前读取：落点与活动面板同侧时 newStore === activeStore。
            let existingTabs = activeStore.tabs.filter { !$0.isPlaceholder }
            if existingTabs.isEmpty {
                // 目标面板本来是空的：直接填回，不拆出一个空面板。
                activeStore.replaceAll([session])
                loadActiveTab(side: active)
                return
            }

            newStore.replaceAll([session])
            tabsStore(for: otherSide)?.replaceAll(existingTabs)
            isSinglePaneMode = false
            UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
            activePane = side
            applyPaneMode()
            widenWindowForSecondPane(newSide: side)
            loadActiveTab(side: side)
            loadActiveTab(side: otherSide)
            return
        }

        guard let store = tabsStore(for: side) else { return }
        store.insert(session, at: store.count)
        refreshTabStrip(side: side)
        loadActiveTab(side: side)
        activatePane(side)
    }

    /// 窗口加宽到能放下第二块面板（2026-10-20 第五轮 C 重写）
    ///
    /// 旧实现的坑：单栏时 `paneSplitView.bounds.width` 是**整块操作区宽**
    /// （面板本来就占满），拿来当「新增面板宽」会把窗口加宽到 ~2000pt；
    /// 高度也可能被殃及。新实现：
    ///   目标宽 = 侧栏宽 + 操作区宽 × 2 + 卡片留白，**钳制到屏幕可视宽度**；
    ///   只改宽度与对应侧 origin，高度绝不动；向左加宽时左缘贴屏幕边保护。
    private func widenWindowForSecondPane(newSide: PaneSide) {
        guard let window, let screen = window.screen else { return }
        let sidebarWidth = sidebarView.frame.width
        let opWidth = max(FFDividerGlowMath.minPaneWidth, paneSplitView?.bounds.width ?? 0)
        let visibleW = screen.visibleFrame.width
        // 理想：侧栏 + 两倍操作区 + 两侧卡片留白
        var target = sidebarWidth + opWidth * 2 + FFActivePaneBorderView.edgeOutset * 2
        target = max(1060, min(target, visibleW))
        // 钳制后操作区可能小于理想值，交由 NSSplitView 自行分配（两侧各保最小宽）

        var frame = window.frame
        let delta = target - frame.width
        if newSide == .left {
            // 新面板在左 → 窗口向左加宽（右缘不动），左缘贴屏幕边保护
            frame.origin.x = max(screen.visibleFrame.minX, frame.origin.x - delta)
            frame.size.width = min(target, frame.maxX - frame.origin.x)
        } else {
            // 新面板在右 → 窗口向右加宽（左缘不动），右缘不超出屏幕
            let maxW = screen.visibleFrame.maxX - frame.origin.x
            frame.size.width = min(target, maxW)
        }
        guard abs(frame.width - window.frame.width) > 0.5 else { return }
        resizeWindowKeepingSidebar(frame)
    }

    /// 标签被拖出窗口 → 独立成新窗口
    ///
    /// 2026-10-20 第五轮 C：双栏窗口里搬空**一块**面板时，只折叠该面板
    /// （另一块还有标签，整窗关掉会连它一起丢）——仅当两块都空才关窗。
    func detachTabToNewWindow(side: PaneSide, index: Int, atScreenPoint point: NSPoint) {
        guard let session = takeTabOut(side: side, index: index) else { return }
        let sourceEmpty = isPaneEmpty(side: side)

        // 先注入标签、定位，再显示；避免新窗口在默认位置用默认内容闪一下。
        // 自检必须关掉：派生窗口若再跑拖拽自检，会无限递归创建窗口。
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        controller.leftTabsStore?.replaceAll([session])
        controller.refreshTabStrip(side: .left)
        if let newWindow = controller.window {
            newWindow.setFrameOrigin(NSPoint(x: point.x - 60, y: point.y - 60))
        }
        controller.loadActiveTab(side: .left)
        (NSApp.delegate as? AppDelegate)?.registerWindowController(controller)
        controller.prepareForInitialDisplay()
        controller.showWindow(nil)
        FFLayoutDiagnostics.logTransition("拖出新窗口后", controller)
        FFLayoutDiagnostics.logNextRunLoop("拖出新窗口下一拍", controller)
        FFDebug.log("[TABDRAG] 标签拖出成独立窗口 title=\(session.title)")

        guard sourceEmpty else { return }
        // 另一块面板还有标签 → 只折叠空的那块（变单栏显示另一侧）
        let otherSide: PaneSide = side == .left ? .right : .left
        let otherHasContent = !(tabsStore(for: otherSide)?.tabs.allSatisfy { $0.isPlaceholder } ?? true)
        if otherHasContent && !isSinglePaneMode {
            activePane = otherSide
            isSinglePaneMode = true
            UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
            applyPaneMode()
            loadActiveTab(side: otherSide)
            FFDebug.log("[TABDRAG] 双栏中搬空一块 → 折叠该面板，窗口变单栏")
        } else {
            closeSelfAfterEmptyPane()
        }
    }

    /// 面板被搬空 → 关掉本窗口；若是最后一个窗口，补一个默认窗口
    private func closeSelfAfterEmptyPane() {
        let others = NSApp.windows.filter { $0.isVisible && $0 !== window }.count
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.close()
            FFDebug.log("[TABDRAG] 源面板已空，窗口关闭（其它窗口 \(others) 个）")
            if others == 0 {
                let fresh = MainWindowController()
                (NSApp.delegate as? AppDelegate)?.registerWindowController(fresh)
                fresh.showWindow(nil)
            }
        }
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
        // ⌘W 在辅助窗口（设置/搜索/查重）里应关闭该窗口，而不是操作主窗口标签。
        if let key = NSApp.keyWindow, key !== window {
            key.performClose(sender)
            return
        }
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

    /// 标签拖动模型自检（2026-10-20 #4）
    ///
    /// 覆盖「拖出只搬当前标签 / 拖回落点分流 / 源面板空了要关窗」三条主线。
    /// 跨窗口的物理拖拽靠合成事件不可靠，这里直接调用真实代码路径验证状态变化。
    func runDragSelfTest() {
        guard let leftStore = tabsStore(for: .left),
              let rightStore = tabsStore(for: .right) else {
            FFDebug.log("[SELFTEST] 缺少标签组，跳过")
            return
        }
        // 自检会临时改写标签和路径；结束后必须还原本来的会话，
        // 否则后续的列表/外壳自检会在 /tmp 空目录上跑，误报列内容为空。
        let originalLeftTab = leftStore.active
        let originalRightTab = rightStore.active

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

        // ① 摘走一个标签：源面板少一个，其余标签还在
        let before = leftStore.count
        let taken = takeTabOut(side: .left, index: 0)
        let takeOK = taken != nil && leftStore.count == before - 1
        FFDebug.log("[SELFTEST] ① 摘走一个标签 \(takeOK ? "PASS" : "FAIL") 源=\(leftStore.count) 期望=\(before - 1)")

        // ② 把摘走的标签并到右面板标签条（拖回落点 = 标签条）
        let rightBefore = rightStore.count
        if let session = taken {
            acceptTab(session, into: .tabStrip(window: self, side: .right, index: nil))
        }
        let mergeOK = rightStore.count == rightBefore + 1
        FFDebug.log("[SELFTEST] ② 并入右面板标签条 \(mergeOK ? "PASS" : "FAIL") 右=\(rightStore.count) 期望=\(rightBefore + 1)")

        // ③ 单栏真实链路：左面板 A/B/C，拖 B 到右半区 → 右面板只放 B，左面板保留 A/C
        // 关键：走 FFDropResolver + 真实 panContents，不再直接传 side 绕过落点判定。
        isSinglePaneMode = true
        UserDefaults.standard.set(true, forKey: Self.singlePaneModeKey)
        activePane = .left
        func tab(_ path: String) -> PaneTabSession {
            PaneTabSession(state: PaneState(path: path))
        }
        leftStore.replaceAll([tab("/tmp/a"), tab("/tmp/b"), tab("/tmp/c")], activeAt: 0)
        rightStore.replaceAll([placeholderSession()])
        refreshTabStrip(side: .left)
        refreshTabStrip(side: .right)
        applyPaneMode()
        window?.contentView?.layoutSubtreeIfNeeded()

        var splitOK = false
        if let geometry = dragGeometry(),
           let pane = geometry.paneContents[.left] {
            let pointer = CGPoint(x: pane.rect.midX + 40, y: pane.rect.midY)
            let source = FFDragSource(windowID: geometry.windowID, side: .left, index: 1)
            let decision = FFDropResolver.resolve(source: source,
                                                  pointer: pointer,
                                                  geometries: [geometry])
            if case .split(let windowID, let dropSide) = decision,
               windowID == geometry.windowID,
               dropSide == .right,
               let taken = takeTabOut(side: .left, index: 1) {
                acceptTab(taken, into: .paneContent(window: self, side: dropSide))
                splitOK = !isSinglePaneMode
                    && activePane == .right
                    && leftStore.tabs.map { $0.state.path } == ["/tmp/a", "/tmp/c"]
                    && rightStore.tabs.map { $0.state.path } == ["/tmp/b"]
            }
        }
        FFDebug.log("[SELFTEST] ③ 单栏右半拆双栏 \(splitOK ? "PASS" : "FAIL") 单栏=\(isSinglePaneMode) 活动=\(activePane) 左=\(leftStore.tabs.map { $0.state.path }) 右=\(rightStore.tabs.map { $0.state.path })")

        // ④ 面板被搬空 → 应判定为「空」（用于关窗）
        let emptyProbe = tabsStore(for: .left)
        if let emptyProbe {
            let saved = emptyProbe.tabs
            emptyProbe.resetToPlaceholder(placeholderSession())
            let emptyOK = isPaneEmpty(side: .left)
            emptyProbe.replaceAll(saved)
            FFDebug.log("[SELFTEST] ④ 面板搬空判定 \(emptyOK ? "PASS" : "FAIL")")
        }

        // ⑤ 双栏：把左面板唯一的标签拖到右面板操作区 → 源面板搬空折叠，窗口变单栏
        // （2026-10-20 第五轮 C：搬空的面板消失，不留空占位）
        while leftStore.count > 1 { leftStore.close(at: leftStore.count - 1) }
        if leftStore.tabs.allSatisfy({ $0.isPlaceholder }) {
            _ = newTab(in: .left)
        }
        window?.contentView?.layoutSubtreeIfNeeded()
        if let session = leftStore.tabs.first {
            transferTab(side: .left, index: 0,
                        to: .paneContent(window: self, side: .right))
        }
        let collapseOK = isSinglePaneMode
            && activePane == .right
            && rightStore.count == 2
        FFDebug.log("[SELFTEST] ⑤ 搬空源面板折叠 \(collapseOK ? "PASS" : "FAIL") 单栏=\(isSinglePaneMode) 活动侧=\(activePane) 右=\(rightStore.count) 期望=2")

        // ⑥ 拖出新窗口：源窗口是双栏时，新窗口仍必须是单栏，且只含被拖的标签
        // （旧实现让新窗口继承源窗口的 single_pane_mode，会开出一个带默认右栏的双栏窗口）
        isSinglePaneMode = false
        UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
        applyPaneMode()
        while leftStore.count < 2 { _ = newTab(in: .left) }
        let windowsBefore = Set(NSApp.windows.map { ObjectIdentifier($0) })
        let detachedSession = leftStore.tabs.first
        let leftBefore = leftStore.count
        if detachedSession != nil {
            detachTabToNewWindow(side: .left, index: 0, atScreenPoint: NSPoint(x: 160, y: 160))
        }
        let newWindow = NSApp.windows.first {
            !windowsBefore.contains(ObjectIdentifier($0))
                && $0.windowController is MainWindowController
        }
        let newController = newWindow?.windowController as? MainWindowController
        let detachedOK = detachedSession != nil
            && leftStore.count == leftBefore - 1
            && newController?.isSinglePaneMode == true
            && newController?.leftTabsStore?.count == 1
            && newController?.leftTabsStore?.tabs.first?.id == detachedSession?.id
        FFDebug.log("[SELFTEST] ⑥ 拖出新窗口为单栏 \(detachedOK ? "PASS" : "FAIL") 单栏=\(String(describing: newController?.isSinglePaneMode)) 左标签=\(String(describing: newController?.leftTabsStore?.count)) 期望=1")
        newController?.close()

        // ⑦ 无效落点：侧栏/红绿灯内松手 → returnToSource，不新建窗口
        var invalidOK = false
        if let geometry = dragGeometry(),
           let invalid = geometry.invalidRects.first {
            let source = FFDragSource(windowID: geometry.windowID, side: .left, index: 0)
            let decision = FFDropResolver.resolve(source: source,
                                                  pointer: CGPoint(x: invalid.midX, y: invalid.midY),
                                                  geometries: [geometry])
            invalidOK = (decision == .returnToSource)
        }
        FFDebug.log("[SELFTEST] ⑦ 无效落点回原位 \(invalidOK ? "PASS" : "FAIL")")

        // ⑧ 目标单栏拆双栏：目标原有标签完整保留
        var targetSplitOK = false
        let target = MainWindowController(startsWithSinglePane: true,
                                          showImmediately: false,
                                          runsSelfTests: false)
        if let sourceWindow = window {
            target.window?.setFrameOrigin(NSPoint(x: sourceWindow.frame.maxX + 100,
                                                  y: sourceWindow.frame.minY))
        }
        target.leftTabsStore?.replaceAll([tab("/tmp/x"), tab("/tmp/y")], activeAt: 0)
        target.refreshTabStrip(side: .left)
        target.window?.contentView?.layoutSubtreeIfNeeded()
        if let sourceGeo = dragGeometry(),
           let targetGeo = target.dragGeometry(),
           let targetPane = targetGeo.paneContents[.left],
           let taken = takeTabOut(side: .left, index: 0) {
            let source = FFDragSource(windowID: sourceGeo.windowID, side: .left, index: 0)
            let pointer = CGPoint(x: targetPane.rect.midX + 40, y: targetPane.rect.midY)
            let decision = FFDropResolver.resolve(source: source,
                                                  pointer: pointer,
                                                  geometries: [sourceGeo, targetGeo])
            if case .split(let windowID, let dropSide) = decision,
               windowID == targetGeo.windowID,
               dropSide == .right {
                target.acceptTab(taken, into: .paneContent(window: target, side: dropSide))
                targetSplitOK = target.leftTabsStore?.tabs.map { $0.state.path } == ["/tmp/x", "/tmp/y"]
                    && target.rightTabsStore?.tabs.map { $0.state.path } == [taken.state.path]
                    && !target.isSinglePaneMode
            }
        }
        FFDebug.log("[SELFTEST] ⑧ 目标单栏拆双栏保留标签 \(targetSplitOK ? "PASS" : "FAIL") 左=\(String(describing: target.leftTabsStore?.tabs.map { $0.state.path })) 右=\(String(describing: target.rightTabsStore?.tabs.map { $0.state.path }))")
        target.close()

        // ⑨ 最后一个标签拖出 → 源面板空
        if leftStore.tabs.allSatisfy({ $0.isPlaceholder }) {
            _ = newTab(in: .left)
        }
        var lastTabOK = false
        if let last = leftStore.tabs.first {
            while leftStore.count > 1 { leftStore.close(at: leftStore.count - 1) }
            _ = takeTabOut(side: .left, index: 0)
            lastTabOK = isPaneEmpty(side: .left)
            leftStore.replaceAll([last])
            refreshTabStrip(side: .left)
        }
        FFDebug.log("[SELFTEST] ⑨ 最后标签拖出源面板空 \(lastTabOK ? "PASS" : "FAIL")")

        // ⑩ 跨窗口标签条：按指针位置并入目标
        var crossOK = false
        let crossTarget = MainWindowController(startsWithSinglePane: true,
                                               showImmediately: false,
                                               runsSelfTests: false)
        if let sourceWindow = window {
            crossTarget.window?.setFrameOrigin(NSPoint(x: sourceWindow.frame.maxX + 100,
                                                       y: sourceWindow.frame.minY))
        }
        crossTarget.leftTabsStore?.replaceAll([tab("/tmp/x")], activeAt: 0)
        crossTarget.refreshTabStrip(side: .left)
        crossTarget.window?.contentView?.layoutSubtreeIfNeeded()
        if let sourceGeo = dragGeometry(),
           let targetGeo = crossTarget.dragGeometry(),
           let strip = targetGeo.tabStrips[.left],
           let taken = takeTabOut(side: .left, index: 0) {
            let lastMid = strip.tabRects.last?.midX ?? strip.rect.midX
            let source = FFDragSource(windowID: sourceGeo.windowID, side: .left, index: 0)
            let pointer = CGPoint(x: lastMid + 5, y: strip.rect.midY)
            let decision = FFDropResolver.resolve(source: source,
                                                  pointer: pointer,
                                                  geometries: [sourceGeo, targetGeo])
            if case .merge(let windowID, let side, let index) = decision,
               windowID == targetGeo.windowID,
               side == .left {
                crossTarget.acceptTab(taken, into: .tabStrip(window: crossTarget, side: .left, index: index))
                crossOK = crossTarget.leftTabsStore?.tabs.map { $0.state.path } == ["/tmp/x", taken.state.path]
            }
        }
        FFDebug.log("[SELFTEST] ⑩ 跨窗口标签条并入 \(crossOK ? "PASS" : "FAIL") 目标=\(String(describing: crossTarget.leftTabsStore?.tabs.map { $0.state.path }))")
        crossTarget.close()

        // 复原：把自检前的真实会话放回主窗口，再回到双栏
        leftStore.replaceAll([originalLeftTab])
        rightStore.replaceAll([originalRightTab])
        refreshTabStrip(side: .left)
        refreshTabStrip(side: .right)
        loadActiveTab(side: .left)
        loadActiveTab(side: .right)
        isSinglePaneMode = false
        UserDefaults.standard.set(false, forKey: Self.singlePaneModeKey)
        applyPaneMode()
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
            let tag = "侧栏\(state.sidebarVisible ? "可见" : "隐藏")/单栏\(state.singlePane ? "是" : "否")/缓冲内\(state.pointerInsideTabBuffer ? "是" : "否")/把手\(state.onResizeHandle ? "是" : "否")"

            // ⓪ 把手优先：命中调宽把手时任何区域都放行给 FFSplitView
            // （卡片 8pt 留白同时是「拖窗口」与「调宽」把手，两套手势打架的仲裁）
            if state.onResizeHandle {
                for region in FFRegion.allCases {
                    expect(region, state, .resizeDivider, "把手优先→放行 [\(tag)] \(region)")
                }
                continue
            }

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

        // ⑥ 几何常量：C2 全局顶栏
        if FFInteractionPolicy.titleBandHeight == 36,
           FFInteractionPolicy.activeTabHeight == 30,
           FFInteractionPolicy.inactiveTabHeight == 26,
           FFInteractionPolicy.tabTopGap == 6,
           FFInteractionPolicy.topBarHitSize == 28,
           FFInteractionPolicy.tabSeamFillet == 10 {
            pass += 1
        } else {
            fail += 1
            FFDebug.log("[POLICY] FAIL 几何常量：第二轮应为 36/30/26/6/28/10")
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
        let list = leftFileListView

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
        if let frame = sidebarView.superview?.convert(sidebarView.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.minY + 20), .window, "侧栏底部空白")
        }

        // 卡片四周 8pt 留白（wrapper 左缘）
        if let wrapper = leftPaneWrapper, let frame = wrapper.superview?.convert(wrapper.frame, to: contentView) {
            expect(NSPoint(x: frame.minX + 3, y: frame.midY), .panel, "卡片左缘留白（第五轮 C：不再拖窗口）")
        }

        // ⑥ 调宽把手：C2 顶栏内不算把手，分栏内部同一 X 才算
        if let split = paneSplitView, split.arrangedSubviews.count >= 2,
           let handleX = split.handleXPositions.first {
            let cv = contentView
            // 把手在「卡片外沿」，不是分隔线本身（分隔线在缝隙正中，差 8pt）
            let seamInCV = cv.convert(NSPoint(x: handleX, y: 0), from: split).x
            // 全局顶栏内：超出分栏 bounds，不应命中
            let inBar = NSPoint(x: seamInCV, y: cv.bounds.height - 14)
            if !isPointOnResizeHandle(windowPoint: inBar) {
                pass += 1
            } else {
                fail += 1
                FFDebug.log("[REGION] FAIL 全局顶栏内的缝隙 X 不应命中把手")
            }
            // 分栏内部：应命中
            let inPane = NSPoint(x: seamInCV, y: cv.bounds.height - 100)
            if isPointOnResizeHandle(windowPoint: inPane) {
                pass += 1
            } else {
                fail += 1
                FFDebug.log("[REGION] FAIL 分栏内部的缝隙 X 应命中把手")
            }
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
        if let frame = sidebarView.superview?.convert(sidebarView.frame, to: contentView) {
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
        if let list = leftFileListView,
           let frame = list.superview?.convert(list.frame, to: contentView) {
            expect(NSPoint(x: frame.midX, y: frame.midY), .pressFeedback, "文件列表→不拖动")
        }

        FFDebug.log("[BEHAVIOR] 拖动行为自检 通过\(pass) 失败\(fail)")
    }

    /// 面板宽度自检（Phase 3）：12pt 热区 / 软最小 / 吸附 / 双击 50/50。
    func runPaneWidthSelfTest() {
        var pass = 0
        var fail = 0
        func check(_ ok: Bool, _ label: String) {
            if ok { pass += 1 } else { fail += 1; FFDebug.log("[WIDTH] FAIL \(label)") }
        }

        check(abs(FFDividerGlowMath.hotZoneRadius * 2 - 12) < 0.01,
              "分栏热区应为 12pt（实为 \(FFDividerGlowMath.hotZoneRadius * 2)）")
        check(FFPaneWidthMath.effectiveMin(total: 1200) == 400,
              "宽窗口首选最小应为 400")
        check(FFPaneWidthMath.effectiveMin(total: 780) == 390,
              "1060 窗口 + 280 侧栏时应软降到 390")
        check(FFPaneWidthMath.effectiveMin(total: 720) == 360,
              "窄窗口硬下限应为 360")
        check(abs(FFPaneWidthMath.snappedRatio(0.494, total: 1000) - 0.5) < 0.001,
              "49.4% 应吸附到 50%")
        check(abs(FFPaneWidthMath.doubleClickLeft(total: 1200) - 600) < 0.01,
              "双击应回到 50/50")
        if let split = paneSplitView {
            check(split.adaptivePaneMinimum, "双面板分栏应启用软最小")
            check(split.allowsRatioGestures, "双面板分栏应启用吸附/双击")
            check(split.handleXPositions.count == 2,
                  "双栏应有两个调宽把手（实为 \(split.handleXPositions.count)）")
        } else {
            check(false, "缺少双面板分栏")
        }
        FFDebug.log("[WIDTH] 面板宽度自检 通过\(pass) 失败\(fail)")
    }

    /// 图二压力自检（Phase 0）：20 轮隐藏/显示侧栏 × 单/双栏 × 左右活动面板。
    ///
    /// 每轮只读快照，不主动重绘；结束后恢复用户原来的侧栏/单双栏/活动面板/窗口尺寸。
    func runLayoutStressSelfTest() {
        guard let window, paneSplitView != nil else {
            FFDebug.log("[LAYOUT] FAIL 无窗口或分栏")
            return
        }
        let wasSingle = isSinglePaneMode
        let wasSidebar = isSidebarVisible
        let wasActive = activePane
        let wasFrame = window.frame
        let defaults = UserDefaults.standard
        let oldSidebarHidden = defaults.object(forKey: "sidebar_hidden")

        var failures: [String] = []
        func check(_ phase: String) {
            window.contentView?.layoutSubtreeIfNeeded()
            failures.append(contentsOf: layoutAnomalies(phase: phase).map { "\(phase): \($0)" })
        }

        for cycle in 0..<20 {
            setSidebarVisible(false, animated: false)
            check("第\(cycle)轮-隐藏侧栏")
            activePane = (cycle % 2 == 0) ? .right : .left
            isSinglePaneMode = true
            applyPaneMode()
            check("第\(cycle)轮-单栏-\(activePane)")
            setSidebarVisible(true, animated: false)
            check("第\(cycle)轮-显示侧栏")
            isSinglePaneMode = false
            applyPaneMode()
            check("第\(cycle)轮-双栏")
        }

        activePane = wasActive
        isSinglePaneMode = wasSingle
        applyPaneMode()
        if isSidebarVisible != wasSidebar {
            setSidebarVisible(wasSidebar, animated: false)
        }
        window.setFrame(wasFrame, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        if let oldSidebarHidden {
            defaults.set(oldSidebarHidden, forKey: "sidebar_hidden")
        } else {
            defaults.removeObject(forKey: "sidebar_hidden")
        }

        for failure in failures.prefix(20) {
            FFDebug.log("[LAYOUT] FAIL \(failure)")
        }
        FFDebug.log("[LAYOUT] 布局压力自检 20轮 失败\(failures.count)")
    }

    /// 侧栏隐藏后的标签避让自检（2026-10-21 C2）。
    ///
    /// 真实路径：setSidebarVisible(false) → 顶栏工具/侧栏键常驻 →
    /// 标签组整体右移让开按钮；面板工具栏仍保持 8pt 缩进。
    func runSidebarAvoidanceSelfTest() {
        guard let window, let bar = globalTopBar else {
            FFDebug.log("[AVOID] FAIL 无窗口或全局顶栏")
            return
        }
        let wasVisible = isSidebarVisible
        let testSide: PaneSide = (!isSinglePaneMode || activePane == .left) ? .left : .right
        guard let strip = tabStrip(for: testSide) else {
            FFDebug.log("[AVOID] FAIL 无可用标签条")
            return
        }

        setSidebarVisible(false, animated: false)
        window.contentView?.layoutSubtreeIfNeeded()
        updateTabStripFrames()
        window.contentView?.layoutSubtreeIfNeeded()

        var pass = 0
        var fail = 0
        func check(_ ok: Bool, _ label: String) {
            if ok { pass += 1 } else { fail += 1; FFDebug.log("[AVOID] FAIL \(label)") }
        }

        let tabLeading = FFActivePaneBorderView.edgeOutset + FFInteractionPolicy.tabInsetFromPanel
        let stripFrame = strip.convert(strip.bounds, to: nil)
        let sidebarFrame = bar.convert(bar.sidebarButton.frame, to: nil)
        let themeFrame = bar.convert(bar.themeButton.frame, to: nil)
        let active = strip.allTabItems().first(where: { $0.isActive })
        let tabFrame = active?.convert(active?.bounds ?? .zero, to: nil) ?? .zero

        check(stripFrame.minX >= sidebarFrame.maxX,
              "隐藏侧栏后标签组必须让开侧栏键（\(stripFrame.minX) vs \(sidebarFrame.maxX)）")
        check(tabFrame.minX >= stripFrame.minX + tabLeading - 1,
              "首个标签应对齐标签组内缩 \(tabLeading)（\(tabFrame.minX) vs \(stripFrame.minX)）")
        check(stripFrame.maxX <= themeFrame.minX + 1,
              "标签组右缘不能进入右侧按钮区（\(stripFrame.maxX) vs \(themeFrame.minX)）")
        check(tabFrame.height >= FFInteractionPolicy.activeTabHeight - 0.5,
              "隐藏侧栏后活动标签仍应是 30pt（实为 \(tabFrame.height)）")
        check(leftPaneToolbar.leadingInset == 8 && rightPaneToolbar.leadingInset == 8,
              "隐藏侧栏后两侧工具栏仍应保持 8pt 缩进")

        if wasVisible {
            setSidebarVisible(true, animated: false)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        refreshTabStrip(side: testSide)
        FFDebug.log("[AVOID] 侧栏隐藏避让自检 通过\(pass) 失败\(fail)")
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

        // 焊接自检需要「活动 + 非活动」同屏才有意义。
        // 自检会临时补标签，结束后还原，避免污染用户会话。
        let leftStore = tabsStore(for: .left)
        let rightStore = tabsStore(for: .right)
        let originalLeftTabs = leftStore?.tabs ?? []
        let originalRightTabs = rightStore?.tabs ?? []
        let originalLeftActive = leftStore?.activeIndex ?? 0
        let originalRightActive = rightStore?.activeIndex ?? 0
        if let leftStore, leftStore.count < 2 { _ = newTab(in: .left) }
        if let rightStore, rightStore.count < 2 { _ = newTab(in: .right) }
        window?.contentView?.layoutSubtreeIfNeeded()
        defer {
            leftStore?.replaceAll(originalLeftTabs, activeAt: originalLeftActive)
            rightStore?.replaceAll(originalRightTabs, activeAt: originalRightActive)
            refreshTabStrip(side: .left)
            refreshTabStrip(side: .right)
            loadActiveTab(side: .left)
            loadActiveTab(side: .right)
        }

        // ① 常量（C2）
        check(FFInteractionPolicy.titleBandHeight == 36, "顶栏应为 36")
        check(FFInteractionPolicy.activeTabHeight == 30, "活动标签应为 30")
        check(FFInteractionPolicy.tabTopGap == 6, "上方空条应为 6")
        check(FFInteractionPolicy.inactiveTabHeight == 26, "非活动标签应为 26")
        check(FFInteractionPolicy.inactiveTabTopGap
              + FFInteractionPolicy.inactiveTabHeight
              + FFInteractionPolicy.inactiveTabBottomGap
              == FFInteractionPolicy.titleBandHeight,
              "非活动：8 上间隙 + 26 高 + 2 下空隙 应等于 36")
        // 内凹不能压进面板圆角
        check(FFInteractionPolicy.tabInsetFromPanel
              >= FFTabSilhouette.panelCorner + FFInteractionPolicy.tabSeamFillet,
              "标签左缘退让 \(FFInteractionPolicy.tabInsetFromPanel) 应 ≥ 面板圆角 16 + 内凹 10")

        // ② 活动标签几何：底边贴 0、顶边 = 带高 − 上间隙
        for (name, strip) in [("左", leftTabStrip), ("右", rightTabStrip)] {
            guard let strip, let tab = strip.activeTabFrame else { continue }
            check(abs(tab.minY) < 0.5, "\(name)标签底边应贴 0（实为 \(tab.minY)）")
            check(abs(tab.maxY - (strip.bounds.height - FFInteractionPolicy.tabTopGap)) < 0.5,
                  "\(name)标签顶边应 = \(strip.bounds.height - FFInteractionPolicy.tabTopGap)（实为 \(tab.maxY)）")
            check(tab.minX >= FFInteractionPolicy.tabInsetFromPanel,
                  "\(name)标签左缘应 ≥ 退让量（实为 \(tab.minX)）")
        }

        // ③ 非活动标签：在 38pt 栈内垂直居中，中心线与活动标签一致
        for (name, strip) in [("左", leftTabStrip), ("右", rightTabStrip)] {
            guard let strip, strip.subviews.count > 0 else { continue }
            let items = strip.allTabItems()
            guard items.count >= 2, let active = items.first(where: { $0.isActive }) else { continue }
            let inactive = items.filter { !$0.isActive }
            for item in inactive {
                let f = item.convert(item.bounds, to: strip)
                let a = active.convert(active.bounds, to: strip)
                check(abs(f.midY - a.midY) < 0.5, "\(name)非活动标签中心线应与活动对齐")
                check(abs(f.minY - FFInteractionPolicy.inactiveTabBottomGap) < 0.5,
                      "\(name)非活动标签底边应离面板 2（实为 \(f.minY)）")
                check(abs(f.maxY - (FFInteractionPolicy.titleBandHeight - FFInteractionPolicy.inactiveTabTopGap)) < 0.5,
                      "\(name)非活动标签顶边应留 2（实为 \(f.maxY)）")
            }
        }

        // ④ 不变量：发光收到的矩形 == 当前活动标签（换算到发光坐标系）
        if let strip = leftTabStrip, let glow = leftActiveBorder,
           let wrapper = leftPaneWrapper, let tab = strip.activeTabFrame {
            if let got = glow.tabRect {
                // C2：标签底边 = 顶栏底边 = 面板顶边（wrapper 顶部，y = wrapper 高度）
                check(abs(got.minY - glow.bounds.height) < 1,
                      "发光收到的标签底边应等于面板顶边（实为 \(got.minY) vs \(glow.bounds.height)）")
                // 标签向上高出面板一个活动标签高度
                check(abs(got.maxY - (glow.bounds.height + FFInteractionPolicy.activeTabHeight)) < 1,
                      "发光收到的标签顶边应高出面板 \(FFInteractionPolicy.activeTabHeight)（实为 \(got.maxY) vs \(glow.bounds.height + FFInteractionPolicy.activeTabHeight)）")
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
        let tab = NSRect(x: 36, y: panel.maxY, width: 120,
                         height: FFInteractionPolicy.activeTabHeight)
        let withTab = FFTabSilhouette.composite(panel: panel, tab: tab)
        let withoutTab = FFTabSilhouette.composite(panel: panel, tab: nil)
        check(withTab.bounds.height > withoutTab.bounds.height + 20,
              "有标签的轮廓应比无标签高出一个标签高度（\(withTab.bounds.height) vs \(withoutTab.bounds.height)）")

        // ⑥ A1 背板接线：背板必须可见、拿到活动标签矩形并填卡片色；
        // 活动标签自己不能再画背景，否则会盖住内凹肩线。
        for (name, strip) in [("左", leftTabStrip), ("右", rightTabStrip)] {
            guard let strip else { continue }
            guard let backdrop = strip.subviews.compactMap({ $0 as? PaneTabStripBackdrop }).first else {
                check(false, "\(name)标签条缺少焊接背板")
                continue
            }
            check(!backdrop.isHidden, "\(name)焊接背板应可见")
            check(backdrop.tabRect != nil, "\(name)焊接背板应拿到活动标签矩形")
            let alpha = backdrop.fillColor.usingColorSpace(.deviceRGB)?.alphaComponent ?? 0
            check(alpha > 0.9, "\(name)焊接背板应填不透明卡片色（alpha=\(alpha)）")
            let activeItem = strip.allTabItems().first(where: { $0.isActive })
            let tabAlpha = activeItem?.layer?.backgroundColor?.alpha ?? 0
            check(tabAlpha < 0.01, "\(name)活动标签不应自己画背景（alpha=\(tabAlpha)）")
            let contentCenter = strip.bounds.height - FFTopBarMetrics.centerline
            if let plus = strip.subviews.compactMap({ $0 as? FFHoverIconButton }).first {
                let plusRect = plus.alignmentRect(forFrame: plus.frame)
                let plusFrame = strip.convert(plusRect, from: plus.superview)
                check(abs(plusFrame.midY - contentCenter) < 0.5,
                      "\(name)＋中心应落在 18pt 中线（\(plusFrame.midY) vs \(contentCenter)）")
            }
            if let activeItem,
               let close = activeItem.subviews.compactMap({ $0 as? FFTabCloseButton }).first {
                let closeRect = close.alignmentRect(forFrame: close.frame)
                let closeFrame = strip.convert(closeRect, from: close.superview)
                check(abs(closeFrame.midY - contentCenter) < 0.5,
                      "\(name)关闭×中心应落在 18pt 中线（\(closeFrame.midY) vs \(contentCenter)）")
            }
        }

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
        // 用**默认宽度**算（用户手动调过的列宽会存盘，不该影响这条断言）
        let defaultWidths = Dictionary(uniqueKeysWithValues: all.map { ($0, $0.defaultWidth) })
        let narrow = FFListColumnsState.columnsFitting(in: 380, from: all, widths: defaultWidths)
        check(narrow.contains(.name), "名称列永不被收起")
        check(!narrow.contains(.comment), "窄面板应先收起说明列")
        let wide = FFListColumnsState.columnsFitting(in: 2000, from: all, widths: defaultWidths)
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
        if let list = leftFileListView {
            check(list.usesSharedRowMidline, "名称列图标与文字应共用行中线")
            check(list.visibleColumnIDs.contains(FFListColumn.size.rawValue)
                  || !FFListColumnsState.isVisible(.size),
                  "可见列与状态应一致")
        }

        // ⑧ 可选列真的能渲染出内容（用独立探针，不依赖当前目录里恰好有文件）
        let probe = FileListView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        let probeVM = PaneViewModel()
        probe.viewModel = probeVM
        probeVM.state.path = "/tmp"
        probeVM.state.files = [
            FileEntry(path: "/tmp/self-test.txt",
                      name: "self-test.txt",
                      isDirectory: false,
                      size: 1234,
                      modificationDate: Date(),
                      creationDate: Date())
        ]
        probe.reloadData()
        probe.layoutSubtreeIfNeeded()
        let kind = probe.debugCellText(for: .kind, row: 0) ?? ""
        let size = probe.debugCellText(for: .size, row: 0) ?? ""
        let modified = probe.debugCellText(for: .modified, row: 0) ?? ""
        let created = probe.debugCellText(for: .created, row: 0) ?? ""
        check(!kind.isEmpty, "类型列应有内容（实为「\(kind)」）")
        check(!size.isEmpty, "大小列应有内容")
        check(!modified.isEmpty, "修改日期列应有内容")
        check(!created.isEmpty, "创建日期列应有内容（可选列渲染路径）")

        FFDebug.log("[SHELL] 列表与外壳自检 通过\(pass) 失败\(fail)")
    }

    /// 操作区左半 / 右半各取一个窗口坐标点
    private func windowPointInOperationHalf(side: PaneSide) -> NSPoint {
        guard let cv = window?.contentView else { return NSPoint(x: 100, y: 100) }
        let sidebarRight = sidebarView.superview.map {
            cv.convert(sidebarView.frame, from: $0).maxX
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

