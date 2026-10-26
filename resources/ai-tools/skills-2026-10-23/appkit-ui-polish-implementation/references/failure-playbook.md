# AppKit UI 精修故障手册

每个模式按“症状 → 根因 → 识别 → 最小修复 → 回归 → 真机复验”处理。代码片段是模式示例，接入时使用项目现有类型、token 和测试设施。

## 1. 深色模式白底白字（复用窗口）

**症状**

- 辅助窗口、设置窗口或单例面板在深色模式下出现白底白字，浅色模式正常。
- 首次打开可能正常，关闭重开或切换主题后出错。
- 同一个窗口在系统外观切换后颜色不更新。

**根因**

- 初始化时把动态 `NSColor` 解析成 `CGColor` 并缓存；`CGColor` 是快照，不跟随外观。
- 单例窗口只构建一次视图，外观变化时没有重新赋值。
- 只在 `viewDidLoad` 设置颜色，没有在 `viewDidChangeEffectiveAppearance` 或每次显示时重应用。
- 测试只覆盖了一种外观，或测试宿主继承了真实系统外观。

**识别**

- 搜索 `static let`、`static var`、`cgColor`、`layer?.backgroundColor`、`textColor` 的赋值位置。
- 看颜色是否在初始化路径只执行一次。
- 在窗口打开时切浅色/深色，再关闭重开；分别截图。
- 检查窗口是否复用了上一次的 `effectiveAppearance` 或缓存视图。

**最小修复**

```swift
private func applyAppearance() {
    let background = NSColor.windowBackgroundColor
        .resolvedColor(with: effectiveAppearance)
    layer?.backgroundColor = background.cgColor

    titleLabel.textColor = .labelColor
    separator.layer?.backgroundColor = NSColor.separatorColor
        .resolvedColor(with: effectiveAppearance).cgColor
}

override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyAppearance()
}
```

窗口控制器在每次显示前也应用一次，防止窗口未挂载时错过外观回调：

```swift
override func showWindow(_ sender: Any?) {
    contentViewController?.view.layoutSubtreeIfNeeded()
    contentViewController?.applyAppearance()
    super.showWindow(sender)
}
```

要点：

- 用语义色或项目动态 token；不要用 `.white`/`.black` 硬编码。
- 需要 `CGColor` 时，用 `resolvedColor(with: effectiveAppearance)` 现取现用。
- 每次 show 重新应用；不要假设 `viewDidChangeEffectiveAppearance` 一定会覆盖所有复用路径。
- 测试中强制设置 `window.appearance = NSAppearance(named: .darkAqua)`，不要依赖当前系统主题。

**回归护栏**

- 视图/窗口测试：`.aqua` 与 `.darkAqua` 各断言背景、文字、分隔线的解析结果。
- 复用循环：show → close → show，两种外观各跑一次。
- 真机：窗口打开时切主题、关闭重开、关闭时切主题，三组截图。
- 若测试实例化生产窗口控制器，先按 `macos-xctest-isolation` 隔离偏好。

**不要做**

- 不要只在 `viewDidLoad` 里再赋一次颜色。
- 不要缓存 `NSColor.cgColor` 作为固定值。
- 不要用“深色下把文字改成黑色”掩盖背景错误；先确认背景和文字都来自正确外观。

## 2. ⌘I 被右键菜单抢占

**症状**

- 主菜单里 ⌘I 的命令不触发，反而执行了某个上下文菜单动作。
- 在不同焦点区域按 ⌘I，行为不一致。
- 右键菜单打开时快捷键看似正确，关闭后主命令失效。

**根因**

- 上下文菜单项设置了 `keyEquivalent`，与主菜单或 responder 链中的命令重复。
- 同一个快捷键在多个菜单/多个 target 上注册。
- 命令依赖具体窗口控制器，而不是通过 responder 链路由。

**识别**

- 枚举主菜单、上下文菜单、工具栏菜单，打印 `title`、`keyEquivalent`、`keyEquivalentModifierMask`、`action`、`target`。
- 在编辑器、列表、空白区分别按快捷键，确认实际命中的 target。
- 检查最近新增的 `NSMenuItem` 是否复制了主菜单的键位。

**最小修复**

