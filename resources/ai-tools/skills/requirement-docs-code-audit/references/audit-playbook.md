# 审计操作手册

本文件把 SKILL.md 的六步流程落成可复制命令和判定细则。所有命令默认只读；不要在没有用户确认时执行构建、测试、清理或修改。

## 0. 约定

```bash
REPO=/Volumes/Iris-Data/文件管理系统/flowfinder-native
SWIFT=$REPO/FlowFinder/FlowFinder
TESTS=$REPO/FlowFinder/Tests/FlowFinderTests
RUST=$REPO/rust-core
DOCS=$REPO/docs
```

- 优先用 `rg`；没有 `rg` 时用 `grep -RIn`。
- 命令输出要记录日期、commit、命中数和文件位置。
- 命中数不是结论。一个符号被搜索到，只说明它出现过，不说明它被使用。
- 路径示例按 FlowFinder 当前布局编写；换项目时替换变量，不要照搬目录名。

## 1. 文档基线

### 1.1 读文档的顺序

| 顺序 | 文档 | 主要提取 | 常见陷阱 |
|---|---|---|---|
| 1 | PRODUCT / 产品定位 | 范围、明确不做、目标用户 | 把旧愿景当当前承诺 |
| 2 | REQUIREMENTS | 旅程、ID、优先级、状态口径 | 状态列可能整列过期 |
| 3 | ACCEPTANCE | 可执行的通过条件、验收数值 | 数值可能已被后续 SPEC 推翻 |
| 4 | REQUIREMENTS-LEDGER | R-xx、证据等级、当前测试基线、未验项 | 条目多，容易只看最新一条 |
| 5 | HANDOVER | 版本、分支、命令、已知债、未验项 | 顶部数字可能未随本轮重算 |
| 6 | 最新 SPEC / PLAN | 已确认决策、未完成阶段 | 计划勾选不等于代码完成 |

### 1.2 快速盘点

```bash
find "$DOCS" -maxdepth 1 -name '*.md' -print | sort
rg -n '^#{1,4} |\b[A-Z]{1,2}-[0-9]{2}\b' \
  "$DOCS/REQUIREMENTS.md" "$DOCS/ACCEPTANCE.md" "$DOCS/REQUIREMENTS-LEDGER.md"
```

先人工读一遍标题和状态口径，再决定用哪些正则。不要只用正则生成清单，表格里的多行需求、合并单元格和“同上”会漏。

### 1.3 必须记录的基线

- 文档版本与日期。
- 状态词表：例如 `已完成 / 部分完成 / 未开始 / 已废弃`，或 `✅ / ⚠️ / 🔧 / ❌`。
- 当前测试数字及其来源（台账、交接、本轮命令）。
- 当前版本号与构建号。
- 文档之间的冲突：同一需求两份文档状态不同、验收数值不同、入口名称不同。
- 工作区是否有未提交改动。

冲突先写进报告，不要先替用户裁决。裁决会改变审计结论，属于下一步动作。

## 2. 需求 ID 清单

### 2.1 收集范围

至少收集四类 ID：

- 需求旅程：`J1`–`J5`
- 横切需求：`C-xx`、`N-xx`
- 验收项：`L-xx`、`T-xx`、`V-xx`、`D-xx`、`O-xx`、`S-xx`、`F-xx`、`K-xx`
- 台账条目：`R-xx`

`D-xx` 可能同时表示“验收详情项”和“设计决策”，必须结合来源文档判断，不能按编号合并。

### 2.2 清单字段

| 字段 | 要求 |
|---|---|
| ID | 保留来源前缀，不重新编号 |
| 来源 | 文件 + 行号 |
| 需求原文 | 尽量原文，不改写成自己的话 |
| 优先级 | P0/P1/P2，缺失时标“未标” |
| 文档声称状态 | 原样记录，不先修正 |
| 声称位置 | 文件:行号或“无” |
| 所属旅程 | J1–J5 或横切 |
| 关联验收项 | 有则列，无则写“无” |
| 备注 | 冲突、重复、歧义 |

### 2.3 完整性检查

- 需求文档中的每个 J/C/N 是否都能在验收或台账找到落点？
- 验收文档中的每个 ID 是否都能回到需求？
- 台账是否有 R-xx 没有对应需求，或需求没有 R-xx？
- 是否有同一 ID 在两处写了不同状态或不同实现位置？
- 是否有“阶段 C”“后续做”“待定”但没有归属的悬空项？

报告中的“分母”用清单总数，不用测试总数。测试总数是另一条基线。

## 3. 代码证据

### 3.1 位置与符号

