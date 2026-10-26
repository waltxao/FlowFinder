# 隔离副本 UI 验证：失败模式与来源证据

来源：Qoder 会话 `8e8ea484-01b5-4565-8e7c-e1034f1d68a1`，包含 2026-10-21 18:28–18:32 的隔离副本验证和 2026-10-22 00:11–02:23 的桌面副本走查。以下命令、输出和错误文本均来自该会话转录；路径、PID 和构建号只是当时的实例，不要在新任务中直接复用。

## 1. 进程名歧义：副本和桌面版都叫 FlowFinder

**现象**

改了 Info.plist 的 `CFBundleName`，但 System Events 里的进程名仍是二进制名：

```text
75913 /private/tmp/FlowFinder-Phase2.app/Contents/MacOS/FlowFinder
FlowFinder
FlowFinder
```

两个进程都叫 `FlowFinder`。按 `process "FlowFinder"` 或 `tell application "FlowFinder"` 操作时，命中的可能是用户正在用的桌面副本。

**根因**

`CFBundleName` / `CFBundleDisplayName` 是显示名；System Events 的进程名来自可执行文件。不能把显示名当作进程定位依据。

**处理**

先用副本可执行路径取 PID，再按 `unix id` 操作：

```bash
pgrep -fl -- "/private/tmp/FlowFinder-Phase2.app/Contents/MacOS/FlowFinder"
ps -p 75913 -o pid=,command=
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is 75913)) to get {name, count of windows}'
```

新 Skill 使用 `every application process whose unix id is ...` 取 `item 1`，避免 `first ... whose` 的索引问题。

## 2. `first ... whose unix id` 报 `-1719`

**错误原文**

```text
execution error: “System Events”遇到一个错误：不能获得“application process 1 whose unix id = 49728”。无效的索引。 (-1719)
```

**处理**

- 等待进程完成 AX 注册后重试。
- 改用：

```applescript
tell application "System Events"
  set procs to every application process whose unix id is 49728
  if (count of procs) = 0 then return "no-process"
  set p to item 1 of procs
end tell
```

会话后续用 `every ... whose unix id is 50057` 成功拿到了进程。

## 3. `position` / `size` 返回 `missing value`

**输出**

```text
FlowFinder, missing value, missing value, 1
```

**处理**

改读 AX 属性：

```applescript
tell application "System Events"
  tell (item 1 of (every application process whose unix id is 49728))
    get {name of window 1, ¬
      value of attribute "AXPosition" of window 1, ¬
      value of attribute "AXSize" of window 1, ¬
      value of attribute "AXMain" of window 1}
  end tell
end tell
```

会话随后得到：

```text
FlowFinder, 311, 92, 856, 900, true
```

## 4. 激活后窗口几何变化，旧坐标失效

**输出**

激活前：`311, 92, 856, 900`  
激活后：`311, 92, 1609, 900`

**原因**

窗口可能处于单/双栏切换、布局动画或权限弹窗后的恢复过程。按旧尺寸截取会裁掉右侧内容，或截到目标窗口之外的区域。

**处理**

每次 `activate`、切模式、隐藏侧栏、弹窗关闭后都重新读取 `AXPosition` / `AXSize`，再执行 `screencapture -R`。

## 5. 坐标点击误伤：不要跨实例复用坐标

**经过**

第一次截图 `260,30,1400,900` 时出现 TCC 权限弹窗。助手尝试用 AppleScript 点「不允许」失败，随后用坐标点击弹窗按钮；点击后临时副本的几何从 `856×900` 变为 `1609×900`，并且出现了用户窗口/Qoder 被激活的迹象。转录无法确认点击最终落在哪个实例，但这正是「进程名歧义 + 跨实例坐标」的典型风险。

**处理**

- 不用上一个实例的坐标去点另一个实例。
- 先按 PID 确认窗口，再在同一轮内重新截图、取坐标、点击、复核。
- 能 AXPress 就不坐标点击。
- 权限弹窗无法通过 AX 找到按钮时，截全屏确认并交还用户，不要盲点。

## 6. 新 Bundle ID 触发新的 TCC 身份

**现象**

临时副本首次启动后出现文件夹访问权限弹窗，遮挡了顶栏截图。

**根因**

TCC 授权按 Bundle ID（以及签名身份）记录；换了 Bundle ID 就是新的授权主体，不会继承桌面副本的权限。

**处理**

- 不修改 TCC 数据库，不尝试绕过。
- 让用户点「允许」，或在确认不需要该权限时点「不允许」。
- 弹窗存在时先截全屏确认文案，不要循环点击或反复重试。
- 把「截图中有 TCC 弹窗」写进证据，不能当作干净的 UI 截图。

## 7. 权限弹窗按钮 `-1728`

**错误原文**

