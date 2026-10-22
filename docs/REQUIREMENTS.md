# FlowFinder 需求基线

> **版本：** 2.1
> **日期：** 2026-10-22（按 R-19…R-22 当前代码校正）
> **性质：** 当前版本要做的事。按用户旅程组织，不按历史版本堆叠。
> **配套：** `PRODUCT.md` · `DESIGN-SPEC.md` · `ACCEPTANCE.md` · `REQUIREMENTS-LEDGER.md`
> **上一版：** 2.0（2026-10-17）。本版把已实现项改为 ✅/⚠️，未实现项保留为 backlog，并补入本轮新增能力。

---

## 1. 状态口径

| 状态 | 含义 |
|---|---|
| ✅ 已验证 | 代码存在且有自动化或真机证据 |
| ⚠️ 待验收 | 代码存在，缺少真机/人工验收 |
| 🔧 不符 | 有实现但与需求不一致 |
| ❌ 未实现 | 无实现 |

优先级：**P0** 阻断发布 · **P1** 本版应做 · **P2** 可延后。

---

## 2. J1 首次打开 → 看到自己的文件

| ID | 需求 | 优先级 | 状态 | 位置 / 差距 |
|---|---|---|---|---|
| J1-01 | Info.plist 用途声明（桌面/文稿/下载/外置卷/网络卷） | P0 | ✅ | `Resources/Info.plist` 5 条；终端入口已改 `NSWorkspace`，不再依赖 AppleEvents |
| J1-02 | 无权限时中文引导 +「打开系统设置」 | P0 | ✅ | `UI/FFPermissionGate.swift` |
| J1-03 | 默认收藏指向桌面/文稿/下载 | P1 | ✅ | `UI/SidebarFavoritesStore.swift` |
| J1-04 | 首次启动引导页（双栏用法 + 权限 + 快捷键） | P1 | ✅ | `UI/OnboardingWindowController.swift`；帮助菜单可重开 |
| J1-05 | ad-hoc 分发说明 | P1 | ✅ | README「下载与安装」；DMG 内说明未核 |
| J1-06 | 崩溃日志落盘 `~/Library/Logs/FlowFinder/` | P2 | ✅ | `UI/FFCrashLog.swift`；未捕获异常写入 `crash.log` |
| J1-07 | 记住上次打开的目录 | P2 | ✅ | `FFStartupPath`（左右路径 + 单/双栏 + 活动面板）；窗口尺寸不恢复 |

---

## 3. J2 双栏搬文件（差异化核心）

| ID | 需求 | 优先级 | 状态 | 位置 / 差距 |
|---|---|---|---|---|
| J2-01 | 双操作区，各自独立导航 | P0 | ✅ | `MainWindowController` + `PaneViewModel` |
| J2-02 | ⌘⇧C 复制到对侧 / ⌘⇧X 移动到对侧 | P0 | ✅ | `MainWindowController+MenuActions`；`FFBatch2IntegrationTests` 覆盖落地与删源 |
| J2-03 | 拖拽跨栏 | P0 | ✅ | 落点 resolver/集成测试；**物理拖拽手感未验** |
| J2-04 | 冲突三选：替换 / 保留两者 / 跳过 | P0 | ✅ | `ConflictResolver` + `FFDestructivePolicyTests` |
| J2-05 | 跨栏操作可撤销 | P1 | ✅ | `PaneState` 撤销栈 |
| J2-06 | 文件夹右键「在另一侧打开」 | P1 | ✅ | `menuOpenInOther`；集成测试覆盖 |
| J2-07 | 面板搜索范围可切：本栏 / 含子目录 / 双栏 | P1 | 🔧 | 仅当前栏递归；固定 3 层、上限 500（`FFSearchPolicy`），无范围 UI |
| J2-08 | 两栏同步导航（开关，默认关） | P2 | ❌ | 无 |
| J2-09 | 目录差异对比（仅左/仅右/大小不同） | P2 | ❌ | 无 |

---

## 4. J3 整理文件

