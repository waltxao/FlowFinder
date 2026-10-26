# 实测案例：F-02 详情栏展开后每列只剩一行（2026-10-22，FlowFinder 0.8.0-26102235）

来源会话 `55665e8c-c7de-4c41-8f4f-b359570ac313`，缺陷编号 F-02，落库为 R-35。
本文件保留可核对的原始数值与命令，供 SKILL.md 主流程需要细节时按需加载。

## 症状

展开详情栏后只显示「名称 + 创建日期」两行（8 个信息行里每列只排到 1 行），
折叠再展开、改宽改高都不恢复；不点不拖就永远停在塌陷态。

## 已失效的假设（重要：不要重复走）

改造前的代码是这样选可用高度的，并且注释把它当成正确做法：

```swift
let availableWidth = max(columnsStack.bounds.width, 1)
// 必须用 clip view 的可视高度：contentSize 是 documentView 的固有高度，
// 会随内容增长，拿它判断"装得下"等于永远装得下，行会被裁掉却不重排。
let availableHeight = max(infoScrollView.contentView.bounds.height, 1)
```

「改用 clip 可视高度」相对 `documentView.contentSize` 确实是进步（后者会随内容增长），
但它仍然读的是**后代视图 frame**，在同一轮遍历里就是旧值——这正是缺陷本身。

## 取证：三条路只有一条能用

### lldb attach（失败，别再试）

`process attach -p 4097` 能挂上并停在 `mach_msg2_trap`，但表达式全部不可用：

| 尝试 | 结果 |
|---|---|
| `expr -l objc++ -O -- NSWindow *w = [[NSApplication sharedApplication] windows][0]` | `error: no member… 'windows'`（只有 `NSApp` 符号可解析） |
| 加显式类型转换 `(NSArray*)… objectAtIndex:` | `error: no known method '-performSelector:'; cast the message send to the method's return type` |
| `expr -l objc++ -O -- (NSString*)[… recursiveDescription]` | 打印 `(NSString *) 0x0000000000001114`（乱指针） |
| `expr … (void)[s writeToFile:@"/tmp/ff-viewtree.txt" …]` | 文件根本没生成 |

结论：该二进制（Swift + AppKit，ad-hoc 签名）的调试信息里没有 ObjC 类型信息，
表达式求值不可信。改走应用内日志。

### AX 树（不够用）

`System Events` 报主窗口只有 11 个直接 UI 元素；详情栏的「种类/大小/位置/创建日期/
修改日期/标签/文件说明」等自绘字段完全不在 AX 输出里。另外，未选中文件时点
「文件 > 显示简介」不会产生任何布局日志（`grep -c FFDBG` = 0），必须先选中一行。

### 应用内 NSLog 几何日志（决定性）

在 `rearrangeFlow()` 里加一条日志，一次打印栏/子树各层 frame、约束 constant、
父视图同一性与 active 约束列表。实测输出（隔离副本 PID 4097）：

```
FFDBG flow w=402.0 h=30.0 clip=30.0 content=30.0 heights=[16.0,16.0,16.0,16.0,16.0,16.0,16.0,16.0]
layout=[[0],[4]] | bar={{0,0},{558,132}} exp={{8,18},{542,108}} stack={{0,0},{542,108}}
modules={{0,0},{542,108}} scroll={{140,0},{402,30}} hc=132.0 applied=132.0 user=132.0
sup=Optional((8.0, 8.0, 574.0, 856.0)) scrollParentFrame={{0,0},{542,108}} sameParent=1
scrollConstraints=<NSAutoresizingMaskLayoutConstraint:… NSClipView:….minX == 0 (active, …)> || …
```

读法：

- `bar` 高 132、`exp/stack/modules` 108 都已到位；
- `scroll` 仍 `{{140,0},{402,30}}`——30 是折叠态内容高，即上一轮的值；
- `sameParent=1` 且约束 `active`、日志里没有任何 "Unable to simultaneously satisfy constraints"，
  排除挂错父视图和约束冲突；
- 结论：横向（x=140、w=402）已被解析、纵向没跟上——同一轮遍历内 AppKit 自上而下更新 frame，
  父已到位、子仍是旧值。

## 红绿门：先造出一个无效闸门

第一版 harness 用真实 `NSWindow` + `container.layoutSubtreeIfNeeded()` + `RunLoop.main.run(0.2)`：

```
FFTEST bar={{0,0},{600,132}} scroll={{162,0},{422,108}} clip={{0,35},{422,108}} doc={{0,35},{422,73}}
```

窗口里几何全对，测试通过——**但把测量来源临时改回旧写法后仍然通过**：

```
$ xcodebuild test … -only-testing:FlowFinderTests/FFDetailsLayoutTests/testExpandedDetailsFlowFitsAllRowsIntoVisibleHeight
Test Case '…testExpandedDetailsFlowFitsAllRowsIntoVisibleHeight]' passed (0.245 seconds).
** TEST SUCCEEDED **        # exit=0，闸门对缺陷不敏感
```

