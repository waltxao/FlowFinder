---
name: appkit-stale-frame-layout-debug
description: "AppKit「布局回调读到未重排的后代 frame」类缺陷的定位—取证—回归 playbook。当展开/缩放后只剩一行（或每列一行、控件宽度塌成 0）且之后不再自愈、缩放后布局不更新，或怀疑 layout()/其 DispatchQueue.main.async 块里读到的子视图 frame 是旧值时使用；也用于 lldb attach 后 expr 报「no known method -performSelector:」或返回乱指针、AX 树看不到自绘字段、布局回归测试改前就绿的情况。给出 NSLog 几何取证模板、自身 bounds 推导判据、刻意不 flush 布局的红绿门与隔离副本截图裁剪复核步骤。"
---

# AppKit 布局回调读到未重排的后代 frame

## Overview

同一轮布局遍历内，父视图的 `bounds` 已被约束引擎更新，其后代视图的 `frame` 可能仍是
上一轮（例如折叠态）的旧值。任何在 `layout()` 或其 `DispatchQueue.main.async` 块里
读取后代 frame 来「决定怎么排」的代码，都会按旧尺寸分配，并且遍历结束后没有新事件再触发
重排——表现为塌陷后不自愈。本 Skill 固化「取证 → 判据 → 红绿门 → 实机复核」这条链路。

## 适用与不适用

适用：展开/缩放后行数或控件尺寸塌陷且不自愈；布局分支的可用尺寸来自子视图 frame；
需要为布局缺陷建一个改前必红的回归。

不适用（改用对应 Skill）：拖拽手感与逐事件性能 → `appkit-drag-performance`；
命中/hitTest 类交互回归 → `appkit-interaction-regression-testing`；
整体 UI 审计与截图验收 → `cua-macos-ui-audit`；
视觉特效（发光/圆角/模糊）渲染 → `appkit-visual-effect-verification`；
跑测试本身（镜像、分批、Bundle ID 隔离、红绿取证命令）→ `flowfinder-xctest-batch-verification`。

## 1. 停止猜测，直接打几何

不要靠读代码猜哪个假设成立——这类缺陷的实测值会直接推翻直觉（曾把「必须用 clip view
可视高度」写成注释里的正确做法，而它正是 bug）。在可疑的重排入口处打一条几何日志，
一次覆盖三层：栏/容器自身 `bounds`、可疑子视图 `frame`、相关约束 `constant`，
外加父视图同一性与 active 约束列表。

```swift
NSLog("FFDBG bar=\(NSStringFromRect(bounds)) modules=\(NSStringFromRect(contentModules.frame)) "
    + "scroll=\(NSStringFromRect(infoScrollView.frame)) clip=\(NSStringFromRect(infoScrollView.contentView.frame)) "
    + "hc=\(heightConstraint.constant) sameParent=\(infoScrollView.superview === contentModules ? 1 : 0) "
    + "constraints=\(infoScrollView.superview?.constraints.map { "\($0)" }.joined(separator: " || ") ?? "nil")")
```

需要整棵子树时，写一个递归 dump（`depth` 缩进 + 每个节点的 frame 与
`intrinsicContentSize`），在测试里对目标容器调用一次即可看清哪一层没跟上。

Swift 侧坑（都会真实编译失败）：

- 变参 `NSLog("%@ %@", a, b)` 在本工程工具链报 `'NSLog' is unavailable: Variadic function is unavailable`——一律用**单参数 + 字符串插值**。
- `NSStringFromCGSize` 不在 scope，用 `NSStringFromRect` 或 `"\(size)"`。
- 私有属性在测试里取不到：把它开成 `internal` 并写明「internal：布局回归测试需要同一份口径」，不要在测试里 KVC。

日志随隔离副本启动写入应用 stderr（见第 4 步）。

## 2. 判据

同时满足即确认为本类缺陷：

1. 自身 `bounds` 已是新值，子视图 `frame` 仍是上一轮值（实测例：栏 132pt、子视图 30pt）。
2. `sameParent=1` 且相关约束 `active`，即约束本身没错、不是层级挂错——只是**尚未重排**。
3. 遍历结束后无任何事件再触发布局：不点不拖就永远停在塌陷态。

结论固定为：`layout()` 及其 async 块内只能读**自身 `bounds` 与已知常量**，可用尺寸自己推导：

```swift
/// 可用尺寸由自身 bounds 与固定缩进推导；读子视图 frame 会拿到上一轮的旧值。
var infoAreaSizeForFlow: CGSize {
    let icon = iconWidthC?.constant ?? iconWidth
    return CGSize(
        width: max(bounds.width - expandedSideInset * 2 - icon - iconDividerWidth, 1),
        height: max(bounds.height - topEdgeHeight - statusBarHeight, 1))
}
```

同时删掉入口里的 `layoutSubtreeIfNeeded()`：在同一次遍历中被重入调用时它不生效，只留下
「已经 flush 过」的错觉。