先确认文档写的文件、类型、函数在当前 commit 是否存在：

```bash
rg -n 'class FFPillButton|struct TagCatalog|enum FFToolRegistry' "$SWIFT" --glob '*.swift'
rg -n 'fn ff_organize_by_date|fn ff_task_submit' "$RUST" --glob '*.rs'
```

通过条件：

- 能找到符号。
- 行号可以因后续改动偏移，但不能指向无关代码。
- 文档只写“某文件”时，至少定位到具体类型或函数。

### 3.2 生产调用方

对关键符号统计“定义之外”的调用：

```bash
rg -n '\bff_organize_by_date\b' "$SWIFT" \
  --glob '*.swift' \
  --glob '!**/Tests/**' \
  --glob '!**/Bridge/FFIFunctions.swift'
```

```bash
rg -n '\bTagCatalog\b' "$SWIFT" \
  --glob '*.swift' \
  --glob '!**/Tests/**'
```

通过条件：

- 排除声明、协议要求、测试、注释和文档后，仍有生产调用。
- 调用发生在用户操作或数据流的真实路径上，不是只在初始化时注册但从不触发。
- 若只有测试调用，结论是“有测试、无生产调用”，不是“已接线”。

常见假阳性：

- 同名类型或函数在不同模块重复。
- 注释、字符串、日志里出现符号名。
- 测试 helper 里调用。
- 只在 SwiftUI Preview 或调试入口调用。

### 3.3 用户可达路径

从入口追到动作，至少追一条完整链路：

| 入口类型 | 要找的证据 |
|---|---|
| 菜单 | `NSMenuItem`、`target`、`action`、`keyEquivalent`、菜单构建函数 |
| 按钮 | `addTarget`、closure、`onClick`、`mouseUp`、`performClick` |
| 工具栏 | 按钮工厂、`toolbarItem`、`validateToolbarItem` |
| 工具页 / 注册表 | `register`、`includedToolIDs`、`catalog`、`perform` |
| 快捷键 | 菜单 key equivalent、`NSMenuItem`、`keyDown`、快捷键中心 |
| 通知 | `post`、`addObserver`、`publisher(for:)`、Combine 订阅 |
| FFI | Rust 导出 → 头文件 → Swift 声明 → 应用调用 → UI 结果 |

需要排除的“假可达”：

- 入口存在但 `isEnabled = false` 且没有可用条件。
- 入口存在但点击回调为空。
- 入口被旧版本代码覆盖，实际显示的是另一个视图。
- 工具注册表列了条目，但页面过滤掉或点击被忽略。
- 快捷键被菜单或系统拦截，实际不触发。

### 3.4 设置键读写闭环

先找键定义，再找所有引用：

```bash
KEY=show_file_tags
rg -n "\"$KEY\"|FFUserDefaultsKeys\.showFileTags" "$SWIFT" --glob '*.swift'
```

分类每处引用：

| 类型 | 特征 | 是否算闭环 |
|---|---|---|
| 定义 | `static let ... = "key"` | 不算 |
| 写入 | `set(_:forKey:)`、`removeObject(forKey:)` | 只是起点 |
| 设置页读取 | 设置窗口初始化控件 | 只证明能回显 |
| 业务读取 | 非设置 UI 的模型/视图/服务读取 | 算读取方 |
| 应用 | `didSet`、通知、重新布局、重新加载 | 算生效路径 |
| 测试 | 测试里设置/读取 | 只证明键可读写，不证明功能生效 |

判定：

- 只有定义 + 写入 + 设置页读取：`写了不生效`。
- 有业务读取但只在启动时读一次：功能可能生效，但改设置后要重启；按验收要求判断。
- 有读取但没有应用（例如读了布尔值却从不影响渲染）：仍是断开。
- 键名是字符串字面量时，别只搜符号常量；两种形式都搜。
- SwiftUI 还要搜 `@AppStorage("key")`、`UserDefaults(suiteName:)`。

来源会话报告过 9 个只写不读键。复跑时以当前代码重算，不要沿用数字。以下键名可作为候选起点，逐个核验后再下结论：

`show_file_tags`、`show_file_extensions`、`show_system_files`、`folder_first_sort`、`keep_selection_position`、`smb_default_domain`、`smb_auto_reconnect`、`check_update_on_startup`、`confirm_file_operations`。

### 3.5 权限与平台能力

先列 Info.plist 的用途说明：

```bash
rg -n 'UsageDescription' "$SWIFT/Resources/Info.plist"
```

再找需要用途说明的 API：

```bash
rg -n 'NSAppleScript|OSAScript|AVCaptureDevice|CNContactStore|CLLocationManager|EKEventStore|PHPhotoLibrary' \
  "$SWIFT" --glob '*.swift'
```

