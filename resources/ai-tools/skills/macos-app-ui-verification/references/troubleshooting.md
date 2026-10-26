# macOS 真机 UI 验证：故障排查

## 错误原文与处置

### 1. Computer Use 连续超时

```
[node_repl error] Error: Computer Use request timed out; outcome may be unknown, observe before retrying
```

先不要重试。连续两次出现，且窗口截图正常、应用进程存在时，优先检查系统隐私弹窗。

常见弹窗：

- `<App> 想访问「桌面」文件夹中的文件`
- `<App> 想要录制此电脑的屏幕`
- `<App> 想要控制此电脑`

处理：

1. `swift scripts/window_capture.swift screen /tmp/screen.png` 截全屏确认弹窗。
2. 把控制权交还用户，让用户点“允许”或在“系统设置 > 隐私与安全性”中授权。
3. 用户确认后重新 `get_app_state`，不要沿用旧元素 ID。

`FF_SKIP_PERMISSION_GATE=1` 这类开关只跳过应用自己的启动权限门，无法绕过 macOS TCC。不要用 `tccutil`、修改数据库或伪造点击去绕过。

### 2. 截图坐标失效

```
[node_repl error] Error: Screenshot coordinates require a current screenshot whose target window still belongs to the app and has unchanged geometry. Re-query get_app_state before retrying.
```

根因：坐标来自上一次调用的截图，或窗口在两次调用之间改变了尺寸、位置、焦点。

处理：在同一个 node_repl cell 内重新取状态和截图，再点击：

```js
const state = await getAppState();
const shot = await getScreenshot();
await click({ x, y });
const after = await getScreenshot();
```

不要用「重新截一张图，然后在下一次工具调用里点击」的方式跨调用传递坐标。

### 3. 真人正在操作

```
[node_repl error] Error: The user is still interacting with '<AppName>'. Wait 5 seconds and retry.
```

根因：用户正在使用应用，Computer Use 主动让出控制。

处理：

- 停止点击和重试，不要与用户抢鼠标。
- 告知用户当前验证停在哪一步，等待用户空闲。
- 恢复后重新取状态，旧元素 ID 可能已失效。
- 等待期间可以写台账、整理已有截图，不要为了截图把应用强行拉到前台。

### 4. 窗口截图空白或只有壁纸

可能原因：

- 当前进程没有“屏幕录制”权限。
- 窗口已最小化。
- 窗口在当前 Space 之外，或应用使用了受保护的图层。

处理：

- 首次运行时可能弹出授权；交给用户处理。
- 取消最小化，或让用户把窗口切到当前 Space。
- 用 `window_capture.swift list` 确认 window id 仍在、bounds 非零。
- 不要用全屏截图裁切代替窗口截图来规避权限；先解决权限。

### 5. 像素扫描没有结果

`count=0` 或旧脚本返回 `-1`：

- `--region` 超出了图像尺寸，或框到了空白区域。
- 极性反了：浅色背景上的深色文字用 `dark`，深色背景上的浅色文字用 `light`。
- 颜色规则不匹配：红绿灯是渐变红，底部像素的绿色通道可能到 158；用 `r >= 200 && r - g >= 70 && r - b >= 70`，既覆盖渐变又排除橙色（橙色的 `r - g` 通常约 66）。
- 文字抗锯齿导致边缘像素亮度偏高；适当提高 `--threshold`。
- 区域里混入了图标、相邻标签、分隔线，包围盒中心被拉偏。
- 窗口不在前台：红绿灯会变成灰色，`--mode red` 必然为 0。先激活窗口（征得用户同意），或改测标签文字。
- 需要调阈值时，用 `--mode probe --region x0,y0,x1,y1` 打印每个像素的 RGB，再决定颜色规则。

### 6. 数值差一个裁剪偏移

来源会话中的真实例子：

- 第一次扫描得到红绿灯中心 17.5，但标签文字中心 86.5，看起来没有对齐。
- 原因是文字区域的裁剪原点没有参与换算；把裁剪局部坐标当成窗口绝对坐标后，86.5 减掉裁剪偏移才等于 17.5。
- 修正后两者都是 17.5pt，规范是 18pt，误差 0.5pt。

规则：

```
窗口绝对 pt = (裁剪局部 px + 裁剪原点 px) / scale
```

用 `--origin x,y` 传入裁剪原点，直接看 `absolute_pt`。不要手工在两次测量里用不同的基准。

### 7. Retina 比例混淆

- `screencapture` 在 Retina 上通常输出 2x 像素；窗口 bounds 是 pt。
- `scale = 图像宽 / 窗口宽`，不要假设永远是 2。
- 点击坐标要用截图工具声明的截图尺寸；如果调用方缩放了图片，先把坐标换算回原始截图尺寸。
- 报告里写清 `px` 和 `pt`，例如“bbox 32..39 px，中心 17.75 pt”。

### 8. 默认值写入后被应用改回

应用可能在退出时把当前窗口状态写回 `UserDefaults`。正确顺序：

```bash
osascript -e 'quit app "<AppName>"'    # 只退出自己启动的验证实例
defaults write <bundle-id> sidebar_width -int 180
open -a "<path-to-app>"
# 截图、测量、记录
defaults write <bundle-id> sidebar_width -int 206
osascript -e 'quit app "<AppName>"'
open -a "<path-to-app>"
```

注意：

- 先 `defaults read` 记录原值。
- 只操作自己启动的验证实例；用户正在用的副本不要动。
- 重启前确认没有未保存内容。
- 结束后用 `defaults read` 和截图双重确认已恢复。

## 验证清单

- [ ] 确认了应用进程与 `.app` 路径（Desktop 副本还是构建缓存）。
- [ ] 记录了 window id、bounds、截图路径。
- [ ] 截图尺寸与窗口 bounds 的 scale 已计算。
- [ ] 每次坐标点击都在同一 cell 内先取新截图。
- [ ] 遇到 TCC 或真人操作时已让出控制，没有循环抢点。
- [ ] 像素测量给出了 bbox、center、绝对 pt 和裁剪原点。
- [ ] 对齐结论由两个独立测量相互印证，不是目测。
- [ ] 默认值、窗口尺寸、侧栏宽度已恢复。
- [ ] 未验证项明确标注为“未验”。
