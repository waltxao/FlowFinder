---
name: macos-app-ui-verification
description: "macOS 原生 App（SwiftUI/AppKit）真机 UI 验证与像素测量。用于对已运行应用截图核对、用 Computer Use 按坐标点击、窗口被遮挡或不在前台时取证、量控件中线与间距、构造窄侧栏等难拖拽状态，以及排查系统 TCC 权限弹窗、\"Screenshot coordinates require a current screenshot\"、\"user is still interacting\" 等阻塞。不适用于 iOS 模拟器、纯 Web 页面或只改代码不跑真机的场景。"
---

# macOS App 真机 UI 验证

把“看起来对”变成可复核的证据：窗口截图、像素中线、AX 状态。没有证据不宣称通过。

## 何时使用

- 修改 macOS 原生应用 UI 后，需要真机截图或点击验证。
- 窗口被遮挡、不在前台、或用户正在操作，仍要取证。
- 对齐、间距有 1–2pt 疑问，需要量出中线而不是目测。
- 需要用持久化默认值构造窄侧栏、隐藏面板等难拖拽状态。
- Computer Use 报超时、坐标失效或 “user is still interacting”。

纯 iOS 模拟器、Web 页面、或不需要运行应用的单元测试不属于本 Skill。若改动需要先补 AppKit 布局断言，可配合 `appkit-layout-tdd`。

## 铁律

1. **证据优先**：结论必须附窗口号、截图路径、测量值或 AX 状态。
2. **不代用户授权**：系统 TCC 弹窗只能由用户点“允许”或在系统设置中授权；不尝试绕过。
3. **点击前必须新截图**：不复用上一次调用里的坐标；截图、点击、复核放在同一次执行内。
4. **pt 与 px 分开**：Retina 截图通常是 2x；报告写清换算和裁剪原点。
5. **改默认值、重启前先记录**：验证结束恢复原值；只操作自己启动的验证实例。

## 流程

### 1. 确认实例与窗口

```bash
SKILL=~/.qoder-cn/skills/macos-app-ui-verification
pgrep -fl "<AppName>"
swift "$SKILL/scripts/window_capture.swift" list "<AppName>"
```

记录 **window id、owner、bounds（pt）**。若同时有 Desktop 副本和构建缓存副本，先确认要验证的是哪一个。

### 2. 截图（窗口被遮挡也能截）

```bash
swift "$SKILL/scripts/window_capture.swift" capture <window-id> /tmp/app-window.png
```

内部调用 `/usr/sbin/screencapture -x -o -l<window-id>`，只截目标窗口，不要求前台。脚本会打印图像尺寸和 `scale = 图像宽 / 窗口宽`（Retina 通常为 2）。

注意：窗口不在前台时红绿灯会变成灰色。截图仍有效，但 `--mode red` 会得到 `count=0`；要测红绿灯颜色需先激活窗口，或改测文字、图标。

- 图像全黑、只有壁纸或空白：检查“屏幕录制”权限、窗口是否最小化；先取消最小化或切到当前 Space。
- 需要看系统弹窗时截全屏：

```bash
swift "$SKILL/scripts/window_capture.swift" screen /tmp/screen.png
```

- 首次 `screencapture` 可能触发 TCC；让用户处理，不要重复重试。

### 3. TCC 弹窗与 Computer Use 超时

Computer Use 连续超时（例如两次 `Computer Use request timed out; outcome may be unknown`），且点击像被“吃掉”时，优先怀疑系统隐私弹窗（如“想访问「桌面」文件夹中的文件”“屏幕录制”“辅助功能”），而不是应用 bug。

- 应用自定义的跳过开关（例如 FlowFinder 的 `FF_SKIP_PERMISSION_GATE=1`）只跳过**应用自己的**权限门，挡不住 macOS TCC。
- 截全屏确认弹窗文案，然后把控制权交还用户；用户授权后重新取窗口状态。
- 不要在弹窗存在时循环重试点击，超时是预期结果。

### 4. 坐标点击纪律

Computer Use 的坐标来自**当前截图**。跨调用复用坐标会报：

`Screenshot coordinates require a current screenshot whose target window still belongs to the app and has unchanged geometry. Re-query get_app_state before retrying.`

在**同一个 node_repl cell** 内完成：

```js
// 函数名以当前 CUA 暴露的 API 为准
const state = await getAppState();      // 重新绑定窗口与元素
const shot = await getScreenshot();     // 本次点击的唯一坐标来源
await click({ x, y });                  // x/y 按 shot 的像素坐标
const after = await getScreenshot();    // 必须复核状态变化
```