同一版还先崩过一次测试宿主（`~/Library/Logs/DiagnosticReports/FlowFinder-2026-10-22-221205.ips`）：

```
EXC_BAD_ACCESS / SIGSEGV
objc_release → AutoreleasePoolPage::releaseUntil → objc_autoreleasePoolPop
→ -[XCTMemoryChecker _assertInvalidObjectsDeallocatedAfterScope:]
→ -[XCTestCase assertInvalidObjectsDeallocatedAfterScope:]
```

即真实 `NSWindow` 在测试宿主里与 XCTest 内存检查器冲突；工程内 `rearrangeFlow()` 的既有注释
也写着「单元测试避免使用真实 NSWindow（窗口簿记延迟块与测试裸释放竞态，曾致运行器 SIGSEGV）」。

### 有效闸门

去掉窗口、去掉 flush，按展开态尺寸用 frame 挂载后直接调 `rearrangeFlow()`：

```swift
// 栏按展开态尺寸挂载；子视图未参与布局，frame 仍是初始化值
let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 132))
container.addSubview(bar)
```

改前（镜像内把 `infoAreaSizeForFlow` 临时回退成读 `columnsStack.bounds` / clip frame）：

```
error: XCTAssertEqual failed: ("1.0") is not equal to ("108.0") - 可用高度应由栏自身高度扣除顶部热区与状态栏推导
error: XCTAssertGreaterThan failed: ("1.0") is not greater than ("300.0") - 可用宽度应由栏宽度扣除左右缩进、图标区与分界线推导
error: XCTAssertEqual failed: ("0") is not equal to ("8") - 展开态应放下全部信息行
** TEST FAILED **           # exit=65
```

恢复修复版：

```
Test Case '…]' passed (0.032 seconds).
** TEST SUCCEEDED **
```

红绿取证全程在 `/tmp/ff-src-fulltest` 镜像里做（源工程零改动），跑法与镜像准备见
`flowfinder-xctest-batch-verification`。

## 修复

```swift
/// 信息区可用尺寸（F-02）：由详情栏自身 bounds 与已知缩进推导。
/// 重排发生在本次布局遍历之内，信息区/clip 等子视图 frame 仍是上一轮
/// （折叠态 30pt）的旧值，而栏自身 bounds 已被约束引擎更新；
/// 读子视图会把每列压到一行，且遍历结束后不会再触发自愈重排。
/// internal：布局回归测试需要同一份口径（裸容器里 clip 不会 settle 到目标高度）
var infoAreaSizeForFlow: CGSize {
    let icon = iconWidthC?.constant ?? iconWidth
    let height = max(bounds.height - topEdgeHeight - statusBarHeight, 1)
    let width = max(bounds.width - expandedSideInset * 2 - icon - iconDividerWidth, 1)
    return CGSize(width: width, height: height)
}
```

配套：新增 `expandedSideInset = 8` / `iconDividerWidth = 8` 常量并替换约束字面量，
让推导口径与约束同源；删掉 `rearrangeFlow()` 开头的 `layoutSubtreeIfNeeded()`；
行高改在脱离视图层级的测量台里按 `availableWidth` 测。

## 回归与复核

- 布局相关 5 个测试类串跑：`Executed 45 tests, with 0 failures` / `** TEST SUCCEEDED **`。
- 实机：新副本唯一 Bundle ID `com.flowfinder.f02.live`、`codesign --force --deep --sign -`、
  `FF_SKIP_PERMISSION_GATE=1` 直接 exec，PID 7246 且 `ps` 校验可执行路径属于该副本；
  先 `cua` 选中一行，再用 `System Events` 点「文件 > 显示简介」驱动展开。
- 取图：AX 里看不到详情栏字段，改用 `screencapture -x` 全屏 + PIL 裁剪
  （窗口 `{60,60}`、尺寸 `{1620,900}`，缩放 2）：

```python
box = (60*2, (960-330)*2, (60+1620)*2, 960*2)
Image.open('/tmp/ff-f02c-wide2.png').crop(box).save('/tmp/ff-f02c-wide2-crop.png')
```

  窄栏（`{620,700}`）与宽栏两种状态各取一张，确认 1–4 列流动布局都装下了全部行。
- 应用内自检：`FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1` 在隔离副本上跑通。

## 收尾

```bash
grep -rn "FFDBG" FlowFinder/ | head      # 必须为空
rm -rf "$(cat /tmp/ff-f02c-dir.txt)"     # 删除临时副本
pgrep -f "macos-ui-verify" || echo "no audit instances running"
```

CHANGELOG 记为「## [未发版] ### F-02 详情栏 1–4 列流动布局修复（2026-10-22，第二十八轮 R-35）」，
`docs/ACCEPTANCE.md` 补 R-35 D-06 验收口径。
