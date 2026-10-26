---
name: macos-cua-session-recovery
description: "Recover macOS Computer Use sessions blocked by screen lock, SESSION_BUSY, a closed CUA connection, or an isolated app copy that launches without a window. Use when IOConsoleLocked or CGSSessionScreenIsLocked is true, CUA reports SESSION_BUSY or 'Computer Use connection is closed', an app copy has a PID but no window, screenshots capture the wrong region, or AX element IDs go stale after reconnect. 适用于 macOS CUA 锁屏、客户端重连、副本启动无窗口、截图/AX 取证恢复；不负责 UI 覆盖矩阵与产品验收本身。"
---

# macOS CUA Session Recovery

## Overview

Recover the CUA evidence chain: unlocked screen, one live client, the correct copy PID and window geometry, then a fresh AX tree and screenshot. This skill repairs the instrumentation. It does not decide whether the UI passes.

Use together with `cua-macos-ui-audit` for coverage policy and `macos-native-ui-verification` for per-surface visual acceptance.

## Non-Negotiables

1. Check the lock state before reauthorizing permissions, reinstalling, or filing a product bug.
2. Treat recovery as instrumentation repair. A surface stays `Unverified` until it has a post-recovery screenshot and state.
3. Touch only the copy, client, and `caffeinate` process you created. Record bundle ID, PID, and paths before acting.
4. After any error, re-read state before acting again. Never replay an action whose result is unknown.
5. Stop after two failed recovery attempts for the same signal. Preserve the raw error and report `Blocked`.
6. Use an app's own test flag only on an isolated copy. Never bypass macOS TCC on the user's app.
7. Keep one active CUA client per `node_repl` session.

## Recovery Ladder

| Signal | First check | Verified response | Never do |
|---|---|---|---|
| App has a PID but no window, or AX is empty | `IOConsoleLocked`, `CGSSessionScreenIsLocked` | Start bounded `caffeinate`, ask the user to unlock, relaunch the copy after unlock | Reauthorize TCC, reinstall, assume a single-instance modal |
| `SESSION_BUSY: close the previous client and wait for its cleanup` | Live client variables in `node_repl` | Close every known client, wait 800-1000 ms, create one new client | Create another client on top of the busy one |
| `Computer Use connection is closed` | Whether the previous action partially applied | Close, wait, recreate, fetch full AX, take a new screenshot, compare state | Blindly repeat the last click |
| Screenshot shows the wrong region | Current window position and size | Re-query geometry, then `screencapture -R` | Hardcode coordinates from an earlier run |
| `New accessibility baseline` or reused IDs | Full AX tree | Discard all prior IDs and rebuild targets | Reuse a numeric ID after reconnect |
| `open -n` copy runs but is invisible | Lock state, app permission gate, real path/PID | Use `open -n --env <app test flag>=1`, match PID by `pwd -P` path | Kill by process name or launch direct binaries blindly |

## 1. Preflight: Lock and Caffeinate

Run the read-only check first:

```bash
scripts/cua-preflight.sh
```

Expected healthy output includes `LOCKED=no`. The script reads:

```bash
ioreg -n Root -d1 -a 2>/dev/null | plutil -p - 2>/dev/null \
  | grep -i -E 'IOConsoleLocked|CGSSessionScreenIsLocked' || true
```

If `LOCKED=yes`:

1. Record both key values verbatim.
2. Start bounded prevention: `scripts/cua-preflight.sh --caffeinate 7200`.
3. Ask the user to unlock the Mac manually. Do not attempt to unlock programmatically.
4. Clean up any copy launched while locked: it may have a process but no window.
5. After the user confirms unlock, rerun the check before launching anything.

`caffeinate` prevents idle sleep, not a manual lock or a password-protected screen saver. Always bound it with `-t`, record its PID, and stop only that PID. Never use `pkill` to clear caffeinate processes you did not start.

When done: `scripts/cua-preflight.sh --stop-caffeinate`.

## 2. Launch an Isolated Copy CUA Can See

Create a unique bundle identity, re-sign after editing `Info.plist`, and launch through LaunchServices with the app's own test flag:

```bash
SRC="/absolute/path/App.app"
DIR=$(mktemp -d /tmp/macos-ui-verify.XXXXXX)
APP="$DIR/AppAudit.app"
cp -R "$SRC" "$APP"

BID="com.example.audit.$(date +%s)"
plutil -replace CFBundleIdentifier -string "$BID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "AppAudit" "$APP/Contents/Info.plist" 2>/dev/null || true
plutil -replace CFBundleDisplayName -string "AppAudit" "$APP/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

open -n --env APP_SKIP_PERMISSION_GATE=1 "$APP"
sleep 3
```

Replace `APP_SKIP_PERMISSION_GATE` with the app's actual test-only environment variable, and only when the app supports it. This flag skips the app's own onboarding/permission gate; it is not a macOS TCC bypass. If no such flag exists, stop and let the user handle the permission prompt.

Resolve the PID by real path, not by name:

```bash
REAL=$(cd "$APP" && pwd -P)
PID=""
for p in $(pgrep -f -- "$REAL/Contents/MacOS/"); do
  cmd=$(ps -p "$p" -o command= 2>/dev/null || true)
  case "$cmd" in
    "$REAL/Contents/MacOS/"*) PID=$p; break ;;
  esac
done
[ -n "$PID" ] || { echo "NO_PID_FOR=$REAL" >&2; exit 1; }
```

`/tmp` is a symlink to `/private/tmp`. Comparing the `mktemp` path with the process command fails unless you resolve it with `pwd -P`; the failure mode is either "no PID" or a second accidental instance.

