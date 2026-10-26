---
name: appkit-visual-effect-verification
description: "在真实 AppKit 窗口中验证原生视觉效果，而不是在 mockup 或代码里推断。Use when glow/shadow/rounded-corner/blur/focus-ring work looks right in code or HTML but renders as a hard edge, crisp outline, clipped halo, wrong color, or wrong shape; when the user says 发光做错了、圆角不对、真机效果不对, or asks to verify 活动/非活动面板、微光、阴影、蒙版、材质. Covers primitive selection, computer-use screenshots, edge crops, lldb view/layer attribution, and honest acceptance records."
---

# AppKit 视觉效果真机验证

## 目标

把“代码写完了”推进到“真实窗口渲染正确，并且验收状态说清楚”。本 Skill 关注 AppKit/CALayer 的视觉结果：发光、阴影、描边、圆角、毛玻璃、焦点环、蒙版。

核心规则：**mockup、HTML/CSS、代码审阅、单元测试都不能证明 AppKit 的渲染结果。只有真实 App 窗口的截图算视觉证据。**

## 适用与不适用

适用：

- 代码或设计稿看起来正确，真实窗口却出现硬边、等宽描边、顶部脏边、光晕被裁、颜色不对、圆角不一致。
- 用户说“发光做错了”“圆角不对”“真机效果不对”“你自己看看”。
- 活动/非活动面板、浅色/深色、不同窗口尺寸下的视觉效果需要逐项核对。
- 需要判断某个视觉效果该用 shadow、border、gradient、blur 还是 mask。

不适用：

- 纯布局几何、拖拽/命中/手感：用 `macos-appkit-ui-verification` 或 `appkit-interaction-regression-testing`。
- 需求还没定、需要多方案取舍：用 `visual-requirement-confirmation`。
- Web UI、纯逻辑测试、性能分析。

## 失败模式：先认出来，再修

### 硬边不是“调得不够淡”

典型症状：

- 发光呈等宽 1–2px 亮线，边缘没有自然衰减。
- 降低 opacity 只是让线更细/更暗，线的“硬度”不变。
- 顶部或四角出现一条本不该有的包边。
- 用两层、三层渐变和 mask 叠加，仍然像描边。

根因通常是 primitive 选错：用“描边 + 渐变 + mask”去模拟柔光。`CAGradientLayer` 被描边路径 mask 后，边界仍然是几何边界；再给这个 layer 加 `shadow*` 也不保证变成柔和光晕。继续调颜色/透明度是在错误的方向上优化。

**停止条件：连续两轮只调 opacity/color，硬边特征没有变化，就停止调参，换 primitive 或先做层归因。**

### 其他常见误判

| 现象 | 更可能的原因 | 先检查 |
|---|---|---|
| 光晕被切平 | 祖先视图 `masksToBounds`/`clipsToBounds` 为 true | 每一层祖先的裁剪设置 |
| 窗口缩放后光晕变矩形/偏移 | `shadowPath` 没有随 bounds 更新 | `layout()` / `viewDidLayout` |
| 切换主题后颜色不更新 | `CGColor` 是快照，不跟随动态 `NSColor` | 外观/强调色变化时重新赋值 |
| 顶部仍有一条亮边 | 单独画了顶部 edge，或 mask 路径包含整圈 | 删除顶部 edge；检查 path 是否只覆盖需要的边 |
| 四角光晕形状不对 | `shadowPath` 用了普通圆角，但卡片是 squircle/自定义路径 | 用与卡片相同的路径 |
| 非活动面板也有光 | 只设置了 active 的 opacity，没有在失焦时归零 | 活动切换路径 |

## 选择 primitive

先选对 primitive，再写代码。按“想要的效果”选择，不按框架喜好选择。

| 想要的效果 | 优先 | 避免 / 注意 |
|---|---|---|
| 圆角卡片周围的自然柔光 | 卡片自身 layer 的 `shadowColor` / `shadowOpacity` / `shadowRadius` / `shadowOffset` / `shadowPath` | 描边 + 渐变 mask；多层同心描边 |
| 只亮左/下/右，顶部干净 | shadow 向下偏移；必要时用容器裁剪/遮罩 | 画整圈再想办法挖掉顶部 |
| 清晰 1px 活动边 | border / edge draw | 用 shadow 冒充硬边 |
| 圆角 | `cornerRadius` + `cornerCurve = .continuous` | 用 mask 裁内容导致子视图消失 |
| 毛玻璃/材质 | `NSVisualEffectView` | 多层材质叠加、自己写 blur |
| 键盘焦点环 | 系统 focus ring 或强调色 border | 用发光代替焦点可见性 |