- 移除上下文菜单项的 `keyEquivalent`，保留标题/动作。
- 让主菜单项唯一拥有该快捷键；动作使用 `target = nil` 或正确的 responder 链目标。
- 如果命令在不同上下文有不同语义，给它们不同键位，不要共享同一个。

菜单盘点示例：

```swift
func allItems(in menu: NSMenu) -> [NSMenuItem] {
    menu.items + menu.items.flatMap { item in
        item.submenu.map(allItems(in:)) ?? []
    }
}

func shortcutOwners(of key: String, in menu: NSMenu) -> [NSMenuItem] {
    allItems(in: menu).filter {
        !$0.isSeparatorItem
            && $0.keyEquivalent.lowercased() == key.lowercased()
    }
}
```

应用内自检或菜单构造测试断言：

```swift
let owners = shortcutOwners(of: "i", in: NSApp.mainMenu!)
XCTAssertEqual(owners.count, 1, "⌘I 应只有一个归属")
```

`NSApp.mainMenu` 在单元测试环境可能不可用；此时把断言放进应用内自检，或直接测试构建菜单的函数。

**回归护栏**

- 唯一归属测试：同一快捷键只允许一个菜单项。
- 上下文测试：有选中/无选中、key/non-key window 下命令仍可达。
- 真机按键冒烟：编辑器、列表、空白区各一次。

**不要做**

- 不要用“把主菜单快捷键删掉”来消除冲突。
- 不要假设上下文菜单不在主菜单里就不会参与键位解析；实际盘点。
- 不要用隐藏菜单项来“解决”冲突，隐藏项仍可能参与路由。

## 3. 主题迁移后旧粉色残留

**症状**

- 迁移逻辑看起来执行过，标记也已置位，但界面仍有旧粉色/旧强调色。
- 重启后仍残留；换主题或打开新窗口才短暂正常。
- 只有部分控件残留，其他颜色已更新。

**根因**

- 布尔迁移标记先被置位，但实际 token/派生色没有重算。
- 旧值仍被读取，或旧值被缓存成 `CGColor`/图片/图层颜色。
- 迁移只处理主强调色，没有处理派生的 hover、选中、边框、发光色。
- 迁移顺序或竞态导致标记写入成功、颜色写入失败。
- 清理范围过大或过小：误删用户偏好，或没有清掉已知旧键。

**识别**

- 读取持久化键和迁移版本：`defaults read <bundle-id>`。
- 用旧偏好 fixture 复现，而不是只在干净安装上测试。
- 搜索所有派生色和缓存路径：`cgColor`、`layer?.backgroundColor`、缓存的 `NSImage`、单例。
- 确认迁移是否幂等；重复运行是否仍能修正。

**最小修复**

```swift
enum ThemeMigration {
    static let currentVersion = 2

    static func run(defaults: UserDefaults) {
        let stored = defaults.integer(forKey: "themeSchemaVersion")
        guard stored < currentVersion else { return }

        // 从源数据重算，而不是只翻标记
        let palette = ThemePalette.make(from: stored)
        ThemeStore.apply(palette)
        defaults.set(currentVersion, forKey: "themeSchemaVersion")
    }
}
```

如果标记已经等于当前版本但颜色仍残留，说明旧迁移没有真正完成：提升版本号或增加“校验实际存储值”的修复步骤，而不是直接相信标记。

清理旧键时先备份：

```sh
defaults export <bundle-id> /tmp/<bundle-id>.defaults.backup.plist
defaults delete <bundle-id> <confirmed-stale-key>
```

只删除已确认的键；绝不 `defaults delete <bundle-id>` 删除整个 domain。

**回归护栏**

- 旧偏好 fixture：写入旧版本、旧粉色和派生键，运行迁移，断言：
  - 版本号更新。
  - 旧粉色不再被解析为当前 token。
  - 派生色（hover/选中/边框）也更新。
- 重启后读取实际持久化值，再截图。
- 重复运行迁移，确认幂等。

**不要做**

- 不要把“标记已置位”当作迁移成功。
- 不要只改主强调色，忽略派生色。
- 不要删除整个 defaults domain 来“清干净”。
- 不要在迁移未完成时提前写入新标记。

