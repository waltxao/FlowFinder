# AppKit 实机验证隔离配方

目标是：在不打扰用户实例、不污染用户默认值的前提下，拿到可复核的窗口、AX 和截图证据。命令中的 `<AppName>`、`<bundle-id>`、`<PID>`、`<path-to-app>` 都是占位符。

如果环境已安装 `macos-isolated-app-ui-verification`，优先使用它的完整清单和故障表；本文件只保留本 Skill 需要的最小配方，避免把两套隔离流程混用。

## 1. 盘点实例与副本

```bash
pgrep -fl "<AppName>"
mdfind "kMDItemCFBundleIdentifier == '<bundle-id>'"
```

记录每个候选的路径、版本、PID。优先验证明确的那一份（桌面副本、构建缓存副本或自己启动的临时副本），不要用“看起来最新”猜。

如果存在同 Bundle ID 的多个 `.app`，先决定验证哪一个；不要直接 `open -a "<AppName>"`，它可能激活另一个实例。

## 2. 启动独立 Bundle ID 副本

用于“已有实例在跑”“需要干净默认值”“同名进程导致 AX 命中错误窗口”的场景。

```bash
APP_SRC="/path/to/Build/Products/Debug/<AppName>.app"
APP_TMP="/tmp/<AppName>-verify.app"
VERIFY_BUNDLE="<bundle-id>.verify"

rm -rf "$APP_TMP"
cp -R "$APP_SRC" "$APP_TMP"

plutil -replace CFBundleIdentifier -string "$VERIFY_BUNDLE" \
  "$APP_TMP/Contents/Info.plist"
plutil -replace CFBundleName -string "<AppName>Verify" \
  "$APP_TMP/Contents/Info.plist"

codesign --force --deep --sign - "$APP_TMP"
open "$APP_TMP"
sleep 2

pgrep -fl "$APP_TMP/Contents/MacOS/"
```

要点：

- 修改 `Info.plist` 会让原签名失效，必须重新 ad-hoc 签名。
- 独立 Bundle ID 让单实例检查、默认值域和 AX 目标都互不干扰。
- 只复制到临时目录；不要把改过 Bundle ID 的副本留在桌面或 Applications。
- `open` 后如果进程不存在，先看日志/Gatekeeper/签名，不要反复点。

## 3. 按 PID 驱动 AX

同名进程、同 Bundle ID 多副本时，不要用 `process "<AppName>"`。先按 PID 找到唯一进程：

```applescript
set targetPID to 12345 -- 替换为 pgrep 得到的实际 PID
tell application "System Events"
    set procs to every application process whose unix id is targetPID
    if (count of procs) = 0 then return "not registered"
    set p to item 1 of procs
    set w to window 1 of p
    return {name of w, position of w, size of w}
end tell
```

要点：

- `first process whose unix id is targetPID` 在进程尚未注册到 System Events 时可能报 `-1719`（invalid index）。先枚举并检查 `count`，再取 `item 1`。
- AX 进程名可能是二进制名，不一定等于 `CFBundleName`；不要靠名字区分副本。
- 没有辅助功能权限时，AX 查询会失败；让用户在系统设置中授权，不要绕过。
- 先确认目标窗口 `AXMain` / `AXFocused`，再截图或点击；多窗口应用不要默认 `window 1` 就是主窗口。

## 4. 激活与按窗口区域截图

```bash
osascript -e 'tell application id "<verify-bundle-id>" to activate'
sleep 1

# 从 AXPosition / AXSize 读取，替换为实际数值
AX_X=0; AX_Y=0; AX_W=800; AX_H=600
screencapture -x -R "$AX_X,$AX_Y,$AX_W,$AX_H" /tmp/<AppName>-verify.png
sips -g pixelWidth -g pixelHeight /tmp/<AppName>-verify.png
```

要点：