> 数值（radius、opacity、offset、inset）从项目现有 token 和设计规格取，不要把 FlowFinder 的数值写死到其他项目。

### 原生阴影的最小形态

```swift
layer.masksToBounds = false
layer.shadowColor = accent.cgColor
layer.shadowOpacity = isActive ? activeOpacity : 0
layer.shadowRadius = radius
layer.shadowOffset = CGSize(width: 0, height: offsetY)
layer.shadowPath = CGPath(roundedRect: cardRect,
                          cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius,
                          transform: nil)
```

要点：

- `masksToBounds = false`，并检查所有祖先没有裁掉 shadow。
- `shadowPath` 用卡片的真实圆角矩形；卡片在 wrapper 内缩时，用同样的 inset，别猜。
- 在 `layout()` / `viewDidLayout` 更新 `shadowPath`；否则窗口缩放后 shadow 还是旧尺寸。
- `shadowOffset` 的符号取决于视图/图层的坐标翻转；用截图确认方向，不要凭记忆。
- 非活动状态把 `shadowOpacity` 设为 0；活动切换、强调色变化、浅/深色切换都要重新应用。
- `NSColor` 转 `CGColor` 后不会自动跟随外观；在 `viewDidChangeEffectiveAppearance` 或强调色通知里重新赋值。

## 工作流

### 1. 冻结预期

用一句话写清验收对象：

- 哪几条边应该有光/阴影？
- 哪条边必须干净？
- 活动面板与非活动面板的差异是什么？
- 浅色/深色是否都要成立？
- 角是普通圆角还是 squircle？

如果这些无法从设计稿/现有规格判断，先用 `visual-requirement-confirmation` 问一个决策问题；不要用实现猜测审美。

### 2. 锁定被测产物

- 执行项目的构建命令，记录 `BUILD SUCCEEDED`。
- 记录产物路径、mtime、SHA-256。
- 如果用户测试的是桌面副本，先替换并校验；否则你验证的可能是旧包。
- 视觉/层归因使用本地 debug 或 ad-hoc 构建；不要对生产/公证包做 lldb 注入。

### 3. 用 computer-use 截真实窗口

- 用 `computer-use:computer-use` 激活 App，确认它是前台。
- 截目标窗口，不要截整屏后让 Finder/其他窗口混进来。
- 把截图保存到 `/tmp/<name>.png`，再用 Read 查看；不要只依赖对话里的缩略图。
- 至少采集：活动面板（有光/阴影）、非活动面板（应该没有或明显更弱）、四边/四角（顶部、底部、左、右）。
- 产品支持深色/高对比时补测；没测就标 Unverified。

### 4. 裁剪四边与四角

来源案例实际裁了左上、右上和发光区域；把方法扩展为四边+四角，避免只看顶部就下结论。

```sh
sips -c <height> <width> --cropOffset <y> <x> <input.png> --out <crop.png>
```

判读标准：

- **硬边**：从卡片边缘到背景，alpha/亮度是阶跃，线的宽度基本恒定。
- **柔光**：从边缘向外有连续衰减，越远越淡。
- **顶部干净**：顶部没有一条与左右同宽的亮线；如果四角有、顶部没有，说明路径/edge 画法不对。
- **活动/非活动**：非活动面板不应有同强度的光；切换焦点后要交换。
- **四边一致**：左/右/下应有相似的衰减；如果只有某一边硬，检查那条边的 path/edge。

截图尺寸是像素，Retina 下不要拿 1x 和 2x 的裁剪做对比。固定窗口尺寸、位置、外观和内容，否则裁剪无法比较。

### 5. 需要时做层归因

看不清是谁画的，或者怀疑有多个视图叠加时，先归因，不要盲改。

在本地 debug/ad-hoc App 上，用 lldb 打印视图树：

```sh
lldb -p <pid> -b \
  -o 'expr -l objc++ -O -- (id)[[[[NSApplication sharedApplication] windows] firstObject] contentView]' \
  -o 'expr -l objc++ -O -- (id)[[[[[NSApplication sharedApplication] windows] firstObject] contentView] performSelector:@selector(_subtreeDescription)]' \
  -o 'detach' > /tmp/<app>-view-tree.txt 2>&1
```

如果 `firstObject` 为 nil，先确认 App 有窗口且已前台。在输出里找疑似类名和地址，例如：