常见映射：

| API / 能力 | 需要的键 |
|---|---|
| `NSAppleScript`、向其他 App 发送 Apple Events | `NSAppleEventsUsageDescription` |
| 摄像头 | `NSCameraUsageDescription` |
| 麦克风 | `NSMicrophoneUsageDescription` |
| 通讯录 | `NSContactsUsageDescription` |
| 日历 / 提醒 | `NSCalendarsUsageDescription` / `NSRemindersUsageDescription` |
| 照片库 | `NSPhotoLibraryUsageDescription` |
| 桌面 / 文稿 / 下载 | `NSDesktopFolderUsageDescription` / `NSDocumentsFolderUsageDescription` / `NSDownloadsFolderUsageDescription` |
| 外置卷 / 网络卷 | `NSRemovableVolumesUsageDescription` / `NSNetworkVolumesUsageDescription` |

还要检查：

- 沙盒 entitlement 是否允许目标路径或网络访问。
- 签名方式是否让 TCC 权限在每次构建后重置。
- 缺少用途键时，系统可能直接拒绝而不弹窗；不能只看“有没有报错弹窗”。

### 3.6 无障碍与键盘

自定义 `NSView` 不是天然可访问的按钮。至少检查：

```bash
rg -n 'setAccessibilityElement|setAccessibilityRole|setAccessibilityLabel|setAccessibilityHelp|setAccessibilityEnabled|accessibilityPerformPress|acceptsFirstResponder|keyDown|nextKeyView' \
  "$SWIFT/UI/FFPillButton.swift" "$SWIFT/UI/SidebarView.swift"
```

通过条件：

- 有 `setAccessibilityElement(true)` 或等价的可访问容器。
- 有正确的 `role`（按钮、链接、行等）。
- 有 label；仅有 label 不够。
- 有按压缩放/动作实现，VoiceOver 能执行。
- 键盘焦点能到达，且有可见焦点或等价反馈。
- 父视图的 `accessibilityChildren` 没有把子元素吞掉。

常见误判：`SidebarView.swift:316` 给 `toolPill` 设了 label，但 `FFPillButton` 本身没有 element/role/action。label 只让元素有名字，不会让它自动成为可操作按钮。

### 3.7 测试盘点

```bash
rg -n 'func test[A-Za-z0-9_]+' "$TESTS" --glob '*.swift'
rg -n '^final class .*Tests|^class .*Tests' "$TESTS" --glob '*.swift'
rg -n '#\[(tokio::)?test\]' "$RUST/src"
```

同时找应用内自检：

```bash
rg -n 'FF_SELFTEST|SELFTEST|selfTest|SelfTest' "$REPO/Makefile" "$SWIFT" --glob '*.swift'
```

记录：

- 测试方法总数，不把 `XCTAssert` 数当测试数。
- 测试文件与测试类。
- 行为测试、几何/令牌测试、纯工具测试的比例。
- 应用内自检的段数与断言数。
- 台账中的实机证据（截图路径、AX 记录、日志）。

注意：

- 只跑单个测试时，不得更新全量测试总数。
- 测试名字存在不代表断言了用户行为；必须看测试体。
- 一个 UI 测试如果只实例化视图并断言属性，不能证明点击、键盘或真实窗口路径。
- 应用内自检与 XCTest 是两套证据，不能相加成“覆盖率”。

### 3.8 限制、占位与死代码

```bash
rg -n 'maxDepth|maxResults|pageSize|prefix\([0-9]+\)|limit|即将推出|coming soon|isEnabled = false|isHidden = true' \
  "$SWIFT" --glob '*.swift'
```

死代码检查：

```bash
# 把 CANDIDATE 换成待核验的类型或函数
CANDIDATE=FFLegacyPanel
rg -n "\b$CANDIDATE\b" "$SWIFT" --glob '*.swift'
```

注意：`FFEmptyStateView` 在当前仓库已被删除（`CHANGELOG.md` 记录），但 `REQUIREMENTS.md` 仍写“已建但生产未引用”。这是文档过期，不是现存死代码；不要按旧类型继续审计。实际空态由 `FFPaneStateOverlayView` 承担。

判定：

- 只有定义、注释、测试引用，生产路径 0 引用：候选死代码。
- 仍在 storyboard/XIB、`NSClassFromString`、selector 字符串或通知里出现：不能直接判死。
- 资源文件被代码动态拼接名字时，静态搜索可能漏。
- 死代码先标“候选”，删除需要用户确认和回归测试。

## 4. Rust / FFI