| ID | 需求 | 优先级 | 状态 | 位置 / 差距 |
|---|---|---|---|---|
| J3-01 | 复制/剪切/粘贴/重命名/删除/新建文件夹 | P0 | ✅ | `PaneState`；新建文件夹在文件菜单/右键/⇧⌘N |
| J3-02 | 删除进废纸篓，可还原 | P0 | ✅ | `PaneState` + `DeleteConfirmDialog` |
| J3-03 | 撤销/重做闭环 | P0 | ✅ | `PaneState` + per-window UndoManager |
| J3-04 | 批量重命名（含路径安全校验） | P1 | ✅ | `BatchRenameWindowController` + Rust |
| J3-05 | 重复文件扫描（BLAKE3 三阶段，每组保留一个） | P1 | ✅ | Rust `dedup_engine` + `DuplicateScanWindowController` |
| J3-06 | 标签：新建/改色/筛选 | P1 | ✅ | `TagCatalog` + 侧栏 + `TagSelectorDialog` |
| J3-07 | 标签重命名 | P1 | ✅ | `TagCatalog` 改名并同步所有文件 |
| J3-08 | 标签与访达双向可见 | P1 | ✅ | 写入 `com.apple.metadata:_kMDItemUserTags` binary plist 数组；`FFBatch2IntegrationTests` 断言格式与读回 |
| J3-09 | 按类型自动打标签（规则引擎） | P2 | ⚠️ | Rust 规则引擎存在；工具页已隐藏 AI 入口，但注册表仍叫「AI 自动打标」 |
| J3-10 | 按日期/类型批量整理（预览 + 撤销） | P2 | ❌ | Rust FFI 已实现，Swift 无入口 |
| J3-11 | 文件说明写入 Finder 注释 | P2 | 🔧 | 仍存 `UserDefaults["fileDescriptions"]`，以绝对路径为 key，改名/移动后丢失 |

---

## 5. J4 全键盘操作

| ID | 需求 | 优先级 | 状态 | 位置 / 差距 |
|---|---|---|---|---|
| J4-01 | Tab 焦点流转（侧栏 → 左栏 → 右栏） | P1 | ✅ | keyViewLoop 含侧栏收藏、工具胶囊、工具行与左右面板 |
| J4-02 | ⌘F 聚焦当前面板搜索框 | P1 | ✅ | `menuSearch`；`FFBatch2IntegrationTests` 覆盖 |
| J4-03 | ⌥⌘C 拷贝路径 | P2 | ⚠️ | `menuCopyPaths` 存在，无自动化 |
| J4-04 | 文本编辑时 ⌘C/V/A/Z 不被文件操作劫持 | P0 | ✅ | `dispatchToTextEditing`；⌘C 隔离有测试 |
| J4-05 | 快捷键自定义真实生效 | P1 | ✅ | `FFShortcutSettings` + `MainMenu` |
| J4-06 | 空格 QuickLook、方向键切换、Esc 关闭 | P0 | ✅ | `MainWindowController` QL 预览；无自动化 |
| J4-07 | VoiceOver 标签、动态字体、reduced-motion | P1 | ⚠️ | AX 标签/对比度自动测试；完整 VoiceOver 走查待补；工具胶囊/工具行已补 AX |

---

## 6. J5 出错能自救

| ID | 需求 | 优先级 | 状态 | 位置 / 差距 |
|---|---|---|---|---|
| J5-01 | 无权限：中文说明 +「打开系统设置」 | P0 | ✅ | `FFPermissionGate` |
| J5-02 | 只读卷：说明原因 + 建议 | P1 | ✅ | `FFErrorText` 已覆盖只读/空间不足/权限等；`FFErrorTextTests` |
| J5-03 | 断线：说明 + 重连 | P1 | ✅ | SMBBridge 健康检查/退避重连 + 底部状态条「重试」；真实断线未触发 |
| J5-04 | 错误可重试 | P1 | ✅ | 状态描述符 + 重试测试 |
| J5-05 | 空目录有说明，不白屏 | P1 | ✅ | `FFPaneStateDescriptor` 空态覆盖层 |

---

## 7. 横切：视觉与主题

| ID | 需求 | 优先级 | 状态 | 当前值 |
|---|---|---|---|---|
| C-01 | 单一字体令牌来源 | P1 | 🔧 | `FFDesign.Text` 与 `FFVisualTokens.Font` 并存；硬编码 `systemFont` 122 处（静态棘轮） |
| C-02 | 主题三态（浅/深/跟随系统），即时生效 | P0 | ✅ | `ThemeManager` |
| C-03 | 圆角令牌 | P1 | ✅ | 控件 6 / 卡片 8 / 详情 12 / 面板 12 / 窗口 12 |
| C-04 | 材质：窗口+侧栏亚克力，操作区实体 | P1 | ✅ | `FFGlassView` / `FFSolidSurfaceView` |
| C-05 | 工具栏双行 72pt（冻结） | P1 | ✅ | Row1/Row2 各 32 + 间距 |
| C-06 | 详情栏浮层 + 底部留白 | P1 | ✅ | 收起 54 / 展开 132–300 / 预览列 96–200 |
| C-07 | 面包屑溢出保留当前目录 | P1 | ✅ | `BreadcrumbBar` |
| C-08 | 侧栏宽度可拖并记忆 | P2 | ✅ | 默认 220，范围 180–280 |