```text
FlowFinder.FFActivePaneGlowView 0x7a52373c00 f=(0,0,601,900)
```

只在这一轮诊断里隐藏它：

```sh
lldb -p <pid> -b \
  -o 'expr -l objc++ -- (void)[(NSView*)<address> setHidden:YES]' \
  -o 'detach'
```

再次截图：

- 硬边消失 → 该视图/图层就是伪影来源，换它的 primitive。
- 硬边仍在 → 不是它；继续用同样方法排查下一个候选，或临时移除一层后重建。

安全边界：

- lldb 会暂停 App；不要在用户正在操作时附加。
- `_subtreeDescription` 是私有 selector，只用于本地诊断；不可用时退回临时 debug 开关或逐层移除。
- 不要把 `setHidden:YES` 当成修复；诊断后重启 App 恢复，再改代码。
- 不修改用户数据、不注入业务状态、不附加到生产包。
- 无法归因时记录“未确定”，不要猜。

### 6. 在正确的 primitive 上修复

- 硬边：删除描边/渐变模拟，改用卡片 layer 的原生阴影。
- 顶部脏边：不要先画整圈再遮；用 offset 或只覆盖需要的边。
- 阴影被裁：向上检查每一层 `masksToBounds`，确认 shadow 有足够的外扩空间。
- 尺寸变化：在布局回调里更新 `shadowPath`。
- 活动切换：非活动 `shadowOpacity = 0`；活动恢复目标值。
- 强调色/外观：重新赋 `shadowColor`；浅色/深色分别看一遍。
- 如果设计确实需要强彩色渐变光，单一 shadow 可能不够；改用缓存模糊图或专用图层，并重新走真机截图流程，不要假装 shadow 就是渐变。

### 7. 复验与验收记录

- 重新构建，跑项目测试；测试是回归证据，不是视觉证据。
- 重启同一个产物（不要复用旧进程），重复第 3–4 步。
- 记录：
  - **Verified**：真实窗口截图显示硬边消失/四边符合预期；构建和测试结果；产物校验值。
  - **Unverified**：光的强度、柔和度、审美是否符合用户偏好；缺哪张图/哪个外观。
  - **Blocked**：无法截屏、无法 lldb、App 被遮挡/权限受限；说明原因。
- 不要用“已修复/效果对了”代替用户验收。更准确的说法是：“已改为原生阴影，硬边消失；强度是否合适需要你确认。”
- 用户仍说不对时，先问一个聚焦问题：太强、太弱、边错了，还是顶部不干净？再只调对应参数或换 primitive，不要从头重做。

## 反模式

- 用 HTML/CSS 的 `box-shadow` 或设计稿当 AppKit 渲染证据。
- 用整屏截图代替目标窗口截图，结果截到 Finder/其他 App。
- 硬边时继续调 opacity/color，或叠加更多渐变层。
- 给渐变描边 layer 加 shadow，就认为它会变成柔光。
- `masksToBounds = true` 还奇怪阴影为什么被切。
- 只设置一次 `shadowPath`，窗口缩放后不更新。
- 只验证顶部，不验证四边/四角/非活动面板。
- 用 XCTest 通过证明“视觉正确”。
- 把 lldb 的 `setHidden:YES` 留在运行中的 App 里，或把它当修复。
- 用户说“做错了”时，用代码意图解释为什么应该是对的；先看真实截图。

## 完成门禁

- [ ] 构建成功，且记录被测产物路径/校验值。
- [ ] 有活动面板和非活动面板的真实窗口截图。
- [ ] 四边/四角至少各看过一张裁剪图；顶部是否干净有明确结论。
- [ ] 如果出现过硬边，能说清是哪个 primitive 导致的，而不是只说“调淡了”。
- [ ] `shadowPath`/`masksToBounds`/活动切换/强调色更新已检查。
- [ ] 复验使用新构建、新进程。
- [ ] 验收记录区分 Verified / Unverified / Blocked；没有把测试通过当成审美通过。
- [ ] 没有留下 lldb 隐藏、临时 debug 开关或未清理的诊断代码。

## 资源

- `references/verified-case-flowfinder-glow-2026-10-21.md`：FlowFinder 三边微光的失败实现、lldb 归因、最终原生阴影代码、构建/测试结果和未验收项。
- 相邻 Skill：`computer-use:computer-use`（真实窗口操作/截图）、`macos-appkit-ui-verification`（交互证据阶梯）、`visual-requirement-confirmation`（需求确认门禁）。
