---
name: macos-isolated-app-ui-verification
description: "在 macOS 上验证原生 App UI：默认用独立 Bundle ID 的临时副本（ad-hoc 重签、按 PID 定位 AX、AXPosition/AXSize + screencapture -R 取证）；用户明确要求时，也可对桌面副本做非破坏、可恢复的实测（记录 PID、窗口和偏好，测后恢复）。覆盖 Computer Use 的 user changed、No active app state、坐标失效恢复，大列表 AX 枚举的 RSS 采样，以及测试后 last_left_path/right_path 与设置开关的恢复。适用于多副本同名或同 Bundle ID、需要新鲜默认值、固定窗口尺寸截图、坐标点击可能误伤用户窗口，或需要在真实偏好下验证的场景。不适用于 iOS 模拟器、Web 页面或只需单元测试的场景。"
---

# macOS 隔离副本 UI 验证

默认在用户正在使用 App 时，用独立 Bundle ID 的临时副本做真机 UI 验证；按 PID 定位 AX，用 AX 几何加 `screencapture -R` 取证，全程不退出、不覆盖、不抢用户实例。用户明确要求时，才切换到桌面副本模式，并先记录、测后恢复偏好。

## 适用与不适用

适用：

- 用户已打开桌面副本或 Xcode 构建，不能退出、覆盖或抢焦点。
- 系统里有多个同名进程或同 Bundle ID 副本，按名字操作会命中错误实例。
- 需要新鲜 UserDefaults，或需要避开 App 的单实例提示。
- 需要固定窗口尺寸、隐藏侧栏、窄侧栏、单/双栏等状态截图。
- 需要坐标点击，但存在误点用户窗口的风险。
- 用户明确要求直接验证桌面副本，或问题必须依赖真实偏好、TCC 授权、容器数据才能复现。
- 需要检查数千行列表的 AX/VoiceOver 行为与内存占用。

不适用：

- 纯单元测试、代码审查、iOS 模拟器、Web 页面。
- 只需读取一次已有窗口截图且不需要交互：优先用 `macos-app-ui-verification`。
- 需要复现依赖用户真实偏好或权限的问题：隔离副本默认是干净状态，先征得同意再导入状态，否则结论可能不成立。
- 用户正在使用桌面副本且不同意重启或改偏好：只能只读取证；需要交互的项标为未验，不要为了测试抢占实例。

## 铁律

1. 先记录用户实例的 PID、路径、窗口几何；不退出、不覆盖、不 `pkill` 同名进程。
2. 默认只操作自己用 `mktemp -d` 创建的 `/tmp` 副本；桌面副本按第 8 条执行。
3. 进程名不可信；PID 必须和副本可执行路径同时核对。
4. 每次激活、切模式、改侧栏、弹 TCC 后重新取 AX 几何；不复用旧坐标。
5. 截图必须实际读取并记录尺寸、遮挡物；文件存在不等于验证通过。
6. TCC 弹窗只由用户授权或明确选择“不允许”，不绕过。
7. ad-hoc 签名只用于本机验证，不用于分发。
8. 桌面副本只在用户明确要求或同意时操作；先确认是谁启动的，记录偏好基线，测后逐键恢复并复核。
9. 大列表默认不做全量 AX 枚举；必须诊断时先采样 RSS，在可丢弃副本上做一次，异常即停止并重启。

## 与已有 Skill 的分工

- 通用窗口截图、像素中线测量、Computer Use 坐标纪律、`The user is still interacting`、TCC 超时处理：用 `macos-app-ui-verification`。
- 本 Skill 只补：隔离/桌面两种副本模式、Bundle ID 重签、PID 定位、AX 几何加 `-R` 取证、`user changed` / `No active app state` 恢复、大列表 RSS 采样、测试后偏好恢复。
- 如果能稳定拿到 CGWindowID，优先用 `macos-app-ui-verification` 的 `window_capture.swift` 按窗口号截图；`-R` 是拿不到可靠 window id 时的兜底。

## 流程

### 0. 前置记录

```bash
pgrep -fl "<BinaryName>"
ps -p <pid> -o pid=,command=
```

记录哪些进程不是自己启动的。后续只操作临时副本；用户实例只读。

