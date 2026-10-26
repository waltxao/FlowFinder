---
name: appkit-ui-polish-implementation
description: "Implement an approved macOS AppKit UI polish plan end-to-end: reproduce each defect, encode it in a failing XCTest, apply the minimal appearance-aware fix, then verify light/dark live rendering, menu shortcuts, theme migration, build, in-app self-check, and the exact desktop copy. Use when asked to 落地已确认的 AppKit UI 精修, 统一或修复面板/卡片圆角, 修复双面板活动态圆角不一致, 深色模式白底白字, 辅助窗口复用后的外观错误, 右键菜单抢占 ⌘ 快捷键, 主题迁移后残留旧色, or to finish 详情/工具栏/搜索/查重 UI 精修."
---

# AppKit UI 精修实施

## 目标

把已确认的 macOS AppKit UI 精修规格逐项落到代码：每个缺陷先复现，能测则先红后绿，修复必须外观感知，最后在用户真正打开的产物上完成浅色/深色与交互状态验收。

本 Skill 是实施编排层，不替代相邻 Skill：

| 任务 | 使用 |
|---|---|
| 需求未收敛、需要多方案取舍 | `visual-requirement-confirmation` |
| 纯 UI 审计、逐屏验收、CUA/AX 状态恢复 | `macos-native-ui-verification` |
| 圆角/阴影/发光/毛玻璃的真机渲染归因 | `appkit-visual-effect-verification` |
| 拖拽、命中、窗口手势回归 | `appkit-interaction-regression-testing` |
| 拖拽卡顿、帧率与主线程性能 | `appkit-drag-performance` |
| Xcode 文件登记、测试通道、交付闸门 | `xcode-swift-delivery-loop` |
| 测试污染真实 `UserDefaults` | `macos-xctest-isolation` |

## 适用与不适用

适用：

- 已有批准规格、决策记录或整改计划，并已获得明确实施授权。
- 多界面精修：面板/卡片圆角、详情区、工具栏、搜索、查重、辅助窗口、菜单与主题迁移。
- 需要把“看起来修好了”推进到“可回归、可真机验收”的 AppKit UI 缺陷。
- 反复出现的外观问题：静态 `CGColor`、快捷键被菜单抢占、迁移后旧色残留、活动态圆角不一致。

不适用：

- 规格未确认、仍需要用户做视觉选择：先用 `visual-requirement-confirmation`，一次只问一个问题。
- 只要求审查或验证现有构建：用 `macos-native-ui-verification`。
- 只需要判断某个视觉效果该用 shadow、border、blur 还是 mask：用 `appkit-visual-effect-verification`。
- Web、移动端、纯逻辑或纯性能任务。

## 硬规则

1. 一次只关闭一个缺陷或一个决策；视觉选择未定时只问一个聚焦问题并停下。
2. 改动前先固定基线：被测产物、浅/深色、活动/非活动、可复用窗口的首次与再次显示。
3. 先复现再改代码；行为可测时先写失败测试。编译失败不算红灯。
4. 单测是回归证据，不是视觉证据；视觉结论必须来自真实产物窗口截图加状态证据。
5. 验证用户真正打开的产物，通常是桌面副本，而不是只有 DerivedData 构建。
6. 未经允许不结束、不重启用户正在用的 App，不覆盖桌面副本，不删除用户数据。
7. 默认不 commit、不 push，除非用户明确要求。
8. 保持已批准的结构：双面板应用保留两个独立面板卡片与面板内详情，不擅自引入全局栏或合并卡片。
9. 测试专用跳过开关、隔离 home、临时隐藏视图不得进入生产路径。
10. 卡住时记录具体阻塞，不做无限重试；同一状态最多尝试两次恢复。

## 开工前

1. 读取已确认规格/决策记录，提取：
   - 圆角 token，以及活动/非活动面板是否允许差异。
   - 涉及哪些界面和状态。
   - 浅色/深色/高对比要求。
   - 快捷键归属与菜单层级。
   - 主题迁移的预期和旧数据边界。
   - 每项的验收证据。
2. 记录目标：工程、scheme、测试 scheme、bundle id、构建产物、桌面副本、版本/build、运行中的 PID。
3. 检查运行实例；只记录，不擅自结束。用户正在操作时等待。
4. 采集基线截图：浅色/深色、活动/非活动、辅助窗口首次/复用、空态/错误态/焦点态；固定窗口尺寸，便于前后对比。
5. 若测试会实例化生产窗口控制器或写入偏好，先按 `macos-xctest-isolation` 做隔离。
6. 建立证据台账，再开始改代码。

