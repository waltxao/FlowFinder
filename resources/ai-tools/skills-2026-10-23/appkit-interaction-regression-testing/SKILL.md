---
name: appkit-interaction-regression-testing
description: "AppKit/macOS 拖拽与命中类回归的三层验证流程：纯函数 XCTest 先红后绿 → 应用内真实 hitTest/几何自检 → 以日志实测值回写文档。Use when fixing or testing AppKit drag/drop, tab reorder, window dragging, hitTest, mouseDownCanMoveWindow regressions; when xcodebuild XCTest hangs, the test host exits due to a single-instance policy, a new Swift test file is missing from the Xcode target, or the repo lives on an external volume. 触发词：拖拽回归、命中测试、标签重排、XCTest、pbxproj、测试宿主、外置卷。"
---

# AppKit 交互回归三层验证

## 适用场景

在 macOS AppKit 应用里修交互回归，尤其是：

- 标签拖拽、条内重排、跨面板/跨窗口落点。
- 窗口拖动、`mouseDownCanMoveWindow`、标题栏带命中。
- `hitTest` 吞事件、控件点不动、点击落到错误视图。
- 需要给上述行为补 XCTest 护栏。
- `xcodebuild test` 疑似挂起，或测试宿主启动即退出。
- 交接文档声称“测试通道不可用”，需要先复测再决定方案。

配合 `superpowers:test-driven-development` 使用；本 skill 只补 AppKit/Xcode 平台层步骤，不重复通用红绿原则。UI 需求的可视化确认不在本 skill 范围内。

## 三层验证

| 层 | 手段 | 锁定的问题 | 通过标准 |
|---|---|---|---|
| 1 | 纯函数 + XCTest | 判定表、插入索引、坐标转换、落点分流 | 先因预期断言失败，再全绿 |
| 2 | 应用内真实视图自检 | 真实视图树、`contentView.hitTest`、几何不变量 | 新步骤先 FAIL 后 PASS，汇总 0 失败 |
| 3 | 日志实数 + 截图回写文档 | 断言数、测试通道状态、几何数字漂移 | 文档数字与日志一致 |

三层缺一不可：纯函数测不到 AppKit 的视图树和坐标；应用内自检无法穷举状态组合；只跑测试不回写文档，下一个人会继续基于过期数字做决定。

## 执行流程

### 0. 预检：先证伪旧结论

- 确认使用完整 Xcode，而不是 Command Line Tools：检查 `xcode-select -p`，必要时设置 `DEVELOPER_DIR`。
- 先跑一次基线全量测试，再决定是否需要 workaround。不要因为交接文档写着“通道坏了”就直接降级验证。
- 检查应用是否在跑：`pgrep -fl '<App 可执行文件名>'`。单实例策略会让测试宿主秒退；很多测试脚本会先 `pkill`。结束用户正在使用的应用前必须征得同意。
- 仓库在外置卷时，把构建产物放到内置卷：设置绝对路径的 `SYMROOT`/`OBJROOT`，或使用内置卷的 `-derivedDataPath`。
- 测试会读写桌面/文稿时，使用隔离的测试 HOME。
- 把完整输出写入日志，用超时保护；不要只看 Makefile 里 `grep | tail` 后的几行。

命令模板：

