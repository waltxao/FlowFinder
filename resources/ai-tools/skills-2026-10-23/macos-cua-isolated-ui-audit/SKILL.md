---
name: macos-cua-isolated-ui-audit
description: "Make Computer Use ready for an isolated macOS app UI audit: check console lock and prevent re-lock with caffeinate, recover from SESSION_BUSY by closing stale CUA clients, launch through LaunchServices with the app's own permission-gate bypass, bind evidence to PID and executable path, and clean up only the audit copy. Use before a long macOS CUA audit, or when CUA reports a locked screen, SESSION_BUSY, no window after launch, a permission gate blocking startup, or a self-test process that appears hung. 适用于 macOS 独立副本 CUA 真机验收的环境预检、会话恢复、启动取证与清理；审计结论与覆盖矩阵请配合 cua-macos-ui-audit 使用。"
---

# macOS CUA Isolated UI Audit

## Overview

This skill is the execution runbook for a Computer Use (CUA) audit of a native macOS app running from an isolated copy. It makes sure the Mac can actually be driven, the CUA client is healthy, the intended copy is running, the app's own permission gate is handled deliberately, and cleanup touches only the audit copy.

Scope boundary:

- This skill owns the isolated-copy environment, launch, session health, evidence binding, and cleanup phases.
- Use `cua-macos-ui-audit` for the full coverage matrix and verdict policy; use `macos-native-ui-verification` for per-surface visual acceptance.
- If a dedicated CUA session-recovery skill is installed, use it for deep recovery after repeated failures. The recovery steps here are the minimum needed to keep an audit moving, not a competing recovery policy.

## When to Use

- Before a long CUA audit of a macOS app copy, especially one that may outlast the screen-lock timeout.
- CUA reports a locked screen, `Automatic unlock is unavailable`, or refuses to type or click.
- CUA reports `SESSION_BUSY: close the previous client and wait for its cleanup`.
- The audit copy starts but no window appears, or the main thread is stuck in a permission gate.
- A self-test binary appears hung while `__CFBundleIdentifier` or `FF_*` environment values leak from the parent process.
- You need to bind evidence to an exact PID and executable path, then clean up only your own copy.

Do not use this skill for web or iOS UI, pure code review, or bypassing macOS TCC. It does not authorize touching the user's running app.

## Non-Negotiables

1. **Check the lock before launch, and re-check before claiming results.** CUA cannot drive a locked Mac. Only the user can unlock it.
2. **Never bypass TCC.** The app's own permission gate and the system TCC prompt are different layers. A skip flag for the former has no effect on the latter.
3. **Use an app-level bypass only on an isolated copy, and only if the flag exists in the app source.** Never set it on the user's instance; never add a bypass to product code for audit convenience.
4. **One CUA client per `node_repl` session.** Close stale clients before creating a new one; do not create parallel sessions.
5. **PID must match the executable path.** A display name, process name, or successful `open` is not proof of the intended instance.
6. **Only kill and delete your own audit copy.** Never use `pkill` by process name. Guard `rm -rf` with an exact temporary-path pattern.
7. **`caffeinate` is time-limited and stopped at the end.** It prevents idle and display sleep; it does not unlock a locked Mac and does not prevent a manual lock.
8. **Locked or unknown state means `Blocked`, not a product defect.** Do not convert "no window while locked" into an app bug.
9. **Launch success is not audit evidence.** Verify a window exists, belongs to the exact PID, and has current AX or screenshot state.

## Phase 0: Preflight

Use `scripts/cua-preflight.sh --check` for a read-only report, `--caffeinate 7200` to start bounded prevention after unlock, and `--stop-caffeinate` to stop only the PID it recorded. You can also run the commands directly.

### Check the console lock

```bash
ioreg -n Root -d1 -a 2>/dev/null \
  | plutil -p - 2>/dev/null \
  | grep -i -E 'IOConsoleLocked|CGSSessionScreenIsLocked' || true
```

Interpretation:

- Any key `=> true`: locked. Ask the user to unlock; stop the launch.
- No key is `true`, but at least one lock key is present and `false`: unlocked. A missing `CGSSessionScreenIsLocked` key is normal on some macOS versions and is not evidence of a lock.
- No lock keys at all: `unknown`, not unlocked. Do not launch and assume it is fine.

Do not chase `plugin_signature_invalid` or `guardian_identity_mismatch` while the console is locked. Those errors may be secondary; a manual unlock is the primary fix.

### Prevent re-lock

Start this only after the console is unlocked. Prefer the bundled helper, which records the PID and verifies the command before stopping it:

```bash
scripts/cua-preflight.sh --caffeinate 7200
```

Equivalent manual form:

```bash
nohup caffeinate -dimsu -t 7200 >/tmp/cua-caffeinate.log 2>&1 &
CAFFEINATE_PID=$!
echo "$CAFFEINATE_PID" >/tmp/cua-caffeinate.pid
```