## 证据台账

```text
| ID | 界面/状态 | 已确认期望 | 实际观察 | 回归测试 | 修复 | 真机证据 | 状态 |
```

- 一行只对应一个可独立验收的缺陷。
- 状态只用 `Verified`、`Unverified`、`Blocked`。
- 不写“整体 UI 已修好”这类聚合行；未测项必须单独列出。
- 证据写截图路径、测试命令、断言数、产物路径/版本/哈希，不写“看起来可以”。

## 单缺陷闭环

1. **复现**
   - 找到最小稳定复现步骤，记录外观、活动面板、窗口尺寸、产物路径。
   - 先判断这是实现缺陷还是规格未定的视觉差异；若是后者，停下来问一个问题。
2. **红灯**
   - 纯逻辑：颜色/token 解析、圆角策略、菜单位属、迁移映射。
   - 视图层：强制 `.aqua` / `.darkAqua` 后断言解析色、`cornerRadius`、`masksToBounds`、菜单键位。
   - 应用内自检：用真实视图树与几何断言，打印 `PASS/FAIL actual=... expected=...`。
   - 纯视觉且无法自动断言时，先写清截图验收条件，并补一个最接近的非视觉护栏；不要静默跳过。
   - 运行聚焦测试，保存红灯输出。
3. **最小修复**
   - 只改满足本行验收所需的代码，不顺手重构。
   - 外观相关修改必须考虑浅色/深色、活动/非活动、首次/复用。
4. **转绿**
   - 先跑聚焦测试，再跑相关测试与全量，记录准确数量。
5. **真机复验**
   - 重新构建，启动新进程，按固定几何对比浅色/深色与相关状态。
   - 更新台账；未测项标 `Unverified`。
6. **停损**
   - 同一视觉问题连续两轮只调数值仍无本质变化，停止调参，转层归因或回到规格确认。

## 界面实施清单

### 圆角与卡片层级

- 先判断差异是否是有意的活动态强调：切换活动面板，看直角是否跟随活动态移动。若跟随，先确认规格，不要擅自把所有角统一。
- 固定窗口尺寸检查四角、活动/非活动、缩放、全屏、还原；只看一个角或只看顶部不算验收。
- 检查外层卡片与内层容器的 `cornerRadius`、`masksToBounds`、content inset，避免双重裁切和单角直角。
- 使用规格 token；`cornerCurve` 只在规格要求时使用。
- 视觉归因交给 `appkit-visual-effect-verification`（裁剪、视图/图层树、lldb），不要用“调大/调小”猜。

### 双面板、详情与工具栏

- 两个独立面板卡片，详情留在面板内；不引入全局栏、合并卡片或额外装饰条。
- 分隔线/间距不能让两张卡视觉粘成一张；窄窗口下复验。
- 活动态强调不能压过内容，也不能降低文字对比。
- 详情区覆盖长路径、缺失元数据、折叠/展开、焦点/选中/非活动。
- 工具栏检查分组、分隔、溢出、可访问标签、随 key window 更新可用性，不重复控件。

### 搜索与查重

- 搜索：焦点环、占位、清除、空/无结果/错误、键盘路径、窄宽度；不把局部搜索扩成全局栏。
- 查重：空闲/扫描/结果/空/错误/取消；进度、选中、布局稳定、强调色克制。
- 两者都要在浅色/深色下检查背景、文字、分隔线和焦点可见性。

### 辅助窗口

- 单例/复用窗口每次 `show` 都重新应用外观，不缓存静态 `NSColor`/`CGColor`。
- 覆盖首次显示、关闭重开、打开时切主题、关闭时切主题。
- 重点查深色白底白字、浅色低对比、分隔线消失、控件颜色不跟随。
- 确认窗口焦点和 key window 状态；不要把后台窗口的禁用菜单误判为产品 bug。

### 菜单与快捷键

- 盘点主菜单、上下文菜单、工具栏菜单的 `keyEquivalent` 与 modifier mask。
- 右键菜单不得拥有应用级快捷键（如 ⌘I）；移除冲突后确认命令仍有可达入口。
- 命令走 responder 链；验证有选中/无选中、key window/非 key window 的启用状态。
- 用应用内自检或菜单构造测试断言“同一快捷键只有一个归属”。

### 外观与主题迁移