```sh
DEVELOPER_DIR=<Xcode.app>/Contents/Developer \
xcodebuild test -project <Project>.xcodeproj -scheme <TestScheme> \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

### 1. 抽纯函数，先写失败测试

把“按下去/落到哪里发生什么”的判定抽成不依赖 AppKit 的类型：

- 区域 → 意图的决策表。
- 插入索引：左半/右半/末尾空白/缓冲边界。
- stack / strip / window 坐标转换。
- 落点分流：重排、合并、拆双栏、独立成窗、无效落点。

测试至少覆盖已知 bug、边界值和“目标原有标签必须保留”这类不变量。新测试文件必须在 `project.pbxproj` 注册四处：

1. `PBXBuildFile`
2. `PBXFileReference`
3. 所属 group 的 `children`
4. test target 的 `PBXSourcesBuildPhase`

注册前先 grep 候选 ID；复用已占用 ID 会让 Xcode 解析到旧 fileRef，新文件静默丢失。不要对 `project.pbxproj` 执行 `git checkout`，直接编辑。

先只跑新测试类：

```sh
xcodebuild test ... -only-testing:<TestTarget>/<TestClass>
```

门禁：失败必须来自预期断言，而不是编译/链接错误。若报 `cannot find X in scope`，先检查 pbxproj 注册。

### 2. 最小实现转绿

只修到新测试通过，然后跑全量，确保原有用例不回归。不要在这一步顺手重构无关代码。

### 3. 应用内真实视图自检

给应用加一个启动自检步骤（例如 ⑥），构造真实窗口/视图树，用真实 frame 推导点位，调用 `contentView.hitTest`，断言：

- 命中视图解析到预期区域与意图。
- `NSControl`、点击手势不会被拖窗区域吞掉。
- 标签条、卡片四边等几何符合设计常量。
- 用户可见不变量，例如“拖出的新窗口必须是单栏且只含被拖标签”。

每个断言打印一行，包含实际值与期望值：

```text
[SELFTEST] ⑥ <名称> PASS/FAIL actual=<...> expected=<...>
```

运行方式按项目约定，例如：

```sh
<APP>_SKIP_PERMISSION_GATE=1 <APP>_SELFTEST=1 <可执行文件路径>
```

尽可能在修复前先跑出 FAIL，再验证 PASS。从未失败过的自检不是证据。自检必须走真实链路；如果它绕过真实窗口或使用假视图，就会和用户看到的界面脱节。

### 4. 几何日志与截图

记录标签条、卡片边缘、插入线、控件命中区的实际数值，与设计常量比对。需要视觉确认时截图并放大核对。合成鼠标事件只能作为 smoke：

- `CGWindowList` 使用屏幕左上原点，`CGEvent` 使用左下原点。
- 可能触发 TCC/辅助功能授权弹窗。
- 窗口遮挡会改变命中结果。

不要把合成事件的结果当作“物理手感已验证”。

### 5. 用日志实数回写文档

- 从日志统计断言数和分类小计，不抄旧文档。
- 更新交接文档、台账、CHANGELOG 和测试通道状态。
- 明确更正过期结论，例如旧文档的断言数、`XCTest 阻塞`。
- 标注仍未验证的项：物理拖拽手感、桌面副本点击、真位移等。
- 用户未要求时不要提交。

### 6. 完成门禁

- [ ] 新测试在修复前因预期原因失败。
- [ ] 全量 XCTest 0 失败，出现 `** TEST SUCCEEDED **`。
- [ ] 构建成功。
- [ ] 应用内自检 0 失败，新步骤实际观察到 FAIL → PASS。
- [ ] 几何数字、断言数与文档一致。
- [ ] 人工未验证项已明确列出。

## 失败模式速查

| 现象 | 很可能的原因 | 处理 |
|---|---|---|
| `test runner hung before establishing connection` | 应用在跑 + 单实例宿主 | 征得同意后结束应用，再跑测试 |
| `Building Swift (Debug)...` 后长时间无输出、无 `swift-frontend` | 仓库/产物在外置卷，llbuild 卡在条件变量 | 构建产物改到内置卷，重跑 |
| 新增文件后 `cannot find X in scope` | pbxproj 缺注册或 ID 冲突 | 检查四处注册，grep ID |
| 点任何标签都选最后一个，拖也拖最后一个 | `hitTest` 直接 `return self`，未做 `frame.contains`；NSStackView 逆序派发 | 命中前先判断 `frame.contains(point)` |
| 缓冲区重排失效、指示线偏移 | stack / strip / window 坐标混用 | 抽纯函数，统一转到 strip 坐标 |
| 控件点不动 | 控件落在 `.window`/`.title`，被翻译成拖窗口 | 对 `NSControl`/点击手势豁免，声明正确区域 |
| 同侧落点复制出标签 | 同侧分支走了 `insert` | 同侧只做 `move` |
| 拖出的新窗默认双栏 | 初始化读取全局 `single_pane_mode` | 显式传 `startsWithSinglePane`，装配完再显示，禁用递归自检 |
| 日志有 `linkd.autoShortcut` 警告但 `TEST SUCCEEDED` | 系统服务噪声 | 以最终状态和失败数为准 |
| 自检全绿但真实应用仍坏 | 自检绕过真实链路或使用假视图 | 改为真实 `contentView.hitTest` + 真实 frame |

## 已验证案例

FlowFinder（macOS AppKit 文件管理器，2026-10-20）：

- 基线 144 条 XCTest、0 失败，证明交接文档的“测试通道阻塞”已过期。
- 新增 18 条回归测试：修前 19 处断言失败，修后 162/0。
- 应用内自检 129 项、0 失败；六步落点自检全部 PASS，新增 ⑥“拖出新窗为单栏”。
- 后续 TDD 累计到 190/0。

具体命令、pbxproj ID、日志片段和根因表见 `references/verified-case-2026-10-20.md`。

## 资源

- `references/verified-case-2026-10-20.md`：完整实测案例，含基线命令、注册 ID、红→绿计数、自检 ⑥ 日志和失败根因。
