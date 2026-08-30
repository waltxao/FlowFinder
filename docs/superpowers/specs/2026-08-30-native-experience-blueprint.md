# FlowFinder 原生体验重设计蓝图（B2）

> **日期：** 2026-08-30
> **性质：** 全应用 UI/UX + 代码审计的修复蓝图（用户授权全程自主执行）
> **审计输入：** `.superpowers/audit/{async-performance, menu-shortcuts-focus, materials-toolbar-visual, drag-gestures-scroll}.md`（四路只读代码审计，全部含 file:line 证据）
> **执行方式：** 分 4 个波次，每波独立 spec→计划→子代理实现→独立审查→全量测试。**Wave 5（NSToolbar 大改造）经审计评估为「双窗格架构冲突、量级大」，本蓝图决策：缓行**（仅做 Wave 4 中的 overflow 小改），理由与替代方案记录于 §6。

## 0. 审计结论汇总

| 审计域 | P0 | P1 | P2 | 代表问题 |
|--------|----|----|----|----------|
| 异步/性能 | 3 | 3 | 4 | fsevents 同步握手最坏冻结 10s；新建文件夹同步移动分钟级冻结；listVolumes 同步 df 网络卷秒级；渲染逐条 xattr；FSEvents 风暴无去抖 |
| 菜单/快捷键/焦点 | 4 | 5 | 3 | Tab 焦点流转完全缺失；⌘C/X/V 不写系统剪贴板；快捷键自定义半成品；4 处死菜单；⌘F 不聚焦面板搜索 |
| 拖拽/手势 | 3 | 2 | 1 | 无 Drop 目标高亮；无 Spring Loading；⌘C 剪贴板不与 Finder 互通；网格拖入不支持文件夹；无轻扫/捏合 |
| 材质/工具栏/视觉 | — | — | — | 实体区叠玻璃材质冲突；双阴影/圆角四档不统一；灰度三套硬编码；无密度切换；无 NSToolbar |

## 1. Wave 1 — 主线程卡顿根治（P0 性能）

**目标：** 常规操作（切目录、新建文件夹、浏览侧边栏）在本地盘零 >100ms 主线程任务；网络盘不再出现秒级冻结。

| # | 项 | 审计依据 | 改法 |
|---|----|----------|------|
| 1.1 | `ff_fsevents_start` 异步化 | async P0-1（CoreBridge.swift:763-796, MainWindowController.swift:309） | `startFSEventsWatcher` 改 completion 回调（active/failed），删主线程 semaphore；状态查询去 `ffiQueue.sync`（回调缓存原子值）；watcher 重启路径内部 stop+join 移后台；handleFileSystemChange 对非 active 状态缓冲（pendingPaths 合帧处理） |
| 1.2 | 新建文件夹（用所选项目）后台化 | async P0-2（PaneState.swift:743-782） | createDirectory+parallelMove 整体移 `DispatchQueue.global`；parallelMove 接 progress 回调 → TaskProgressBar；完成/失败回主线程刷新+错误弹窗；保留撤销注册语义 |
| 1.3 | loadDevices 后台化 | async P0-3（SidebarView.swift:1092, volumes.rs:155/313） | 移 `DispatchQueue.global`，主线程回调刷新设备浮层；TTL 缓存保留 |

**验收：** ①大文件"用所选项目新建文件夹"期间 UI 可交互且进度条可见；②侧边栏设备列表在挂载失联网络卷时不冻结界面；③启动路径无主线程同步等待 fsevents（代码审查 + 手动验证）。

## 2. Wave 2 — 键盘优先工作流 + Finder 互通（P0）

**目标：** 全键盘可用性达到 Finder 水准；剪贴板与系统互通。

| # | 项 | 审计依据 | 改法 |
|---|----|----------|------|
| 2.1 | keyViewLoop + Tab 流转 | menu 审计 P0-1 | 列表/网格/搜索框/排序/分组/另一面板建立 nextKeyView 环；⇧⌘←/→ 或 Tab 跨面板 |
| 2.2 | 剪贴板互通 | menu P0-2 + drag P0-3 | menuCopy/Cut 写 `NSPasteboard.general`（.fileURL + 内部类型双写）；粘贴优先读 general 的 fileURL，回退内部 clipboardItems；Finder 拖入/粘贴互通 |
| 2.3 | 文本编辑分流 | menu P0-2 | 文本框 firstResponder 时 ⌘C/X/V/A/Z 走标准 `copy:`/`paste:` selector，不再被文件操作劫持 |
| 2.4 | 快捷键自定义生效化 | menu P0-3 | QuickLook/⌘D 读设置消费；⌘1/⌘2/⌘O/⌘↑↓/Enter/Del/Space 硬编码改读设置（带默认值回退）；设置页补"恢复默认" |
| 2.5 | 死菜单修复 | menu P0-4 | ⌘⇧N 实现新窗口（或暂移除+记录）；显示隐藏文件接通 menuToggleHiddenFiles→真实状态翻转；帮助项接 About/仓库 |
| 2.6 | 高频补缺 | menu P1 | ⌥⌘C 拷贝路径（右键+编辑菜单）；⌘F 聚焦面板搜索框；F2/Enter 统一内联重命名；⌘D 菜单入口；QL Space 关闭；activatePane 与 firstResponder 统一真值源 |