- `AXPosition` / `AXSize` 使用屏幕坐标点；`screencapture -R` 的区域坐标以屏幕左上角为原点。
- 区域截图在不同系统/显示器上可能是 1x，也可能是 2x；用 `sips` 读实际像素尺寸，再换算 pt，不要假设 Retina 一定是 2x。
- `screencapture -x -l<window-id>` 只截目标窗口，但需要屏幕录制权限；全黑、只有壁纸或空白时先检查 TCC、最小化、当前 Space。
- `-R` 会截取屏幕区域，重叠窗口也会被拍进去；确保目标在前台，或改用窗口 ID 截图。
- 截图后立即读取/测量；不要复用上一次的坐标。

## 5. 临时改写布局默认值

优先在独立 Bundle ID 的域上操作；如果只能操作原 Bundle ID，先退出自己的实例，记录原值，结束后恢复。

```bash
# 记录
defaults read "<bundle-id>" sidebar_hidden
defaults read "<bundle-id>" sidebar_width
defaults read "<bundle-id>" single_pane_mode
defaults read "<bundle-id>" pane_left_width

# 临时构造窄侧栏（先退出自己启动的实例）
defaults write "<bundle-id>" sidebar_width -int 180
open "<path-to-app>"
sleep 2
screencapture -x -R "$AX_X,$AX_Y,$AX_W,$AX_H" /tmp/<AppName>-narrow.png

# 恢复
defaults write "<bundle-id>" sidebar_width -int 206
```

要点：

- 应用可能在退出时回写偏好；先退出再 `defaults write`，再启动。
- 原键不存在时，恢复用 `defaults delete "<bundle-id>" <key>`，不要写回一个默认值。
- 不要用 `defaults delete "<bundle-id>"` 清整个域；会丢用户主题、快捷键等真实偏好。
- 改默认值会改变用户下一次启动的状态；不确认就不要动用户实例的域。

## 6. 点击与操作顺序

1. **AX 元素**：有 `AXButton` / `AXMenuItem` 等元素时，优先 `perform action` 或按元素操作。
2. **CUA 元素**：按元素定位，不依赖截图坐标。
3. **CUA 坐标**：同一次执行内 `get state → screenshot → click → screenshot`，不复用旧坐标。
4. **CGEvent**：最后手段。y 以屏幕顶部为原点；TCC 弹窗和重叠窗口会让点击打到别的 App；点击后必须复核。
5. **人机配合**：合成事件不稳定时，明确告诉用户要做什么，等待用户操作；不要循环抢焦点。

TCC 弹窗出现时，不要循环点击“允许”。让用户授权或拒绝，然后重新取状态。`user is still interacting` 表示真人正在操作，立即让出控制权。

## 7. 清理

```bash
PID=12345  # 替换为 pgrep 得到的验证实例 PID
kill "$PID"
rm -rf "$APP_TMP"
defaults read "<bundle-id>" sidebar_width
```

- 只杀自己启动的 PID；不要按进程名批量杀。
- 删除前确认 `$APP_TMP` 是自己创建的临时副本；用户桌面/构建缓存副本不要删。
- 恢复默认值后再启动一次或读取一次，确认恢复成功。
- 报告里保留 PID、Bundle ID、版本、窗口 bounds、截图路径和测量值。

## 故障对照

| 现象 | 优先检查 | 处理 |
|---|---|---|
| AX 报 `-1719` | `first process whose unix id` 命中了未注册进程 | 改用 `every application process whose unix id is N`，先判断 `count` |
| AppleScript 命中错误窗口 | 同名进程、同 Bundle ID 多副本 | 用 PID 或独立 Bundle ID，不用进程名 |
| 截图全黑/只有壁纸 | 屏幕录制权限、最小化、其他 Space | 让用户授权；取消最小化或切 Space |
| `-R` 截到别的 App | 目标不在前台、窗口重叠 | 先激活并确认 `AXMain`，或改用窗口 ID |
| 坐标点击打空 | 复用了旧截图、pt/px 混用、CGEvent 原点 | 重新截图；按实际像素尺寸换算；优先 AX |
| 点击被系统弹窗吃掉 | TCC/隐私授权弹窗 | 停止重试，交还用户处理 |
| 写入默认值不生效 | 应用退出时回写、写到了错误域 | 先退出再写；确认 Bundle ID；结束时恢复 |
| 临时副本启动失败 | Info.plist 改动后签名失效、Gatekeeper | 重新 `codesign --force --deep --sign -`；检查日志 |