- 有 AX 元素 ID 时优先按元素操作，坐标点击只作兜底。
- 点击未报错不等于成功；必须看 `after` 截图或 AX 状态。
- 截图被调用方缩放时，把坐标换算回工具声明的截图尺寸。

### 5. 让出控制权

报错 `The user is still interacting with '<AppName>'. Wait 5 seconds and retry.` 表示真人正在操作。

- 立即停止点击，不要循环抢占。
- 告知用户并等待；用户切走窗口后重新取状态，不沿用旧元素 ID。
- 期间可以先写文档、整理证据，不要为了截图去抢焦点。

### 6. 构造难拖拽的状态

分隔线、侧栏拖拽不稳定时，先试 AX 设置 splitter 值；仍失败再用应用自己的持久化键：

```bash
defaults read  <bundle-id> sidebar_width
defaults write <bundle-id> sidebar_width -int 180
# 退出并重启“你自己启动的”验证实例
osascript -e 'quit app "<AppName>"'   # 或只 kill 验证实例 pid
open -a "<path-to-app>"
```

- 写入前记录原值，截图后恢复（例如 206 → 180 → 206）并再次确认。
- 应用可能在退出时回写偏好；若写入被覆盖，先退出应用再 `defaults write`，最后启动。
- 重启会丢未保存状态；先确认没有未保存内容。
- 不关闭、不重启用户正在用的实例，除非用户明确同意。

### 7. 像素测量，不目测

```bash
swift "$SKILL/scripts/measure_centerline.swift" /tmp/app-window.png \
  --mode red --region 0,0,120,80 --scale 2
```

- `--mode red`：找红色像素包围盒（红绿灯）。
- `--mode dark` / `--mode light`：按亮度找文字、图标包围盒，`--threshold` 调阈值。
- `--region x0,y0,x1,y1` 用**图像像素**，只框一个控件；不要把图标和相邻标签框进来。
- 输出 `center_pt` 与 `absolute_pt`；`--origin x,y` 是裁剪区在窗口中的像素原点。

判定对齐时，对两个控件分别测量，比较它们到窗口顶或左边的同一边距。来源会话实测：红绿灯红色圆中心 17.5pt，活动标签文字中心 17.5pt，规范 18pt，误差 0.5pt。

常见错误：

- 全部返回 `count=0`：区域坐标、极性（深色文字或浅色文字）或裁剪原点错了；先缩小区域重测。红色扫描还要确认窗口在前台，否则红绿灯是灰色。
- 数值差一个 `scale`：忘了除 Retina 比例。
- 数值差一个裁剪偏移：把裁剪局部坐标当成了窗口绝对坐标；用 `--origin` 或先换算再加。

### 8. 收口

1. 改动后重新按窗口号截图，和基线对比。
2. 报告：窗口号、截图路径、测量值、AX 证据、仍未验证项。
3. 恢复默认值、窗口尺寸和侧栏宽度；退出自己启动的验证实例。
4. 按项目规范同步台账、交接文档；没有执行证据的项标“未验”。

## 故障对照表

| 现象 | 根因 | 处理 |
|---|---|---|
| `Computer Use request timed out` 连续出现 | 系统 TCC 弹窗吃掉点击 | 截全屏确认，交还用户授权 |
| `Screenshot coordinates require...` | 截图过期或窗口几何变化 | 同一 cell 内重新 state → screenshot → click |
| `The user is still interacting...` | 真人正在操作 | 停止重试，等待并重新取状态 |
| `screencapture -l` 得到空白、壁纸 | 无屏幕录制权限或窗口最小化 | 授权；取消最小化或切 Space |
| 像素扫描全 `count=0` | 区域、极性、原点错误 | 缩小区域，换 `dark/light`，核对 origin |
| 点击位置整体偏移 | pt/px 混用或截图被缩放 | 按截图尺寸换算坐标 |
| `defaults write` 后值被改回 | 应用退出时回写 | 先退出应用，再写入，再启动 |

更多细节见 [references/troubleshooting.md](references/troubleshooting.md)。

## 资源

- `scripts/window_capture.swift`：列出窗口、按窗口号截图、全屏截图。
- `scripts/measure_centerline.swift`：像素包围盒与中线测量（red/dark/light）。
- `references/troubleshooting.md`：错误原文、TCC 流程、坐标与裁剪偏移排查。
