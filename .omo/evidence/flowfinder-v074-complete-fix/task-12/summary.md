# Wave4 T12 — 统一 AppKit 状态视图 / 破坏性删除 UX / 搜索结果详情

状态：**完成**。`xcodebuild test -scheme FlowFinderNativeTests` 全绿（**65 tests, 0 failures**；T11 基线 43 + 本任务新增 22）。

## 1. 改动文件清单

| 文件 | 改动 |
|---|---|
| `UI/FFCommon.swift` | +~380 行：`FFPaneOverlayMode` / `FFPaneRetryKind` / `FFPaneStateDescriptor`（纯函数状态机）/ `FFPaneStateOverlayView`（全屏 loading/empty/error + 顶部横幅 operation）；`FFUserDefaultsKeys.deleteConfirmDisabled` |
| `UI/FileListView.swift` | +12 行：`stateOverlayView` 属性 + setupUI 叠加 + viewModel didSet 绑定 |
| `UI/FileGridView.swift` | +12 行：同上（对称接入） |
| `UI/DeleteConfirmDialog.swift` | 参数化（message/confirmButtonTitle）+ `shouldConfirm` 纯决策函数 + 统一 `confirmDelete` 静态入口 |
| `UI/FFPaneActionsController.swift` | `deleteSelected` 删除第二套 NSAlert 确认 → 统一入口；+ isDeleting 守卫 |
| `UI/MainWindowController.swift` | `menuMoveToTrash` → 统一入口；+ isDeleting 守卫 |
| `UI/DuplicateScanWindowController.swift` | `deleteSelected` → 统一入口（业务差异 message/按钮标题经参数传入） |
| `UI/SearchPanelController.swift` | detailsLabel 提为属性 + `tableViewSelectionDidChange` 更新；`showPanel` center() 仅首次；`detailsText` / `contentIndexStatusDescriptor` 抽纯函数；`updateContentIndexStatusUI` 走映射表（文案逐字不变） |
| `Tests/.../PaneStateDeleteFilterTests.swift` | +22 测试（4 个新测试类，扩展进 T11 已挂 target 的既有文件） |

未改（范围禁止）：`rust-core/**`、`FFIFunctions.swift`、`ContentIndexBridge.swift`、`project.pbxproj`、`PaneState.swift`、`Package.swift`。

**pbxproj 冻结说明**：任务禁止改 pbxproj 且 app/test target 均为显式文件引用（非 filesystem-synchronized），
故「新状态视图」按任务允许的「或现有合适文件」放入已在 target 的 `FFCommon.swift`；新测试
按「扩展 XCTest」放入已挂入 target 的 `PaneStateDeleteFilterTests.swift`（文件内多类）。零 pbxproj 改动。

## 2. 状态流（由 PaneState 真值驱动，无业务状态复制）

`FFPaneStateDescriptor.make(from: PaneState)` 纯函数，优先级：**删除中 > 错误 > 加载 > 空 > 内容**：

| PaneState 真值 | 呈现 |
|---|---|
| `isDeleting == true` | 顶部横幅（转圈 + "正在删除 N 个项目…"），**不遮挡列表** |
| `error != nil && files.isEmpty` | 全屏错误 "无法加载此文件夹" + 副消息 + 重试 |
| `error != nil && files 非空`（删除部分失败） | 顶部横幅 "N 个项目删除失败" + 重试（retryKind=.deleteRetry，失败项仍在选中集） |
| `isLoading && files.isEmpty` | 全屏 "正在加载…"（转圈）；有内容时刷新不遮挡 |
| `files.isEmpty` | 四分类：无 path→"打开一个文件夹" / searchQuery→"未找到匹配项" / tagFilter→"没有符合所选标签的项目" / 其余→"此文件夹为空" |
| 其余 | content（浮层隐藏） |

- 重试语义：`.reload`→`refresh()`；`.deleteRetry`→`deleteSelected()`（重删失败项）。
- 视图由 `viewModel.$state.receive(on: .main)` 订阅，**所有状态更新在主线程**（运行时日志 `isMainThread=true` 已验证）。
- 浮层为独立叠加层（约束钉在宿主边），不参与 scrollView/列表布局；`hitTest` 仅保留重试按钮与横幅交互，其余穿透（保留空目录右键新建文件夹）。
- 删除中重复触发：`FFPaneActionsController.deleteSelected` 与 `menuMoveToTrash` 均 `guard !state.isDeleting`。