`-dimsu` prevents display, idle, disk, and system sleep. It cannot prevent a manual lock. Use a finite `-t` value and record the PID. Do not leave a caffeinate process behind.

Stop it by PID after verifying the command, not by a broad pattern:

```bash
ca_cmd=$(ps -p "$CAFFEINATE_PID" -o command= 2>/dev/null || true)
case "$ca_cmd" in
  caffeinate\ -dimsu*|*/caffeinate\ -dimsu*) kill "$CAFFEINATE_PID" ;;
  *) echo "Refusing to kill PID $CAFFEINATE_PID: not caffeinate -dimsu" >&2 ;;
esac
```

### Record the user instance

```bash
ps -axo pid=,command= | grep -F "/Contents/MacOS/" | grep -v grep
```

Record the desktop instance's PID and absolute path before starting. It must remain untouched and running at the end.

## Phase 1: CUA Client Lifecycle

Create the client once per fresh `node_repl` session and bind by the copy's unique bundle ID or absolute app path:

```js
var cua = await (await import("@ali/qoder-cu-sdk")).ComputerUse.createAppClient();
var app = await cua.getApp(bundleIdOrAbsolutePath);
await app.getAXState({ disableDiffing: true });
```

On `SESSION_BUSY: close the previous client and wait for its cleanup`:

1. Close every client you previously created in this session. The client prototype exposes `close()`; the app object does not.
2. Wait about one second for cleanup.
3. Create a new client and rebind in the **same** `node_repl` session.

```js
for (const c of [globalThis.cua3, globalThis.cua2, globalThis.cua]) {
  if (c && typeof c.close === "function") {
    try { await c.close(); } catch (e) {}
  }
}
await new Promise((resolve) => setTimeout(resolve, 1000));
var cua4 = await (await import("@ali/qoder-cu-sdk")).ComputerUse.createAppClient();
var app4 = await cua4.getApp(bundleIdOrAbsolutePath);
```

Rules:

- Do not call `app.close()`; that method is not part of the app object.
- Do not start a second `node_repl` session to work around `SESSION_BUSY`.
- If the error persists after two close-and-wait attempts, stop and report a blocked CUA session.
- After a successful rebind, request a full AX baseline and discard every old element ID and coordinate.

## Phase 2: Launch and Bind

### Preferred: LaunchServices with environment injection

For a CUA-driven UI audit, launch through LaunchServices so the copy registers correctly:

```bash
open --help 2>&1 | grep -q -- '--env' \
  || { echo "open does not support --env; see fallback" >&2; exit 2; }

open -n --env APP_GATE_BYPASS=1 "$APP_COPY"
```

Use the exact app path. Wait for launch, then resolve the PID by executable path:

```bash
REAL=$(cd "$APP_COPY" && pwd -P)
PID=""
for p in $(pgrep -f -- "$REAL/Contents/MacOS/"); do
  cmd=$(ps -p "$p" -o command= 2>/dev/null || true)
  case "$cmd" in
    "$REAL/Contents/MacOS/"*) PID="$p"; break ;;
  esac
done
[ -n "$PID" ] || { echo "Audit copy did not launch" >&2; exit 1; }
ps -p "$PID" -o pid=,command=
```

Then verify the window belongs to that PID, for example:

```bash
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to get {frontmost, count of windows, name of every window}' 2>&1
```

A successful `open` is not proof. If there are multiple candidates, check each command path; do not take the first PID.

### Headless self-test: direct binary with the parent bundle ID removed

When no window is needed, a direct binary launch is acceptable, but remove the inherited Qoder bundle identity:

```bash
env -u __CFBundleIdentifier APP_GATE_BYPASS=1 "$REAL/Contents/MacOS/App"
```

Why: a process launched from Qoder's shell can inherit `__CFBundleIdentifier=com.qoder.app`. The child may then resolve its bundle identity to Qoder, hit a single-instance or modal path, and appear hung with the main thread in `mach_msg`. `env -u` makes it read its own `Info.plist`.

Direct launch may not register the app with LaunchServices. If CUA needs a window, switch to `open -n --env`; do not conclude the app is broken because a direct-launch window is missing.

### Record the environment

```bash
ps eww -p "$PID" | tr ' ' '\n' | grep -E '^(FF_|__CFBundleIdentifier)' || true
```

If `__CFBundleIdentifier=com.qoder.app` appears, record it as an isolation artifact. Relaunch with `env -u` for a headless self-test or with `open -n` for a UI audit.

## Phase 3: Permission Gate

Distinguish two layers before acting:

| Layer | Typical symptom | Allowed action |
|---|---|---|
| App-level gate (for example `FFPermissionGate`) | Main window is not created; `sample` shows threads in `requestAccess`; process is alive | Use the app's own documented bypass flag on the isolated copy only |
| System TCC | macOS privacy prompt for Desktop, Documents, Downloads, Accessibility, or Screen Recording | Stop and let the user decide; never click blindly or bypass |