同时记录用户实例的窗口几何。示例中的 `USER_PID` 是占位符，替换为实际数字：

```applescript
tell application "System Events"
  tell (item 1 of (every application process whose unix id is USER_PID))
    set pos to value of attribute "AXPosition" of window 1
    set sz to value of attribute "AXSize" of window 1
    return {pos, sz}
  end tell
end tell
```

结束时用同样的方法复核 PID、路径和几何。用户自己移动窗口不算我方改动。

### 1. 创建隔离副本

```bash
VERIFY_DIR=$(mktemp -d /tmp/macos-ui-verify.XXXXXX)
APP_COPY="$VERIFY_DIR/App.app"
cp -R "/path/to/Built.app" "$APP_COPY"

VERIFY_ID="com.example.app.verify.$(date +%s)"
plutil -replace CFBundleIdentifier -string "$VERIFY_ID" "$APP_COPY/Contents/Info.plist"
plutil -replace CFBundleName -string "AppVerify" "$APP_COPY/Contents/Info.plist"
plutil -p "$APP_COPY/Contents/Info.plist" | grep -E "CFBundleIdentifier|CFBundleName"

codesign --force --deep --sign - "$APP_COPY"
codesign --verify --deep "$APP_COPY"
```

- 改 Info.plist 后必须重签，否则可能拒绝启动。
- `CFBundleName` 通常存在；若 `plutil` 报 key 不存在，改用 `-insert`。
- 改 `CFBundleName` / `CFBundleDisplayName` 只影响显示，不保证进程名改变。不要据此定位进程。
- `CFBundleDisplayName` 不是所有 Info.plist 都有；需要时先用 `plutil -p` 确认，已有则 `-replace`，没有则 `-insert`。
- 新 Bundle ID 意味着新的 UserDefaults 和 TCC 身份；不要假设继承用户的权限。
- 沙盒应用改 Bundle ID 可能换容器；先确认不会影响用户数据。
- 需要复现用户偏好时，先征得同意，再导出/导入，不要默认复制用户数据。导入前先退出副本，避免偏好缓存覆盖：

```bash
defaults export "$ORIG_BUNDLE_ID" /tmp/orig-defaults.plist
defaults import "$VERIFY_ID" /tmp/orig-defaults.plist
```

### 1B. 桌面副本模式（仅明确要求）

默认仍用隔离副本。只有用户明确说“直接测桌面副本/当前运行的 App”，或问题依赖真实偏好、TCC 授权、容器数据且用户同意时，才进入本模式。

先分清两种桌面副本：

- **测试者启动**：可以重启、可以改偏好；测后必须恢复。
- **用户正在使用**：只读取证；不退出、不重启、不改偏好；需要交互时先征得同意。

前置记录：

```bash
APP_PATH="/Applications/App.app"          # 替换为实际路径
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")
pgrep -fl -- "$APP_PATH/Contents/MacOS/"   # 逐个核对路径后取 PID
ps -p "$PID" -o pid=,rss=,command=
defaults read "$BUNDLE_ID" > /tmp/verify-defaults-before.txt
```

- 同时记录窗口几何（第 3 节）和版本号。
- 偏好基线至少覆盖：`last_left_path`、`last_right_path`、单/双栏、侧栏显隐、确认开关。只恢复本次改过的键。
- 不要用 `defaults import` 整域覆盖；测试期间用户可能改了别的键。必须整域恢复时，先确认没有并发用户改动。
- 应用可能在退出时回写偏好；改偏好后先退出副本，再写入，再启动。

```bash
defaults write "$BUNDLE_ID" last_left_path -string "/tmp/ff-ax-5000"
osascript -e "tell application id \"$BUNDLE_ID\" to quit"
open -a "$APP_PATH"
```

测试后逐键恢复并复核：

```bash
defaults write "$BUNDLE_ID" last_left_path -string "$ORIG_LEFT"
defaults write "$BUNDLE_ID" last_right_path -string "$ORIG_RIGHT"
defaults write "$BUNDLE_ID" <toggle-key> -bool "$ORIG_BOOL"
osascript -e "tell application id \"$BUNDLE_ID\" to quit"
open -a "$APP_PATH"
defaults read "$BUNDLE_ID" last_left_path
defaults read "$BUNDLE_ID" last_right_path
```