### 4.1 三层对齐

```bash
rg -n 'pub (unsafe )?extern "C" fn ff_' "$RUST/src"
rg -n '^ff_[a-z0-9_]+\(' "$RUST/include/ff_ffi.h"
rg -n '@_silgen_name\("ff_' "$SWIFT" --glob '*.swift'
```

检查：

- Rust 导出名、头文件声明名、Swift `@_silgen_name` 名完全一致。
- 参数顺序、类型、可空性、字符串所有权一致。
- 返回值与错误码语义一致。
- 头文件是否被实际包含/链接；只声明不链接会运行时失败。

### 4.2 应用调用方

```bash
rg -n '\bff_task_submit\s*\(' "$SWIFT" --glob '*.swift'
rg -n '\bff_organize_by_date\s*\(' "$SWIFT" --glob '*.swift'
```

排除声明文件后仍无调用，只能说明“FFI 层未接线”。继续查应用层是否已有替代实现：

```bash
rg -n 'TaskService|TaskCoordinator|NotificationCenter|Combine|Progress' "$SWIFT" --glob '*.swift'
```

真实反例：`ff_task_submit` 在 Swift 侧只有声明，没有应用调用；但 `FFTaskService` 已被查重、批量重命名和进度条写入，任务面板也订阅它。此时“任务中心永远空”是错的，正确结论是“FFI 调度入口未接线，但应用级任务服务已工作”。必须把两层分开写。

### 4.3 签名不一致

历史审计出现过 `ff_task_submit` 的 Rust 参数与头文件参数不一致。检查时不要只看函数名：

- 头文件声明与 Rust 定义逐参数对照。
- Swift `@_silgen_name` 的签名与 C 头文件对照。
- 调用点传参是否与声明一致。
- 单元测试是否直接调用 Rust 函数而绕过 C ABI；这种测试不能证明 FFI 可用。

## 5. 覆盖矩阵

### 5.1 列定义

| 列 | 填写要求 |
|---|---|
| ID | 需求编号 |
| 旅程 | J1–J5 或横切 |
| 需求摘要 | 一句话，不改语义 |
| 实现证据 | 生产代码 `file:line`，或“无” |
| 自动化证据 | `测试文件::用例名`，多个用分号，或“无” |
| 证据等级 | 【断言】【实机】【静态】【未验】 |
| 覆盖判断 | 完整 / 部分 / 仅手工 / 无 |
| 缺口 | 实现 / 测试 / 权限 / 无障碍 / 实机 |
| 建议测试名 | 具体行为名 |

### 5.2 覆盖判断标准

- **完整**：有自动化行为断言，且断言了用户可见结果；必要时另有实机证据。
- **部分**：只有几何、令牌、内部状态、单个纯函数测试，或只覆盖旅程的一小段。
- **仅手工**：只有截图、AX、日志或人工操作记录，没有自动化。
- **无**：没有实现证据，或实现存在但完全不可达。

### 5.3 建议测试名

格式：

```text
test<旅程><场景><预期>
```

示例：

```text
testJ1PermissionGateShowsChineseGuidanceAndOpensSettings
testJ2SearchFindsFileBeyondThreeLevelsAndReportsTruncation
testJ3ToolPageKeepsPaneSelectionAndRestoresFavorites
testJ4ToolPillIsAccessibleAsButtonAndKeyboardActivatable
testJ5ReadOnlyVolumeShowsChineseRecoveryAction
```

要求：

- 名字能看出前置条件、动作、预期。
- 不写 `testSearch`、`testToolPage` 这种无法判断行为的名字。
- 涉及限制时，测试要同时断言限制被触发以及用户看到提示。
- 涉及无障碍时，测试要断言 role/action/焦点，而不只是 label 字符串。

## 6. FlowFinder 专用参数

### 6.1 路径与命令

```bash
REPO=/Volumes/Iris-Data/文件管理系统/flowfinder-native
SWIFT=$REPO/FlowFinder/FlowFinder
TESTS=$REPO/FlowFinder/Tests/FlowFinderTests
RUST=$REPO/rust-core
DOCS=$REPO/docs
```

常用验证命令（执行前先读 Makefile 和交接文档）：

```bash
make version
make build
make swift-test
make rust-test
FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1 \
  "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder"
```

- 自检日志通常在 `/tmp/ff-debug.log`。
- `make swift-test` 可能结束正在运行的 FlowFinder 实例；不要在用户正在使用桌面副本时直接跑。
- 只跑单个测试时，不要更新全量 XCTest 总数。
- 台账当前记录的基线是 349 条 XCTest、163 项自检（2026-10-22）；这是待复核值，不是本轮实测值。