Confirm the app's bypass flag exists in source before using it:

```bash
grep -RIn --include='*.swift' 'APP_GATE_BYPASS' .
```

The verified example for this workspace is `FF_SKIP_PERMISSION_GATE=1`. This flag bypasses only the app's own gate; it does not grant TCC permissions. Use it through `open -n --env` for a UI audit:

```bash
open -n --env FF_SKIP_PERMISSION_GATE=1 "$APP_COPY"
```

Do not use the flag on the user's instance. Do not add a bypass branch to product code solely to make an audit easier.

## Phase 4: Evidence and Rechecks

- Re-check the lock state before launch, after long test runs, and before claiming results. A screen can lock again during a multi-hour audit.
- If the lock is `locked` or `unknown`, mark the surface `Blocked`. Do not classify the missing window, disabled menu, or failed click as a product defect.
- After every rebind, relaunch, resize, mode change, or appearance change, fetch a full AX baseline and take a new screenshot.
- Never reuse element IDs or screenshot coordinates across a new baseline, PID, window geometry, or app instance.
- Record the exact artifact: source app, copy path, bundle ID, version, executable path, PID, lock state, environment, and window geometry.
- Keep the audit copy's evidence separate from static code review and baseline tests.

## Phase 5: Cleanup

Stop only the audit copy, and only after verifying the PID still maps to its executable path:

```bash
cmd=$(ps -p "$PID" -o command= 2>/dev/null || true)
case "$cmd" in
  "$APP_COPY/Contents/MacOS/"*) kill "$PID" ;;
  *) echo "Refusing to kill PID $PID: unexpected command" >&2 ;;
esac
```

Remove only your own temporary audit directory:

```bash
case "$VERIFY_DIR" in
  /tmp/macos-ui-verify.*|/private/tmp/macos-ui-verify.*) rm -rf "$VERIFY_DIR" ;;
  *) echo "Refusing to remove unexpected path: $VERIFY_DIR" >&2 ;;
esac
```

Then:

1. Stop `caffeinate` by verified PID.
2. Verify the user's desktop instance is still running with the same PID and path.
3. Report whether cleanup and caffeinate stop succeeded.
4. Do not delete temporary fixtures until the evidence has been copied to its final report location.

## Failure Signatures

| Signal | Interpretation | Required action |
|---|---|---|
| `IOConsoleLocked => true` or `CGSSessionScreenIsLocked => true` | Console is locked | Ask the user to unlock; stop; do not diagnose the app |
| `Automatic unlock is unavailable` plus signature or guardian errors | Locked screen; automatic unlock is secondary | Manual unlock; re-check lock; do not chase plugin signatures first |
| `SESSION_BUSY: close the previous client and wait for its cleanup` | A stale CUA client owns the session | Close old clients, wait about 1 second, recreate in the same session |
| Audit copy PID is alive but no window appears | Lock, app gate, or not yet launched | Check lock first; then check the gate; then verify PID/path and window ownership |
| `sample` shows `FFPermissionGate.requestAccess` in several threads | App-level permission gate is blocking startup | Use the app's own bypass only on the copy; never bypass TCC |
| Main thread in `mach_msg`, no log output, `__CFBundleIdentifier=com.qoder.app` | Parent environment leaked into the child | Relaunch with `env -u __CFBundleIdentifier` (headless) or `open -n --env` (UI) |
| `open: unrecognized option '--env'` | Older `open` or wrong command | Use direct binary only for headless work; do not fake LaunchServices for a UI audit |
| `No active app state` or stale element IDs | CUA state is stale after rebind or relaunch | Reacquire the app and a full AX baseline; discard old IDs and coordinates |
| Multiple PIDs for the same app name | Another copy or a stale instance | Verify each executable path; never kill by process name |
| `caffeinate` still running after cleanup | Sleep prevention left behind | Verify command and kill by recorded PID |

## Completion Checklist

- [ ] Lock state checked and recorded before launch.
- [ ] `caffeinate` started after unlock, time-limited, PID recorded, and stopped at the end.
- [ ] One CUA client; stale clients closed; no `SESSION_BUSY` retry loop.
- [ ] Launch used `open -n --env` for UI, or `env -u __CFBundleIdentifier` for a headless self-test.
- [ ] PID matches the copy's exact executable path; a window was verified for that PID.
- [ ] App-level gate and TCC were distinguished; TCC was not bypassed.
- [ ] Environment recorded, including any `__CFBundleIdentifier` leak.
- [ ] Locked or unknown surfaces were marked `Blocked`, not reported as defects.
- [ ] Audit PID killed only after path verification; temporary directory removed under a guard.
- [ ] User's desktop instance still running; no `pkill` used by process name.
- [ ] Cleanup and caffeinate stop reported accurately.

## Resources

- `scripts/cua-preflight.sh` — read-only lock, caffeinate, and candidate-process report; optional time-limited caffeinate start/stop with PID verification. It never launches, kills, or deletes an app.