- 原值从基线文件读取，不要凭记忆。
- 恢复后复核 PID、窗口几何和关键键值；报告写“已恢复/未恢复”。
- 测试期间用户操作了 App，或 Computer Use 连续报 `user changed`：停止改动，保留用户的新状态，询问后再继续。
- 桌面副本可能被其他构建覆盖；覆盖前确认目标路径和版本号，避免测到旧产物。
- 激活和截图沿用第 4 节，把 `$VERIFY_ID` 换成 `$BUNDLE_ID`，不要用 `open -n` 再启一个实例。
- 证据表用桌面副本的 `bundle_id` / `pid`；`user_instance_unchanged` 改写为“偏好已恢复、实例保留”。

缺少“前往文件夹”（⌘⇧G）或 CU 无法驱动导航时：

- 优先用 App 内置的会话恢复/最近位置进入目标目录。
- 其次用面包屑逐级进入。
- 都没有时，才在征得同意后用 `last_left_path`/`last_right_path` 重启进入；不要盲点坐标。

### 2. 启动并按路径取 PID

本节用于隔离副本；桌面副本不执行 `open -n`，按 1B 记录并核对 PID。

```bash
open -n "$APP_COPY"
sleep 1

PID=""
for p in $(pgrep -f -- "$APP_COPY/Contents/MacOS/"); do
  cmd=$(ps -p "$p" -o command= 2>/dev/null || true)
  case "$cmd" in
    "$APP_COPY/Contents/MacOS/"*) PID="$p"; break ;;
  esac
done

[ -n "$PID" ] || { echo "未找到副本进程" >&2; exit 1; }
ps -p "$PID" -o pid=,command=
```

必须确认 `command` 以副本可执行路径开头。不要用以下方式定位或关闭：

- `pgrep -x "<AppName>"`
- `tell application "<AppName>" ...`
- `process "<AppName>"`
- `pkill -f "<AppName>"`

`open -n` 仍可能受 LaunchServices 缓存影响；以实际 PID 和路径为准。若出现多个候选 PID，逐个核对路径，不要取第一个就操作。若按路径完全找不到，改用 `ps -axo pid=,command= | grep -F "$APP_COPY/Contents/MacOS/"` 人工核对；不要退回按名字杀进程。

### 3. 按 PID 读取窗口几何

示例中的 `PID` 是占位符，替换为实际数字：

```applescript
tell application "System Events"
  set procs to every application process whose unix id is PID
  if (count of procs) = 0 then return "no-process"
  set p to item 1 of procs
  set out to ""
  repeat with i from 1 to count of windows of p
    set w to window i of p
    try
      set pos to value of attribute "AXPosition" of w
      set sz to value of attribute "AXSize" of w
      set out to out & i & tab & (name of w) & tab & (item 1 of pos) & tab & (item 2 of pos) & tab & (item 1 of sz) & tab & (item 2 of sz) & tab & (value of attribute "AXMain" of w) & linefeed
    on error errMsg
      set out to out & i & tab & "ERROR " & errMsg & linefeed
    end try
  end repeat
  return out
end tell
```

- 用 `every ... whose unix id`，不要用 `first ... whose`；进程尚未注册到 AX 时后者可能报 `-1719`。
- `position` / `size` 返回 `missing value` 时，改读 `AXPosition` / `AXSize`。
- 多窗口时选 `AXMain = true` 且标题匹配的窗口；不要默认 `window 1`。
- 记录的是屏幕坐标 pt，原点在左上角。
- 在 shell 中解析每个窗口的字段：`IFS=$'\t' read -r WIN_INDEX WIN_NAME X Y W H IS_MAIN <<< "$WINDOW_LINE"`；先确认 `IS_MAIN` 为 `true` 且标题匹配，再使用 `X/Y/W/H`。

### 4. 激活并截图

```bash
osascript -e "tell application id \"$VERIFY_ID\" to activate"
sleep 0.5

# 期望返回 true；false 时不要截图
osascript <<APPLESCRIPT
tell application "System Events"
  return frontmost of (item 1 of (every application process whose unix id is $PID))
end tell
APPLESCRIPT

# 重新读取目标窗口的 AXPosition / AXSize，赋给 X/Y/W/H 后再取整
X=$(printf '%.0f' "$X")
Y=$(printf '%.0f' "$Y")
W=$(printf '%.0f' "$W")
H=$(printf '%.0f' "$H")
screencapture -x -R "$X,$Y,$W,$H" /tmp/verify.png
sips -g pixelWidth -g pixelHeight /tmp/verify.png
```

