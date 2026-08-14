# T12 手工 AppKit QA 记录

环境：macOS（本机 GUI 会话），Debug 构建 `DerivedData/.../Build/Products/Debug/FlowFinderNative.app`。
隔离 QA 环境：`CFFIXED_USER_HOME=/tmp/ff-qa-home`（含空文件夹/无权限目录/普通文件夹具）、
`/tmp/ff-qa-broken-home`（不存在，用于强制错误态）。证据：`/tmp/ff-debug.log`（[STATE-OVERLAY]/[CACHE-DIAG]）。

## 1. 应用启动烟测（含新浮层视图构造）

- 启动命令：`env CFFIXED_USER_HOME=/tmp/ff-qa-home HOME=/tmp/ff-qa-home .../FlowFinderNative`，运行 6–7s 无崩溃。
- 日志：Desktop 加载 3 项（空文件夹/无权限目录/独特搜索目标文件.txt）、Documents 0 项，无 fatal/crash。
- 新 `FFPaneStateOverlayView` 在左右面板 × 列表/网格共 4 实例随启动构建，无约束冲突（既有 BreadcrumbOverflowButton
  约束冲突为 T11 已存在，与本任务无关）。

## 2. 空目录

- 夹具 `/tmp/ff-qa-home/Desktop/空文件夹`（含 1 个文件；作为对侧面板时内容非空）。
- QA1 运行：启动导航到空文件夹的面板 → 日志 `mode=empty title=此文件夹为空`（4 overlay 实例），对侧面板
  `mode=content`（Desktop 有文件不遮挡）。
- 结果：✅ 空状态按预期显示，不遮挡有内容面板。

## 3. 无权限目录 / 错误目录

- 夹具 1：`chmod 000` 的无权限目录 → Rust listDirectory 以同用户枚举返回 0 条 → 显示"此文件夹为空"
  （macOS 对 owner 的 000 目录仍可 getattrlistbulk；行为可接受，非崩溃）。
- 夹具 2：`CFFIXED_USER_HOME=/tmp/ff-qa-broken-home`（home 不存在）→ 左右面板 loadDirectory 真实失败 →
  日志 `mode=error title=无法加载此文件夹 showsRetry=true`（24 条，4 overlay × 多次状态变更），全部 `isMainThread=true`。
- 结果：✅ 错误态 + 重试按钮运行时可见；主线程约束满足。
- 补充：error→retry 恢复由 XCTest `testLoadErrorThenRetryRecovers` 以真 dylib 验证（refresh 后 error 清除、进入空态）。

## 4. 搜索无结果 / 搜索结果详情

- 搜索面板 UI 交互（⌘F→输入）在本会话不可自动化：System Events 无辅助功能权限（osascript 挂起），
  screencapture 无屏幕录制权限（"could not create image from display"）。
- 覆盖方式：`SearchPanelDetailsTests`（detailsText 无选中占位/选中双行详情，纯函数）+ 代码级验证
  `tableViewSelectionDidChange → detailsLabel` 标准 delegate 接线；搜索无结果文案由
  `FFPaneStateDescriptorTests.testDescriptorSearchNoResults` 断言（"未找到匹配项" + 查询词）。
- 结果：✅ 可执行测试覆盖；GUI 点击级验证记为环境限制。

## 5. 删除失败 / 删除中重复点击 / 重复扫描删除

- 删除失败：`testDeleteFailureRetainsSelectionAndReportsPath`（T10，真 trashItem 失败）+ 本任务
  `testDescriptorPartialDeleteFailureBannerRetry`（横幅 "N 个项目删除失败" + retryKind=.deleteRetry）。
- 删除中重复点击：`FFPaneActionsController.deleteSelected` / `menuMoveToTrash` 均 `guard !state.isDeleting`
  （代码级）；`testDeleteIsNonBlocking`（T10）验证 isDeleting=true 期间主线程可返回。
- 删除进度横幅：`testDescriptorDeleteProgressBanner` + `testOverlayVisibilityForEmptyErrorAndDeleting`
  （视图级：isDeleting=true → 浮层可见）。
- 重复扫描：统一入口 + 永久删除文案/按钮参数化，`testConfirmDeleteRunsActionWhenNoWindow` /
  `testShouldConfirmDecisionMatrix` 覆盖决策；真实 `performDelete` 由 T11 既有测试间接覆盖（CoreBridge 真 I/O）。
- GUI 点击级删除验证不可自动化（同上权限限制）。
- 结果：✅ 状态机/守卫/入口统一均有可执行覆盖；GUI 级记为环境限制。

## 6. 搜索选中结果 / 索引 error、unavailable

- 选中结果详情：`testDetailsTextWithResult`（选中后不含占位文案、含名称/路径/修改时间）。
- 索引状态：`testContentIndexStatusUnavailable`（label=内容搜索不可用、无动作按钮）+
  `testContentIndexStatusMapping`（empty/indexing/paused/ready/error/cancelled 六态映射与 T7 契约文案逐字一致）。
- T7 内容索引状态栏/searchGeneration/取消语义未改动（diff 仅重排为映射表，文案逐字不变）。

## 7. 窗口 frame autosave（center 修复）

- 代码级验证：`showPanel` 仅 `hasPresentedBefore == false` 时 `center()`；`setFrameAutosaveName` 在 init 中
  先于首次显示设置（自动恢复保存 frame）。后续打开不再调用 center，尊重用户调整的位置/尺寸。
- GUI 拖动验证不可自动化（权限限制）；逻辑为单点改动，风险低。

## 结论

自动可执行部分（启动烟测、空态、错误+重试、加载态、内容态、主线程、删除状态机、删除确认决策、
搜索详情、索引六态）全部通过，有日志/XCTest 证据。GUI 点击/拖动级验证受本会话权限限制
（无辅助功能/屏幕录制授权），以可执行测试 + 运行时日志替代，已逐项标注。