### 6.2 已核实的审计样例

以下样例用于说明“怎么查”，不是永久结论；复跑时以当前代码为准。

| 线索 | 当前证据 | 审计含义 |
|---|---|---|
| 权限用途缺失 | `Resources/Info.plist` 有 5 条 `NS*UsageDescription`，没有 `NSAppleEventsUsageDescription`；`BreadcrumbBar.swift:483` 使用 `NSAppleScript` | 文档“6 条全缺”过期；仍缺 AppleEvents，需补键或改掉 AppleScript |
| 自绘胶囊的 AX | `FFPillButton.swift:9` 是 `NSView`，没有 element/role/action；`SidebarView.swift:316` 只设 label | 仅有朗读名，不构成可操作按钮；补 AX 与键盘焦点 |
| FFI 有导出无应用调用 | `ff_organize_by_date/type` 在 Rust 与 `FFIFunctions.swift` 有定义/声明，生产代码无其他调用 | 归为“写了不生效”；接线、删除或明确本版不做 |
| 搜索硬限制 | `PaneState.swift:1289-1297` 固定 `maxDepth = 3`、`maxResults = 500` | 若验收要求更深/更多，需改限制并给截断提示 |
| 空态视图文档 | `REQUIREMENTS.md` 写 `FFEmptyStateView` 已建但生产未引用；`CHANGELOG.md` 记录该类型已删除，`DESIGN-SPEC.md` 写实际由 `FFPaneStateOverlayView` 承担 | 文档过期；不要按旧类型继续找死代码 |
| 只写不读设置 | 来源会话报告 9 个键；候选见 §3.4 | 复跑逐个核验读写闭环，不沿用数字 |
| 任务中心层级 | `ff_task_submit` 无 Swift 应用调用；但 `FFTaskService` 被查重/批量重命名/进度条写入，任务面板订阅 | 不能凭 FFI 零调用判“任务中心永远空” |
| 测试基线 | 台账记录 349 XCTest + 163 自检 | 只能作为起点；要跑全量或标“未重跑” |

### 6.3 FlowFinder 文档角色

| 文件 | 用途 |
|---|---|
| `docs/PRODUCT.md` | 产品定位、明确不做 |
| `docs/REQUIREMENTS.md` | 当前版本需求与状态 |
| `docs/ACCEPTANCE.md` | 可执行验收条件 |
| `docs/REQUIREMENTS-LEDGER.md` | 唯一开发台账、证据与基线 |
| `docs/HANDOVER.md` | 交接入口、命令、债务、未验项 |
| `docs/SPEC-*.md` / `docs/PLAN-*.md` | 已确认设计与实施阶段 |

修复完成后的文档同步不属于本 Skill，交给 `flowfinder-docs-sync`。

## 7. 误报排查

静态搜索的零命中或单命中都可能误导。遇到以下机制时，必须补运行时或人工证据：

| 机制 | 排查方式 |
|---|---|
| Objective-C selector | 搜 `#selector`、`NSSelectorFromString`、`perform(_:)`，检查 responder chain |
| 通知 | 搜 `NotificationCenter`、`post`、`addObserver`、`publisher(for:)` |
| Combine / SwiftUI | 搜 `@StateObject`、`@EnvironmentObject`、`@AppStorage`、`onReceive` |
| KVO | 搜 `observe(\.)`、`addObserver` |
| 动态类/方法 | 搜 `NSClassFromString`、`String(describing:)`、反射 |
| C 函数指针 | 搜 `dlsym`、`Unmanaged`、函数类型变量 |
| 资源/本地化 | 搜资源生成脚本、字符串表、storyboard/XIB |
| 生成代码 | 查生成目录和构建脚本，不只看手写源码 |

处理原则：

- 找不到调用方时写“候选未接线”，不要写“绝对没有”。
- 找到调用方但无法确认用户可达时，补入口链路或标“静态可达、未实机”。
- 运行时证据优先于源码猜测；AX、日志、截图、真实点击都算。

## 8. 证据记录

每条结论至少记录：

```text
日期：2026-10-22
commit：<hash>
命令：rg -n ... 
结果：3 处命中；其中 2 处测试，1 处生产声明，0 处应用调用
结论：FFI 层未接线；应用层是否有替代路径待查
```

要求：

- 不把搜索命中数写成功能数。
- 不把旧台账数字写成当前实测值。
- 不把“代码里没有”写成“产品不需要”。
- 不把“测试通过”写成“用户旅程通过”。
- 不修改代码或文档；需要修复时退出审计模式，按用户批准的批次执行。