- AX 几何用 pt，`-R` 也用 pt；Retina 输出通常是 2x。
- `-R` 截取该区域最上层的内容。先激活目标并确认 `frontmost` / `AXMain`，否则会截到用户窗口、Qoder 或 TCC 弹窗。
- 不要复用上一步的几何。激活、动画、切模式、弹窗都会改变窗口尺寸；实测出现过 `856×900 → 1609×900`。
- `screencapture -l <windowid>` 在权限不足或 id 过期时会空白；没有可靠 window id 时用 `-R`，或改用 `window_capture.swift`。
- 截图后必须读取图片，记录实际尺寸和遮挡物。目标窗口被其他窗口压住时，这张图不算干净证据。
- 多显示器 / 其他 Space：AX 坐标是全局屏幕坐标，`screencapture -R` 在副屏或非当前 Space 可能截错。先把窗口移到主屏当前 Space，或标为未验。

### 5. 驱动交互

- 优先在 PID 对应的窗口内查找 AX 元素并执行 AXPress；按 role、description、help 过滤，避免对整个文件列表跑巨大的 `entire contents` 循环。
- 菜单快捷键只发给已确认 `frontmost` 的目标。System Events 的 `keystroke` 可能落到 Qoder 等前台应用；先 activate 并验证，失败就改用 AXPress。
- 坐标点击只作兜底：同一轮内重新截图、取坐标、点击、复核；坐标不得跨实例或跨截图复用。
- 每次状态变化后重新取 AX 几何：隐藏侧栏、单/双栏、窗口动画、权限弹窗、全屏切换。

Computer Use 报以下错误时，不要原样重试：

```text
The user changed '<App>'. Re-query the latest state with `get_app_state` before sending more actions.
No active app state. Call get_app_state first.
Screenshot coordinates require a current screenshot whose target window still belongs to the app and has unchanged geometry.
No visible target window for coordinate action. Re-query get_app_state after the target window is visible.
```

处理：

1. 在同一个 node_repl cell 内重新调用 `get_app_state`。若当前 CUA 版本支持关闭 diff 的参数（如 `disableDiffing`），设为 true 强制返回完整树；返回中出现 `New accessibility baseline: discard all previous element ID references` 才说明拿到了新基线。
2. 丢弃旧元素 ID，按新树的 AX 索引/元素 ID 操作；不要沿用 diff 里的编号。
3. 坐标点击只用本轮截图，并在同一 cell 内点击、复核。
4. `user changed` 连续出现时，视为真人或外部进程改了 App 状态：停止操作，记录观察，不要判成应用 bug。
5. `No active app state` 通常是跨 cell 丢失状态；不是权限问题，不要重开 App。

大列表 AX 枚举：

- 5000 行级表格不要跑 `entire contents` 或递归遍历全部行；只查可见行、当前选中行，或按 role/description/help 定位。
- 必须做全量枚举诊断时，在可丢弃副本上先采样：

```bash
ps -o rss= -p "$PID"        # 枚举前
# 执行一次受控枚举，记录耗时
ps -o rss= -p "$PID"        # 枚举后
```

- 实测：5000 行表格正常 RSS 约 183MB，一次全量 AX 枚举后升到 792–893MB，并可能 10s 无响应。超过基线 2 倍或 500MB 即停止，重启副本，把该项标为未验。
- 这是被测应用的 AX 行虚拟化问题；不要用截断行索引来“修复”它，也不要在同一实例上反复触发。

### 6. 收尾与证据

```bash
cmd=$(ps -p "$PID" -o command= 2>/dev/null || true)
case "$cmd" in
  "$APP_COPY/Contents/MacOS/"*) kill "$PID" ;;
  *) echo "拒绝结束 pid $PID：$cmd" >&2 ;;
esac

case "$VERIFY_DIR" in
  /tmp/macos-ui-verify.*) rm -rf "$VERIFY_DIR" ;;
  *) echo "拒绝删除 $VERIFY_DIR" >&2 ;;
esac
```