- 迁移标记已置位不等于界面正确；旧持久化颜色、缓存 `CGColor`、未重算的派生色都可能残留。
- 用版本化迁移重算/重应用 token；只清理已确认的旧键，先备份；绝不删除整个 defaults domain。
- 用旧偏好 fixture 回归，再重启验证持久化值和真实颜色。
- `NSColor` 动态色转 `CGColor` 会快照；在 `viewDidChangeEffectiveAppearance` 和每次显示时重新解析。

## 真机验证

- 逐屏验收、CUA/AX、截图状态恢复与产物锁定交给 `macos-native-ui-verification`；本 Skill 只定义要验哪些界面和状态。
- 圆角、阴影、发光、毛玻璃的渲染归因交给 `appkit-visual-effect-verification`；不要用设计稿、HTML 或单测代替真实窗口。
- CUA 出现 `stateLost`、`userChangedFocus`、`New accessibility baseline` 或截图坐标失效时：
  - 按 bundle id 或绝对路径重新获取 App。
  - 重新拉全量 AX，丢弃旧 element ID 和旧截图。
  - 等窗口稳定后重新截图，再继续。
  - 同一状态两次恢复失败就标 `Blocked`，保留错误文本和最后已知窗口信息。
- 浅/深色对比使用同一窗口尺寸、位置和内容；复验使用新构建、新进程。
- 不使用单元测试通过来宣称视觉正确。

## 交付与交接

- Xcode 文件登记、测试通道、构建与最终闸门按 `xcode-swift-delivery-loop` 执行。
- 测试隔离按 `macos-xctest-isolation` 执行。
- 用 `scripts/verify_app_copy.sh` 比对构建产物与桌面副本；默认只读，不覆盖、不启动、不杀进程。
- 需要覆盖桌面副本时先征得同意；覆盖后重新比对并启动冒烟。
- 收尾至少包含：
  - 已完成的界面与已关闭的决策 ID。
  - 构建、聚焦测试、全量测试、应用内自检的准确结果。
  - 产物路径、版本/build、可执行文件哈希、浅/深色截图路径。
  - 未验/阻塞项及下一步。
  - 边界：未提交、未推送、保留的测试专用开关、仍存在的技术债。

最终报告模板：

```text
完成：<界面/缺陷清单>
证据：<构建、XCTest 数量、自检数量、产物路径/版本/hash、截图>
未验：<视觉、性能、人工手感、权限项；附复核步骤>
边界：<未提交、未推送；测试隔离开关；技术债>
```

## 高频故障速查

| 症状 | 更可能的根因 | 最小修复 | 回归护栏 |
|---|---|---|---|
| 深色模式白底白字 | 单例窗口复用了初始化时的静态 `CGColor` | 改用动态色；在 `viewDidChangeEffectiveAppearance` 与每次 show 重新解析并赋值 | 两种外观 × 首次/关闭重开/打开时切主题 |
| ⌘I 触发的是右键菜单动作 | 上下文菜单项设置了 `keyEquivalent` | 移除右键菜单键位，让主菜单/responder 链唯一拥有；确认入口仍可达 | 菜单盘点测试：同一快捷键唯一归属 |
| 迁移后旧粉色仍出现 | 迁移标记已置位，但旧色未重算或仍被缓存 | 版本化迁移 + 重算 token + 清理已知旧键（先备份） | 旧偏好 fixture + 重启后读实际值/颜色 |
| 一侧面板圆角是直角 | 活动/非活动差异，或内外层圆角/裁切不一致 | 先切换活动面板判断；再做图层归因，在正确层应用规格圆角 | 四角裁剪 + 活动/非活动截图 + 几何自检 |
| CUA 状态丢失、坐标失效 | 基线/截图过期或焦点变化 | 按 bundle id 重连、全量 AX、重新截图；两次失败即停 | 记录 PID/窗口/错误文本，标 Blocked |

更完整的原因、代码模式与测试写法见 [failure-playbook](references/failure-playbook.md)。

## 资源

- [UI polish checklist](references/ui-polish-checklist.md)：逐界面实施项、测试钩子与验收证据。
- [Failure playbook](references/failure-playbook.md)：静态颜色、快捷键抢占、迁移残留、圆角不对称、CUA/测试隔离的详细处置。
- [verify_app_copy.sh](scripts/verify_app_copy.sh)：只读比对构建产物与桌面副本的 bundle id、版本、可执行文件哈希。
- 相邻 Skill：`visual-requirement-confirmation`、`macos-native-ui-verification`、`appkit-visual-effect-verification`、`xcode-swift-delivery-loop`、`macos-xctest-isolation`、`appkit-interaction-regression-testing`。