**验收：** 全键盘完成"启动→切面板→搜索过滤→打开→重命名→复制到 Finder"全流程；⌘C 后可在 Finder 粘贴；设置改 Space 键位后立即生效。

## 3. Wave 3 — 交互反馈补全（拖拽/手势/进度）

| # | 项 | 审计依据 | 改法 |
|---|----|----------|------|
| 3.1 | Drop 目标高亮 | drag P0-1 | 列表 draggingUpdated 高亮文件夹行（accent 描边/底色），draggingExited 复位；网格高亮目标 item + 空白区=当前目录 |
| 3.2 | Spring Loading | drag P0-2 | 驻留 1s 自动展开悬停文件夹（自实现计时，兼容两视图） |
| 3.3 | 拖拽复制/移动进度 | async 缺口 | parallelMove/Copy 接 TaskProgressBar（与粘贴路径一致） |
| 3.4 | 网格拖入文件夹 | drag §1.2 | draggingUpdated 识别文件夹 item，acceptDrop 移入 |
| 3.5 | 轻扫前进后退 | drag P1 | 面板容器 swipeWithEvent → goBack/goForward |
| 3.6 | FSEvents 风暴合帧 | async P1-5 | 0.3s 合帧（目录去重 Set + Timer flush），invalidateCache 批量化 |
| 3.7 | tags 批量预热 | async P1-4 | loadDirectory 后台批量预读 xattr 进 TagBridge 缓存 |

**验收：** 拖拽悬停文件夹有高亮且 1s 自动展开；拖拽复制大文件有进度条；同步风暴期间界面不刷屏。

## 4. Wave 4 — 视觉材质与密度（对照截图审查细化）

| # | 项 | 审计依据 | 改法 |
|---|----|----------|------|
| 4.1 | 材质去冲突 | 材质 §1.1 | 工具栏/搜索框去玻璃改实体（与操作区同色系灰度），详情栏保留玻璃浮层 |
| 4.2 | 阴影/圆角收敛 | 材质 §1.3 | 详情栏删 MWC 侧双阴影；圆角收敛 16/10 两档 |
| 4.3 | 颜色令牌统一 | 材质 §1.2 | operationArea 色下沉 FFDesign 令牌，三套硬编码归一 |
| 4.4 | 密度三档 | 材质 §4 | 列表 紧凑22/标准26/宽松32 + 设置页选项；网格 ⌘滚轮/捏合缩放 itemSize（状态驱动+invalidateLayout） |
| 4.5 | 字体令牌 | 材质 §3 | FFDesign.Typography（caption10/body11/emphasis11sb/title13sb）+ 详情栏 10→11pt、44pt 标签改 ≥44 弹性 |
| 4.6 | 工具栏 overflow | 材质 §2 折中 | Row2 控件 compression priority 分级 + 溢出并入菜单按钮 |
| 4.7 | 装饰降噪 | 材质 §3 | 删操作区 1px 边框；FFGlassView 三层装饰在实体背景上降级 |

**验收：** 截图对比（深浅色 × 主窗/子窗）确认材质层次与一致性；缩窄窗口工具栏不破版；密度切换即时生效。

## 5. 横切约束（所有波次）

- 简体中文注释；不新增文件（除非波次明确要求）；pbxproj 不碰。
- 每项改动后 `make swift-test`（落盘判读）；波次完成跑 `make clean && make rust && make test` 清洁基线并恢复被 clean 误删的跟踪文件。
- Rust 改动需 `make rust-test` 全绿。
- 测试宿主不建应用 UI（既有守卫）；测试不用 NSWindow 承载视图（既有约定）。
- 每波交付物：代码提交 + 审查通过 + 验收项核验 + 本文件对应条目勾选。

## 6. 决策记录

1. **NSToolbar 整合红绿灯：缓行。** 审计确认 macOS 单窗口单工具栏与本项目"每窗格一条工具栏"的双窗格架构冲突，且 `.fullSizeContentView` 透明标题栏布局将被打断。折中：Wave 4.6 先解决 overflow；NSToolbar 作为独立大改造在未来单列评估。
2. **文件 promise（NSFilePromiseProvider）**：本地文件管理器场景收益低，列入未来清单（drag 审计 P2）。
3. **截图审查**：屏幕锁定期间受阻，解锁后补做并回填 Wave 4 的视觉细节。