```text
execution error: “System Events”遇到一个错误：不能获得“button "不允许" of window 1 of process "FlowFinderPhase2"”。 (-1728)
```

**处理**

- 弹窗可能是 sheet，也可能属于另一个进程；按 PID 重新枚举窗口和 `sheet`。
- 仍找不到时，读取全屏截图，交还用户处理。
- 不要因为 AX 找不到按钮就改用未经验证的坐标点击。

## 8. 快捷键被前台应用抢走

**经过**

向临时副本 PID 发送 `⌃⌘F` 后，截图显示的是 Qoder，窗口几何仍是普通窗口；最终报告记录「全屏只做了几何单测（实机快捷键被 Qoder 抢走）」。

**处理**

- 发送快捷键前先 `activate`，并读取 `frontmost` 确认目标在前台。
- 菜单快捷键不可靠时，优先 AXPress 具体控件。
- 无法稳定驱动时，把该项标为「未实机验证」，不要用单测冒充实机结果。

## 9. `screencapture -l` 空白或过期

**经过**

会话早期执行 `screencapture -x -l 7938 /tmp/flowfinder-window.png` 没有产出可用截图；随后改用全屏截图和 `-R` 区域截图。转录没有单独确认根因，屏幕录制权限不足、window id 过期、窗口最小化都可能。

**处理**

- 先确认屏幕录制权限和 window id 仍有效。
- 没有可靠 window id 时用 `-R` + 新鲜 AX 几何。
- 能拿到稳定 window id 时，优先 `window_capture.swift` 按窗口号截图。

## 10. 收尾：只结束自己的临时 PID

**风险**

`pkill -f "<AppName>"` 会同时杀掉用户的桌面副本和临时副本。

**处理**

```bash
cmd=$(ps -p "$PID" -o command= 2>/dev/null || true)
case "$cmd" in
  "$APP_COPY/Contents/MacOS/"*) kill "$PID" ;;
  *) echo "拒绝结束 pid $PID：$cmd" >&2 ;;
esac
```

先 `kill` 并等待退出；不要直接用 `kill -9`。删除临时目录时也要带 `/tmp/macos-ui-verify.*` 守卫。

## 11. 桌面副本实测：测试者启动 vs 用户正在使用

**来源**：2026-10-22 的 FlowFinder 实机走查（0.8.0-26102209）。用户要求“继续，完成后进行实机测试”；执行者选择桌面副本，记录 PID 49151/49308、窗口 1400×900，并在走查中重启过测试实例。

**风险**

- 桌面副本可能承载用户真实偏好、最近路径和 TCC 授权；改设置或路径会直接影响用户。
- 走查中设置页三个开关被外部改动，Computer Use 多次判定 `user changed`，转录无法确认来源。
- 结束后执行者恢复了左右栏路径和“移动前确认”开关，桌面副本保持运行（PID 49308，RSS 188MB）。

**处理**

- 先确认副本是测试者启动还是用户正在使用。前者可重启，后者只读。
- 改偏好前 `defaults read "$BUNDLE_ID"` 全量留档，只逐键恢复本次改过的键。
- 不要用 `defaults import` 整域覆盖；测试期间用户可能改了别的键。
- 用户介入或 CU 连续报 `user changed` 时停止改动，保留用户状态。

## 12. Computer Use 状态拦截：user changed / No active app state

**错误原文**

```text
[node_repl error] Error: The user changed 'FlowFinder'. Re-query the latest state with `get_app_state` before sending more actions.
[node_repl error] Error: No active app state. Call get_app_state first.
[node_repl error] Error: Screenshot coordinates require a current screenshot whose target window still belongs to the app and has unchanged geometry. Re-query get_app_state before retrying.
[node_repl error] Error: No visible target window for coordinate action. Re-query get_app_state after the target window is visible.
```

**根因**

- `user changed`：真人或外部进程改了 App 状态。
- `No active app state`：状态在 node_repl cell 之间丢失，后续调用没有当前基线。
- 坐标错误：截图过期、窗口几何变化或窗口不可见。

**处理**

- 同一 cell 内重新 `get_app_state`，拿到完整树后再操作；返回出现 `New accessibility baseline: discard all previous element ID references` 才说明基线已更新。
- 丢弃旧元素 ID，按新树编号操作。
- 坐标点击只用本轮截图，并在同一 cell 内点击、复核。
- 连续 `user changed` 视为真实用户操作，停止并询问；不要判成应用 bug。
- 会话转录没有保留工具入参，`disableDiffing` 参数名未在原文中出现；可核实的是重新调用 `get_app_state` 会返回完整基线。若当前 CUA 版本支持关闭 diff 的参数，再显式使用。

## 13. 5000 行全量 AX 枚举：RSS 183 → 792/893MB

**实测**