桌面副本模式不要跑上面的 `kill` / `rm -rf`：副本是用户的运行实例，测后保留，只恢复偏好。只有测试者启动且用户同意关闭时才退出。

报告证据表：

```text
source_app:
verify_app:
bundle_id:
pid:
window:
AXPosition/AXSize:
screenshot:
image_dimensions:
observed:
unverified:
user_instance_unchanged: yes/no
```

`user_instance_unchanged` 至少核对 PID 和可执行路径；窗口几何由用户移动改变时，注明是用户操作导致的差异。

## 故障对照表

| 现象 | 根因 | 处理 |
|---|---|---|
| 按进程名操作命中用户实例 | 副本二进制进程名与桌面版相同；`CFBundleName` 不改变进程名 | 取 PID，核对副本路径；所有 AX 操作按 `unix id` |
| `first application process whose unix id is ...` 报 `-1719` | 进程尚未注册到 AX，或 `first ... whose` 不稳定 | 用 `every ... whose` 取 `item 1`；等待后重试 |
| `position` / `size` 返回 `missing value` | 窗口不响应普通 AppleScript 属性 | 改读 `AXPosition` / `AXSize` |
| 激活后窗口尺寸变化 | 动画、模式切换、权限弹窗 | 每次变化后重新取几何；重新截图 |
| 截图截到用户窗口或 Qoder | `-R` 取区域最上层；目标未激活 | 先 activate 并验证 `frontmost`；必要时改用窗口号截图 |
| 新副本弹出文件夹/屏幕录制权限 | 新 Bundle ID 是新的 TCC 身份 | 记录弹窗，交还用户授权或选择“不允许”；不绕过 |
| `button "不允许" of window 1` 报 `-1728` | 弹窗不在该窗口 AX 子树，或进程名命中了别的副本 | 按 PID 重新枚举窗口和 sheet；找不到就截图交还用户，不盲点坐标 |
| 快捷键在错误 App 生效 | 按键发给了前台应用 | 先确认 `frontmost`；优先 AXPress |
| `screencapture -l` 空白 | 屏幕录制权限、window id 过期或窗口最小化 | 授权、恢复窗口、换新 window id，或改用 `-R` |
| 结束进程后用户 App 也退出 | 按名字杀进程或 PID 未核对 | 只 kill 路径核对通过的临时 PID |
| CU 报 `The user changed ...` | 真人或外部进程改了 App 状态 | 停止重试；同 cell 重取完整状态；连续出现则记录并询问 |
| CU 报 `No active app state` | 跨 cell 丢失状态 | 同 cell 先 `get_app_state` 再操作；不要重开 App |
| CU 报坐标失效或无目标窗口 | 截图过期、窗口几何变化或窗口不可见 | 同轮重取 state + screenshot + click；不跨调用复用坐标 |
| 大列表枚举后 RSS 暴涨或卡死 | 全量 AX 枚举把行全部物化 | 只查可见行；先采样 RSS；异常重启副本并标未验 |
| 测试后偏好未恢复 | 应用退出回写、整域 import 覆盖或凭记忆写回 | 逐键 write、退出后写入、重启后 `defaults read` 复核 |

更完整的错误原文、来源会话证据和已核实边界见 [references/failure-modes.md](references/failure-modes.md)。

## 验收清单

- [ ] 用户实例 PID、路径在操作前后一致，未被退出或覆盖。
- [ ] 临时 PID 的 `command` 指向副本可执行路径。
- [ ] 截图前重新读取了目标窗口的 AX 几何。
- [ ] 截图已实际读取，尺寸、遮挡物、观察结果已记录。
- [ ] TCC / 权限弹窗已记录，未绕过。
- [ ] 桌面副本模式已确认归属；偏好基线已记录，测后逐键恢复并复核。
- [ ] CU 状态拦截已按同 cell 重取完整状态处理，未沿用旧 ID。
- [ ] 大列表未做全量枚举；若做了受控诊断，已采样前后 RSS 并标为未验。
- [ ] 测试期间用户的改动未被覆盖。
- [ ] 临时进程已退出，临时目录已清理。
- [ ] 未验项已明确写出，没有用“截图存在”代替结论。