Confirm a visible window, then set and read back geometry:

```bash
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to get {frontmost, count of windows, name of every window}'
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to set {position of window 1, size of window 1} to {{0, 30}, {1440, 900}}'
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to get {position of window 1, size of window 1}'
```

If `count of windows` is 0, check in this order: lock state, permission gate, PID path. Do not conclude the app is broken and do not attach a debugger.

## 3. Client Lifecycle

Create one client per `node_repl` session and bind by exact bundle ID:

```js
var cua = await (await import('@ali/qoder-cu-sdk')).ComputerUse.createAppClient();
var app = await cua.getApp('<BUNDLE_ID>');
var ax = await app.getAXState({ disableDiffing: true, emit: false });
nodeRepl.write(ax.split('\n').filter(l => /Window:|button |text field /.test(l)).slice(0, 80).join('\n'));
```

The Computer Use client has `close()`; the app object does not. Before creating any new client, close the current one and wait. Use `emit: false` and write screenshots to files so full AX trees and image bytes do not flood the context.

See `references/recovery-snippets.md` for the verified connect, reconnect, screenshot, element lookup, geometry fallback, and cleanup snippets.

## 4. Recover Session Errors

### SESSION_BUSY

Exact signal: `SESSION_BUSY: close the previous client and wait for its cleanup`.

1. In `node_repl`, close every client variable you created, each in its own `try/catch`.
2. Wait 800-1000 ms. Cleanup is asynchronous; recreating immediately reproduces the error.
3. Create exactly one client and bind the app again.
4. Fetch a full AX tree before acting.

If the error persists after two cycles, stop and report the raw error plus the client variables you closed.

### Computer Use connection is closed

The failed call may have partially applied. In one verified run, the error contained the tail of a scroll result, proving the action had executed.

1. Do not repeat the last action.
2. Close the dead client and wait about 800 ms.
3. Create a new client and bind the same bundle ID.
4. Fetch full AX and take a fresh screenshot.
5. Compare the new state with the intended pre-action state before deciding whether to retry.

If CUA cannot reconnect, preserve evidence with System Events geometry plus a region screenshot:

```bash
screencapture -x -R "$X,$Y,$W,$H" /tmp/cua-evidence.png
```

Re-read geometry immediately before capture; the window may have moved after relaunch.

## 5. Rebuild the Evidence Chain

After any recovery, re-establish all five links in order:

1. Lock state.
2. Copy bundle ID, version, PID, and real executable path.
3. Current window title and geometry.
4. Fresh full AX tree.
5. Fresh screenshot.

Record the bundle ID, PID, geometry, screenshot path, AX summary, action result, and verdict. Treat every prior element ID, coordinate, PID, and screenshot as invalid after a reconnect. A number that reappears in a new baseline may point to a different element.

## 6. Verify a Targeted Change

Use a three-frame sequence and keep all frames:

1. Baseline screenshot and AX in the starting state.
2. Perform one deterministic action.
3. Wait for the UI to settle, then screenshot and re-read AX.
4. Perform the inverse or next action, settle, screenshot again.

For example, verify a live theme fix with light -> dark -> light captures. Claim only the surfaces captured in this sequence. A green build, unit test, or successful reconnect does not prove the UI changed.

## 7. Cleanup

Close CUA first, then stop only your copy:

```bash
APP=$(cat /tmp/cua-copy-app)
CID=$(cat /tmp/cua-copy-pid)
REAL=$(cd "$APP" && pwd -P)
cmd=$(ps -p "$CID" -o command= 2>/dev/null || true)
case "$cmd" in
  "$REAL/Contents/MacOS/"*) kill "$CID" ;;
  *) echo "REFUSED: $CID is not the copy executable" ;;
esac
case "$APP" in
  /tmp/macos-ui-verify.*|/private/tmp/macos-ui-verify.*) rm -rf "$(dirname "$APP")" ;;
  *) echo "REFUSED: $APP" ;;
esac
BID=$(cat /tmp/cua-copy-bid); defaults delete "$BID" 2>/dev/null || true
scripts/cua-preflight.sh --stop-caffeinate
```

Finally confirm the user's own instance PID and path are unchanged, and that no audit copy or `caffeinate` process remains. Report cleanup output; an intention to clean up is not evidence.

## 8. Report

Separate these categories in the final report:

- **Environment events**: lock, `SESSION_BUSY`, connection closed, permission gate, launch failures. Include timestamps and signed recovery steps.
- **Verified**: surfaces with a post-recovery screenshot and AX or behavioral evidence.
- **Unverified**: plausible but not observed after recovery.
- **Blocked**: recovery failed twice, permission denied, or the surface could not be reached.

State isolation limitations: a new bundle ID, ad-hoc signature, and copied path change the TCC identity and app-support location. Do not present copy-only results as results for the user's installed app.

## Pitfalls

- Treating a locked screen as a TCC, install, or single-instance failure.
- Creating a second CUA client after `SESSION_BUSY` instead of closing the old one.
- Repeating the failed action after `Computer Use connection is closed`.
- Reusing AX IDs or screenshot coordinates after a reconnect or geometry change.
- Comparing `/tmp/...` with `/private/tmp/...` and concluding the copy never launched.
- Launching a direct binary to avoid the permission gate; it may have no window and no usable bundle identity.
- Killing audit processes by name or sweeping all `caffeinate` processes.
- Claiming a full UI pass because the session recovered and a few screens were checked.

## Resources

- `scripts/cua-preflight.sh`: read-only lock report, bounded caffeinate start, and PID-checked caffeinate stop.
- `references/recovery-snippets.md`: verified `node_repl` snippets and a full launch/cleanup recipe.
