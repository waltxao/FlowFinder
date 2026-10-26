# 已验证案例：FlowFinder 三边微光（2026-10-21）

## 背景

- 产品：FlowFinder，macOS AppKit 文件管理器，双面板。
- 需求：活动面板只亮左/下/右三边，顶部标签区保持干净；非活动面板不亮。
- 用户反馈：在桌面版看到效果后说“你自己看看，窗口发光做错了”。

## 第一版为什么失败

实现：`FFActivePaneGlowView`，两层 `CAGradientLayer`（wide/core），用只描左/右/下的 `CAShapeLayer` 作为 mask；wide 20px、core 4px；渐变从底部 accent 到顶部透明；顶部路径停在 `bounds.height - 2`，意图是不画顶部。

真机结果：

- 仍然是等宽、清晰的蓝色描边，不是柔光。
- 顶部也有蓝线，和“顶部干净”的目标相反。
- 给两层渐变 layer 加 `shadowColor` / `shadowOpacity` / `shadowRadius` 后，仍是硬边。
- 继续降低透明度只会让线更细，不会产生衰减。

结论：primitive 选错。描边 + 渐变 mask 的几何边界不会因为加 shadow 或调透明度变成柔和光晕。

## 证据链

### 1. 真实窗口截图与裁剪

用 computer-use 打开构建产物，确认前台，截目标窗口；把截图写到 `/tmp/ff-restored-layout.png`。随后用 sips 裁左上/右上：

```sh
cd /tmp
sips -c 260 600 --cropOffset 0 190 ff-restored-layout.png --out pane-left-top.png
sips -c 260 600 --cropOffset 0 595 ff-restored-layout.png --out pane-right-top.png
```

判读：左（活动）面板有连续蓝线；右（非活动）面板的线更弱；顶部仍被包边。硬边特征没有因为透明度变化而消失。

### 2. lldb 归因

打印视图树：

```sh
lldb -p 92597 -b \
  -o 'expr -l objc++ -O -- (id)[[[[NSApplication sharedApplication] windows] firstObject] contentView]' \
  -o 'expr -l objc++ -O -- (id)[[[[[NSApplication sharedApplication] windows] firstObject] contentView] performSelector:@selector(_subtreeDescription)]' \
  -o 'detach' > /tmp/ff-view-tree.txt 2>&1
```

输出中找到：

```text
FlowFinder.FFActivePaneGlowView 0x7a52373c00 f=(0,0,601,900)
```

隐藏该视图并再次截图：

```sh
lldb -p 92597 -b \
  -o 'expr -l objc++ -- (void)[(NSView*)0x7a52373c00 setHidden:YES]' \
  -o 'detach'
```

结果：蓝线完全消失。说明伪影来自 `FFActivePaneGlowView`，不是卡片背景或内容。诊断后重启 App 恢复；`setHidden` 没有进入产品代码。

### 3. 原生阴影复验

删除 `FFActivePaneGlowView` 后，在卡片容器 layer 上应用原生阴影。截图保存为 `/tmp/ff-glow-shadow.png`，再裁发光区：

```sh
sips -c 400 700 --cropOffset 0 150 ff-glow-shadow.png --out glow-shadow-crop.png
```

判读：整圈硬描边消失，阴影主要落在底部和左右，顶部标签区更干净。

## 最终实现

删除 `FFActivePaneGlowView` 及其测试，改为在卡片容器 layer 上应用原生阴影。`FFPaneGlow.apply` 的核心：

```swift
static func apply(to view: NSView, active: Bool, color: NSColor) {
    guard let layer = view.layer else { return }
    let spec = FFGlowSpec.standard
    layer.masksToBounds = false
    layer.shadowColor = color.cgColor
    layer.shadowOpacity = active ? Float(spec.opacity * 0.62) : 0
    layer.shadowRadius = spec.blurRadius + 4
    // 在本项目的图层坐标里，负 y 让阴影向下；其他项目要用截图确认符号。
    layer.shadowOffset = CGSize(width: 0, height: -5)
    updateShadowPath(for: view)
}

static func updateShadowPath(for view: NSView) {
    guard let layer = view.layer, layer.shadowOpacity > 0 else { return }
    layer.shadowPath = CGPath(roundedRect: view.bounds.insetBy(dx: 8, dy: 8),
                              cornerWidth: 16, cornerHeight: 16,
                              transform: nil)
}
```

集成要点：

- `SquircleView.layout()` 里调用 `FFPaneGlow.updateShadowPath(for: self)`，否则窗口尺寸变化后 `shadowPath` 不更新。
- 活动切换时调用 `apply(to:active:color:)`；非活动把 `shadowOpacity` 设为 0。
- 强调色/外观变化时重新赋 `shadowColor`，因为 `CGColor` 不会跟随动态 `NSColor`。
- `masksToBounds = false`；卡片父容器不能裁掉外扩的阴影。

## 验证结果

- `make build`：BUILD SUCCEEDED。
- `make swift-test`：258 条，0 失败。
- 桌面 `FlowFinder.app` 已替换为最新构建；可执行文件 SHA-256：`501665e3…acf7a65`。
- 原生阴影截图已保存并裁剪：`/tmp/ff-glow-shadow.png` → `/tmp/glow-shadow-crop.png`。
- 结果：硬边/整圈描边消失，阴影主要落在底部和左右，顶部标签区更干净。

## 未验收项

- 阴影的强度/柔和度是否达到用户审美，用户当时没有明确确认；助手自己也评价为“较微妙”。
- 深色/高对比模式下的阴影可见性没有单独截图。
- 非活动面板在用户实际窗口中的对比只做了截图判断，没有做像素级测量。

因此本次可以声称“已改为原生阴影，硬边消失，构建/测试通过”，不能声称“用户已接受视觉效果”。

## 教训

1. 硬边先换 primitive，不要先调透明度。
2. 真实窗口截图 + 四边裁剪比代码审阅可靠。
3. lldb 隐藏疑似视图可以快速归因，但只是诊断，不是修复。
4. `shadowPath` 必须随布局更新，`masksToBounds` 必须为 false。
5. 视觉验收是用户决策；测试通过不等于审美通过。