---

## 8. 横切：非功能

| ID | 需求 | 指标 | 状态 |
|---|---|---|---|
| N-01 | 冷启动 | 可交互 < 2s | ⚠️ 未测 |
| N-02 | 目录冷读 | < 1.0ms | ✅ |
| N-03 | 大目录滚动 | 10,000 项 ≥ 55fps | ⚠️ 未测 |
| N-04 | 常驻内存 | < 250MB | ⚠️ 未测 |
| N-05 | 零约束冲突 | 0 条 | ✅ |
| N-06 | 测试基线 | Rust 200 / Swift 389 / 自检 163 | ✅ |
| N-07 | 编译警告 | 0 | ⚠️ 未复测（历史 52） |

---

## 9. 本轮新增能力（R-19…R-22）

| 能力 | 说明 | 证据 |
|---|---|---|
| 全局顶栏 | 36pt；标签 30/26；红绿灯与内容共用 18pt 中线 | `FFTopBarMetrics`、`FFShellLayoutTests`、真机 17.5pt 实测 |
| 工具页 | 品牌旁「工具」胶囊 → 侧栏页；5 个工具/三组；无路径与选中 | `FFToolPage.swift`、`FFToolPageTests`、真机截图 |
| 第二行显示设置 | 眼睛按钮合并显示项/列/第二行；移除新建文件夹与齿轮 | `PaneToolbar.makeDisplaySettingsMenu` |
| 版本规则 | `A.B.C-yymmddxx`，每次迭代构建递增 | `scripts/bump-version.sh`、`FFBuildInfo` |
| 设置接线 | 移动前确认、默认操作行为三选、文件夹优先、刷新保持选中、更新检查、SMB 域/重连 | `FFAppSettings`、`FFBatch2IntegrationTests` |
| 更新检查 | GitHub Releases + 完整版本戳比较；提示去下载 | `FFUpdateChecker` |
| 无障碍 | 工具胶囊/工具行 AX 与 Tab/Enter/Space | `FFToolPageAccessibilityTests` |
| 首次引导 | 独立欢迎窗口：双栏图示、权限状态、三快捷键；帮助菜单可重开 | `OnboardingWindowController`、`FFBatch4Tests` |
| 崩溃日志 | 未捕获异常写入 `~/Library/Logs/FlowFinder/crash.log` | `FFCrashLog`、`FFBatch4Tests` |

---

## 10. 明确实现与宣称不符的项

| # | 原宣称 | 实况 | 处置 |
|---|---|---|---|
| 1 | README「正则搜索」 | 全文已无此表述 | 已修 |
| 2 | README「流式推送」 | 扫描/批量操作有进度回调，但不是逐条流式 | 文案保留「实时进度」，不写流式 |
| 3 | README「玻璃态双栏」 | 操作区实体，仅侧栏亚克力 | 已修 |
| 4 | 「AI 智能打标」 | 扩展名规则引擎 | 工具页已隐藏；注册表命名待改 |
| 5 | 任务中心「暂停/恢复/优先级」 | 实际：复制/移动/删除/查重/批量重命名任务汇总，支持取消/重试/清除；Rust `ff_task_submit` 未接 | README 已按实际改写 |
| 6 | 7 个设置项只写不读 | 9 项全部接线 | 已修（R-21） |
| 7 | SMB 记住密码/自动重连未使用 | 自动连接持久化 + 启动重连 + 状态提示 | 已修（R-21） |
| 8 | 版本号 0.7.9/7901 | `0.8.0-26102204` | 已修 |

---

## 11. 变更控制

1. 新增或修改需求：先改本文件，注明优先级与理由，再动代码。
2. 推翻既有决策：在提交信息写明覆盖条数与理由，并在 SPEC 登记。
3. 标 ✅ 必须有实现位置与验收证据；给不出的标 ⚠️ 或 🔧。
4. 视觉类改动指向 `DESIGN-SPEC.md` 令牌表，禁止整体重设计。
5. 提交前自检是否触碰 `PRODUCT.md` 的「明确不做 / 不追求」。