## 3. 红绿门（改前必红）

两条反模式，都会造出「改前也绿」的假闸门：

- **在 harness 里 flush 布局**（`container.layoutSubtreeIfNeeded()` + 跑 RunLoop）：子视图被
  强制 settle 到新值，旧的错误读法照样得到正确尺寸，测试对缺陷不敏感（实测：回退到旧测量后仍 `exit=0` 通过）。
- **用真实 `NSWindow` 作宿主**：`XCTMemoryChecker _assertInvalidObjectsDeallocatedAfterScope:` →
  `objc_autoreleasePoolPop` → `objc_release` SIGSEGV，测试宿主整个挂掉（工程内已有同类注释）。

有效做法：按**目标态尺寸**用 frame 直接挂载视图（不加约束、不 flush），让子视图 frame 停在
初始化值，然后**直接调用重排入口**，断言推导出的可用尺寸与最终行数/列数。

```swift
let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 132))
container.addSubview(bar)          // 刻意不 layoutSubtreeIfNeeded
bar.rearrangeFlow()                // 复现「子视图尚未重排」的时刻
XCTAssertEqual(bar.infoAreaSizeForFlow.height, 108, accuracy: 0.5)
XCTAssertEqual(visibleRows, 8)
```

证明它真的红：在 `/tmp` 镜像里临时把测量来源改回旧写法（源工程零改动），跑单个测试方法，
拿到失败断言（实测 `("1.0") is not equal to ("108.0")`、可见行 `("0") is not equal to ("8")`），
再恢复修复版跑绿。命令与镜像用法见 `flowfinder-xctest-batch-verification`。

## 4. 实机复核

测试绿不等于用户看到的界面正确，必须回到真实窗口取一次图。

1. 构建产物 → 隔离副本（唯一 Bundle ID + `codesign --force --deep --sign -`）：
   复用 `cua-macos-ui-audit/scripts/prepare-audit-copy.sh`，不要动用户正在用的实例。
2. 直接 exec 启动并把 stderr 落盘（跳过权限引导窗），随后按 PID + 可执行文件路径校验归属：

```bash
DIR=$(mktemp -d /tmp/macos-ui-verify-XXXXXX)   # 或 prepare-audit-copy.sh 的输出目录
: > /tmp/ff-probe.log
FF_SKIP_PERMISSION_GATE=1 nohup "$DIR/FlowFinderAudit.app/Contents/MacOS/FlowFinder" >> /tmp/ff-probe.log 2>&1 &
sleep 6; PID=$(pgrep -f "$DIR/FlowFinderAudit.app/Contents/MacOS"); ps -p "$PID" -o pid,comm | tail -1
```

3. 用菜单驱动状态变化（比合成点击稳），再读日志确认几何：

```bash
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID)
  click menu item \"显示简介\" of menu 1 of menu bar item \"文件\" of menu bar 1
end tell"
```

4. 截图取证据。自绘视图不向 AX 暴露字段（窗口只报十几个元素、看不到「种类/大小/位置」等标签），
   所以只能看图：`screencapture -x` 全屏后按 System Events 的 `position/size`（点、左上原点）
   乘以缩放系数裁剪窗口或窗口内区域：

```bash
python3 scripts/crop_window_screenshot.py --pid "$PID" --out /tmp/ff-bar.png --region 0,570,700,330
```

   裁的是屏幕像素：目标窗口被别的窗口遮挡时先把它置前，或用 `--keep-full` 看整屏。
   缩放系数自动探测；非整数缩放或探测失败时显式传 `--scale 2`。
5. 逐项复核窄/宽、展开/折叠等状态，并跑一次应用内自检（如 `FF_SELFTEST=1`）。

## 5. 收尾

- `grep -rn "FFDBG" <source>` 必须为空——诊断日志不进主干。
- 结束自建实例（按 PID，绝不 `pkill -f FlowFinder`）、`rm -rf` 临时副本目录，`pgrep` 确认无残留。
- 把根因写成一句可复述的话进 CHANGELOG/ledger（例：「重排在同一轮布局遍历内读取尚未重排的
  信息区 frame（栏 132pt、子视图仍 30pt），每列只分到 1 行且不再自愈」），并同步受影响文档口径。
- 顺带清理被本次改造作废的旧注释与断言（如「纵向滚动兜底」），它们会误导下一轮判断。

## Resources

- `scripts/crop_window_screenshot.py` — 全屏截图 + 按 PID 窗口几何裁剪（已在本机实测：
  1400×900 窗口与 `--region 0,570,700,330` 子区域均正确落图，PID/窗口索引错误给出明确报错）。
- `references/verified-case-2026-10-22-f02.md` — 本流程的完整实测案例（F-02 详情栏流动布局）：
  真实日志数值、lldb 失败签名、假闸门与真闸门的对比输出、实机复核与收尾命令序列。
