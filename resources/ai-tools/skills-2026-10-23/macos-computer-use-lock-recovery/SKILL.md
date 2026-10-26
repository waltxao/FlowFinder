---
name: macos-computer-use-lock-recovery
description: 'Recover macOS Qoder Computer Use when it suddenly fails with "Automatic unlock is unavailable", capabilityUnavailable(... plugin_signature_invalid / guardian_identity_mismatch), SESSION_BUSY, or a launched target with no window. Check IOConsoleLocked and CGSSessionScreenIsLocked first, ask the user to unlock manually, close stale CUA clients, relaunch and rebind the target, then prove recovery with fresh AX state. 适用于 Computer Use 突然不可用、锁屏、解锁后 SESSION_BUSY、独立副本无窗口等场景。'
---

# macOS Computer Use Lock Recovery

## Overview

CUA 报自动解锁、插件签名或 guardian 身份错误时，先查屏幕是否锁定。锁屏会让 CUA 拒绝操作，也会让目标 App “启动成功但没有窗口”。按「锁屏检查 → 用户手动解锁 → 关闭旧 client → 重绑目标 → fresh AX 验证」恢复，不要先追签名或改系统设置。

## When to Use

- CUA 报 `Automatic unlock is unavailable`
- 报 `capabilityUnavailable("plugin_signature_invalid, ... guardian_identity_mismatch")`
- 报 `SESSION_BUSY: close the previous client and wait for its cleanup`
- CUA 之前可用，突然不可用
- 目标 App 启动成功但没有窗口，或 System Events 看不到窗口
- 长时间 UI 验证中屏幕可能再次锁定

For CUA SDK API and interaction patterns, use the built-in `computer-use` skill. For full UI audit evidence and isolation policy, use `cua-macos-ui-audit`.

## Non-Negotiables

1. 先查锁屏，再判断插件、签名、App 或测试宿主。
2. 绝不做程序化解锁、索要或输入密码、关闭锁屏、修改安全或隐私设置。只请用户手动解锁。
3. 只操作本次创建的隔离副本。终止前确认 PID 仍映射到该副本的可执行路径；禁止按进程名 `pkill`。
4. 删除临时目录前打印并核对路径，只删本次创建、前缀匹配的目录。
5. `caffeinate` 只防止空闲休眠，不能解锁；必须设置 `-t` 上限并按 PID 关闭。
6. 恢复后必须拿到目标 App 的 fresh AX 树或截图才算成功；只补跑被中断的检查，未观察到的页面标 `Unverified`。
7. 同一恢复路径最多尝试两次；仍失败就停止并报告证据，不要循环重建 client 或反复启动 App。

## Triage

| 现象 | 先查 | 动作 |
|---|---|---|
| `Automatic unlock is unavailable` + 签名/guardian 字符串 | 锁屏状态 | 请用户解锁，复查后重试 |
| CUA 突然不可用，之前正常 | 锁屏状态 | 同上；不要先重启 Qoder |
| `SESSION_BUSY` | node_repl 里的旧 client | close → 等待 800–1000ms → 新建 |
| `open` 成功但无窗口 | 锁屏状态是否再次为 true | 终止副本，解锁后重启 |
| 解锁 + 关闭旧 client 后仍报签名/guardian | Qoder runtime / 权限 | 重启 Qoder，检查辅助功能与屏幕录制 |

## Recovery

### 1. Check lock state first

```bash
ioreg -n Root -d1 -a 2>/dev/null \
  | plutil -p - 2>/dev/null \
  | grep -iE 'IOConsoleLocked|CGSSessionScreenIsLocked' || true
```

Interpretation:

- `IOConsoleLocked => true` or `CGSSessionScreenIsLocked => true`: locked. Treat it as locked even if the user is chatting from another device or the Qoder window is visible.
- At least one key is `=> false` and none is `=> true`: unlocked.
- No matching keys: unknown. Do not assume unlocked; rerun or inspect manually.

Use `scripts/lock-state.sh` for a tri-state result: `LOCKED` (exit 3), `UNLOCKED` (exit 0), `UNKNOWN` (exit 4).

Do not rely on Python Quartz for this check; PyObjC may be unavailable.

### 2. If locked

1. Stop CUA and UI work. Do not launch or debug the target app: a launch while locked can succeed with no window.
2. Ask the user to unlock the Mac manually with password or Touch ID, and keep it unlocked.
3. For long unattended runs, optionally start a bounded keep-awake and record its PID:

   ```bash
   caffeinate -dimsu -t 3600 >/tmp/cua-caffeinate.log 2>&1 &
   echo $! > /tmp/cua-caffeinate.pid
   ```

   It prevents idle sleep and idle lock but cannot unlock the screen. Close it by PID when the run ends.

4. Wait for an explicit user confirmation, then rerun Step 1. Do not proceed on the assumption that the message means the screen is actually unlocked.

### 3. If SESSION_BUSY

`SESSION_BUSY` means a previous CUA client still owns the session. `node_repl` state persists across calls.

1. Identify the client variable from the last `createAppClient()` call in this session.
2. Close the client, not the app object. `client.close()` exists; `app.close()` does not.
3. Wait 800–1000ms for cleanup.
4. Create exactly one new client and bind the target.

```js
// Replace cua10 with the actual client variable from your previous call.
try { await cua10.close(); } catch (e) { nodeRepl.write("close: " + e.message); }
await new Promise(r => setTimeout(r, 800));

var cuaNext = await (await import("@ali/qoder-cu-sdk")).ComputerUse.createAppClient();
var appNext = await cuaNext.getApp("<bundle-id-or-app-path>");
```

If the close fails, report the error; do not create a new client in a loop. If the old client reference is lost, stop and report rather than guessing. Restarting the node_repl session or Qoder is a fallback, not a verified first-line step.

### 4. Launch and rebind the target

Launch only an isolated copy. Verify the PID by exact executable path before interacting with or terminating it.

```bash
open -n --env <APP_SPECIFIC_GATE_VAR>=1 "$APP"
```

`open` supports `--env VAR=VALUE`. Use a skip-gate variable only when the target app itself implements one. For FlowFinder, the app-specific example is `FF_SKIP_PERMISSION_GATE=1`; this is not a CUA flag, a TCC bypass, or a variable to reuse for other apps.

After launch, verify window ownership. A successful `open` or a running PID does not prove a window exists.

If there is no window, rerun Step 1 before blaming the app or test harness. If the screen locked again, terminate only the audit copy and relaunch after unlock.

### 5. Prove recovery

- Bind with the bundle identifier or absolute app path.
- Fetch a fresh baseline: `getAXState({ disableDiffing: true, emit: false })` or a screenshot.
- Confirm the expected window and control are visible.
- Resume only the interrupted checks. Report surfaces not observed as `Unverified`; do not claim a full audit.

## Escalation

Only after the screen is confirmed unlocked and the old client is closed and recreated:

- If the same signature or guardian error persists, restart Qoder, then recheck Accessibility and Screen Recording permissions for Qoder and Qoder Computer Use.
- If the app launches but still has no window while unlocked, inspect the PID, executable path, and app logs before restarting anything.
- Stop after two failed recovery attempts for the same failure. Preserve lock values, error text, client close result, PID, bundle ID, and the last AX state or screenshot.

## References

- Built-in `computer-use`: CUA SDK API, AX state, input actions, and confirmation policy.
- `cua-macos-ui-audit`: isolated-copy audit, coverage matrix, and evidence classification.
- `scripts/lock-state.sh`: tri-state lock check.