## 3. 删除入口统一方式

全应用仅一个确认实现 `DeleteConfirmDialog.confirmDelete(fileCount:window:message:confirmButtonTitle:action:)`：

- 纯决策 `shouldConfirm`：fileCount==0 / `delete_confirm_disabled` 已勾选 / 无宿主窗口 → 直接执行；否则 `DeleteConfirmDialog` sheet。
- "不再询问" 写入统一 key `FFUserDefaultsKeys.deleteConfirmDisabled`（FFCommon 集中管理），三个入口语义一致。
- 业务差异经参数传入：重复扫描 `message: "确定要永久删除 N 个重复文件吗？此操作无法撤销。"`、`confirmButtonTitle: "永久删除"`（其 `performDelete` 为 Rust 永久删除，非废纸篓）。
- 原 `FFPaneActionsController` 的 NSAlert 确认（第二套流程）已删除。

## 4. SearchPanel

- `detailsLabel` 提为属性；`tableViewSelectionDidChange` → `detailsText(for:)`（nil→占位；选中→"名称 · 大小 · 修改于 …\n路径"双行），不再有静态死文案。
- `showPanel` 的 `window.center()` 仅首次（`hasPresentedBefore` 标志）；之后尊重 `setFrameAutosaveName` 恢复的用户 frame。
- T7 内容索引状态栏、searchGeneration、取消语义全部保留；状态映射抽为 `contentIndexStatusDescriptor` 纯函数，文案逐字不变（含 unavailable）。

## 5. 测试（65 = T11 43 + 本任务 22）

| 类 | 测试 | 依赖 dylib |
|---|---|---|
| FFPaneStateDescriptorTests | 9：首启/空目录/搜索无结果/标签空/加载/全屏错误重试/删除进度横幅/部分失败横幅 deleteRetry/有内容不遮挡 | 否 |
| PaneStateFlowTests | 3：loading→ready（真 dylib listDirectory）、空目录、error→retry（refresh 恢复） | 是 |
| DeleteConfirmFlowTests | 4：决策矩阵、无窗口直接执行、勾选"不再询问"跳过、0 条直接执行 | 否 |
| SearchPanelDetailsTests | 4：detailsText 占位/选中、索引映射全 6 态（含 unavailable） | 否 |
| FFPaneStateOverlayViewTests | 2：浮层可见性随真值流（无路径→loading→content；空→错误→删除中） | 是 |

环境约束（已注释在测试内）：`FileManager.default.temporaryDirectory`（/var/folders）在 XCTest harness 下
被 libRPAC 拦截，Rust getattrlistbulk 静默返回 0 条 → 真流测试改用 `/tmp`。

## 6. 验证

```text
$ DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
    -project FlowFinderNative.xcodeproj -scheme FlowFinderNativeTests \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
=> ** TEST SUCCEEDED **  65 tests, 0 failures
```

运行时状态流证据（`/tmp/ff-debug.log`，[STATE-OVERLAY] 标记，全部 `isMainThread=true`）：

```text
mode=empty  title=打开一个文件夹        # 首启（4 个 overlay：左右面板 × 列表/网格）
mode=loading title=正在加载…            # 启动位置导航
mode=empty  title=此文件夹为空          # 空目录导航
mode=error  title=无法加载此文件夹 showsRetry=true   # 错误目录（运行时真实 listDirectory 失败）
mode=content                           # 有内容时隐藏
```

手工 QA 见 `manual-qa.md`。

## 7. 约束遵守

| 约束 | 遵守 |
|---|---|
| 状态 UI 由 PaneState 真值驱动 | ✅（descriptor 纯函数，无副本状态） |
| 删除确认仅一个实现 | ✅（confirmDelete 唯一入口；NSAlert 第二套已删） |
| "不再询问"全入口一致 | ✅（统一 key + 统一入口） |
| 异步完成回调主线程 | ✅（overlay 订阅 receive(on: .main)；运行时 isMainThread=true） |
| 空/错误/加载/搜索无结果文案可区分 | ✅（四分类 + 描述符测试断言文案） |
| 不改 rust-core/FFI/ContentIndexBridge/pbxproj | ✅（零改动；测试扩展进既有文件） |
| 不做 T13 全面 a11y / T14 拆分 | ✅（未触碰） |
| 无失败静默 | ✅（删除失败横幅 + 错误保留，无 silent failure） |
| 无第三方依赖 / SwiftUI | ✅ |