- 5000 项目录首屏 500 条约 0.46s，窗口同步就绪；枚举前 RSS 约 236MB。
- 不调用 AX 时，重启后静置 RSS 稳定在 183MB（11s/31s 两次采样）。
- 一次 AX 全量枚举后 RSS 升到 792MB，并超过 10s 无响应；后续记录为 183→792/893MB。
- 根因：表格把 5000 行全部物化为辅助功能元素；直接截断行索引会破坏 VoiceOver 的行索引语义。

**处理**

- 只查可见行、当前选中行，或按 role/description/help 定位；不要对数千行表格跑 `entire contents`。
- 必须全量枚举时，先在可丢弃副本上采样 `ps -o rss= -p "$PID"`，记录枚举前后与耗时。
- 超过基线 2 倍或 500MB 即停止，重启副本，把该项标为未验。
- 这是被测应用的 AX 行虚拟化问题，不是测试脚本可以“修好”的；不要在同一实例上反复触发。

## 14. 测试后偏好恢复与缺少 ⌘⇧G

**观察到的键（恢复前）**

```text
{
    "last_active_pane" = left;
    "last_left_path" = "/tmp/ff-ax-5000";
    "last_right_path" = "/tmp/ff-ax-5000";
    "onboarding_completed" = 1;
    "single_pane_mode" = 0;
    "startup_location" = 0;
}
```

**恢复**

- 走查中通过 `defaults` 打开“移动前确认”开关；结束后恢复左右栏路径到桌面、关闭该开关。
- 恢复后复核 `defaults read`、PID 和窗口几何；报告写“已恢复/未恢复”。
- 应用退出时可能回写偏好：先退出副本，再 `defaults write`，再启动。

**缺少 ⌘⇧G**

- 该版本没有“前往文件夹”（⌘⇧G）；CU 在导航点击上连续超时。
- 执行者改用 App 内置的会话恢复直接打开 `/tmp/ff-ax-5000`，也用面包屑逐级进入。
- 结论：标准快捷键缺失或 CU 无法驱动导航时，优先用 App 内部导航，不要盲点坐标；仍不行才在征得同意后用 `last_left_path`/`last_right_path` 重启进入。

## 已验证的成功路径

会话中实际跑通的命令序列（路径为当时实例）：

```bash
cp -R "/tmp/flowfinder-xctest-derived/Build/Products/Debug/FlowFinder.app" /tmp/FlowFinder-Phase2.app
plutil -replace CFBundleIdentifier -string com.flowfinder.native.phase2 /tmp/FlowFinder-Phase2.app/Contents/Info.plist
plutil -replace CFBundleName -string FlowFinderPhase2 /tmp/FlowFinder-Phase2.app/Contents/Info.plist
codesign --force --deep --sign - /tmp/FlowFinder-Phase2.app
open /tmp/FlowFinder-Phase2.app
```

结果：

- 重签：`sign=0`
- 窗口：`260, 30, 1400, 900`
- 截图：`/tmp/ff-phase2-dual.png`，2800×1800（Retina 2x），但画面中有 TCC 权限弹窗
- 按 PID `75913` 定位后：`AXPosition/AXSize = 311, 92, 856, 900`，激活后变为 `311, 92, 1609, 900`
- 干净双栏截图：`/tmp/ff-phase2-current.png`，3218×1800
- 隐藏侧栏截图：`/tmp/ff-phase2-hidden-sidebar.png`，窗口 `311, 92, 1609, 900`；转录记录文件 720,624 bytes，未单独记录图像尺寸
- 清理：`kill 75913`

**结论的准确边界**

会话最终报告原文：「双栏/隐藏侧栏实机截图均符合 C2；全屏只做了几何单测（实机快捷键被 Qoder 抢走）。」

因此：

- 不能把自动摘要里的「1400 双栏/隐藏侧栏证据」理解为两张干净的 1400 截图；1400 那张有 TCC 弹窗，干净的双栏和隐藏侧栏证据是 1609×900 的。
- 全屏只做了几何单测，没有实机通过。
- 来源会话没有用户对「隔离副本」的逐字纠正；可核实的纠正是助手发现按进程名误点后改为按 PID。
- 2026-10-22 的桌面副本走查中，用户只要求“实机测试”，没有逐字指定“桌面副本”；执行者选择了测试者启动的桌面副本。新 Skill 因此要求桌面副本模式先确认归属和同意。

## 安全边界

- 不退出、不覆盖、不重签用户的 App。
- 不修改 TCC 数据库，不伪造权限。
- 不默认复制用户的偏好、容器或数据库；需要时先征得同意。
- 桌面副本改偏好前先留档，测后逐键恢复；用户正在使用的副本只读。
- 大列表不做全量 AX 枚举；必须诊断时先采样 RSS，异常即重启副本。
- ad-hoc 签名只用于本机验证，不用于分发。
- 只操作自己创建的临时目录和临时 PID。