## 4. 一侧面板圆角是直角

**症状**

- 左面板左上角是直角，右面板左上角是圆角；或者某个角在活动/非活动切换后形态不一致。
- 代码里所有卡片都设置了相同 `cornerRadius`，真机却不一致。
- 只有一个角异常，其他三个角正常。

**先判断，不要先统一**

1. 切换活动面板，观察直角是否跟随活动态移动。
2. 如果直角跟着活动态走，可能是“活动/非活动面板”的有意差异；回到规格确认，不要擅自把所有角改成同一个值。
3. 如果直角固定在同一侧/同一角，按实现缺陷处理。

**常见根因**

- 外层 wrapper 与内层 container 的圆角/裁切不一致。
- 某个祖先视图 `masksToBounds = true`，把圆角或发光裁掉。
- 只给卡片背景层设置了圆角，内容层/高亮层仍覆盖成直角。
- 活动态切换时只更新了边框/发光，没有更新圆角或 mask。
- 视图层级中有一个不透明背景视图没有圆角，盖住了卡片的圆角。

**识别**

- 用 `appkit-visual-effect-verification` 的视图/图层树与裁剪方法做归因。
- 固定窗口尺寸，裁四角；不要只看顶部。
- 打印每个疑似视图的 `cornerRadius`、`masksToBounds`、`frame`、`backgroundColor`。
- 检查活动/非活动切换路径是否只更新了部分视觉属性。

**最小修复**

- 在正确的容器层应用规格圆角，避免内外层重复裁切。
- 内容层不要用不透明直角背景盖住卡片圆角；必要时让内容层继承圆角或裁剪。
- 活动/非活动切换时同步更新圆角相关属性和 mask。
- 仍然只在规格要求时使用 `cornerCurve = .continuous`。

**回归护栏**

- 几何/策略测试：圆角归属、活动态差异策略。
- 应用内自检：打印实际 `cornerRadius` 与 `masksToBounds`，断言与规格一致。
- 真机：四角裁剪 + 活动/非活动截图 + 缩放/全屏。

**不要做**

- 不要因为“看起来不圆”就全局调大 radius。
- 不要用 mask 强行裁所有内容，导致子视图消失或发光被切。
- 不要把活动/非活动的有意差异当成 bug 抹平。

## 5. CUA 状态丢失、坐标失效

交给 `macos-native-ui-verification` 的恢复矩阵处理。最短处置：

1. 确认目标 bundle id/绝对路径与 PID；不要沿用旧实例。
2. 按 bundle id 或精确路径重新获取 App。
3. 拉全量 AX 基线，丢弃所有旧 element ID。
4. 重新截图，确认坐标属于当前窗口和当前几何。
5. 同一状态两次恢复失败即标 `Blocked`，保留错误文本、PID、窗口标题和最后截图。

不要：

- 在旧截图上继续点。
- 复用旧 element ID。
- 把 `No active app state` 当成产品 bug。
- 在用户正在操作 App 时抢焦点。

## 6. XCTest 污染真实偏好或宿主挂起

交给 `macos-xctest-isolation` 与 `xcode-swift-delivery-loop`：

- TestAction 设置 `CFFIXED_USER_HOME` 与测试标记；LaunchAction 不得带测试 home。
- 在持久化写入点做运行时守卫；测试需要持久化时注入独立 suite。
- 用 `assert-defaults-unchanged.sh` 在测试前后比对真实键。
- 宿主卡在 LaunchServices/侧栏图标时，先 sample 主线程，再决定测试专用跳过开关；不要把测试开关带进生产。
- 测试结束后正常启动一次，确认真实用户目录没有被污染。

## 7. 停损规则

出现以下任一情况，停止自动重试并记录 `Blocked`/`Unverified`：

- 同一视觉问题连续两轮只调颜色/数值，本质特征没有变化。
- 同一 CUA 状态两次恢复失败。
- 测试红灯来自编译/链接错误，而不是预期断言。
- 需要结束用户进程、覆盖桌面副本、删除偏好或修改权限才能继续。
- 规格本身无法判断“哪种才对”，且用户尚未确认。

保留现场证据，写清下一步需要谁做什么，不用新的猜测覆盖失败记录。
