---
name: macos-cua-lock-and-launch-recovery
description: "Diagnose and recover Qoder Computer Use (CUA) on macOS when automation worked earlier but suddenly fails mid-task. Triggers include 'Automatic unlock is unavailable', capabilityUnavailable(plugin_signature_invalid / guardian_identity_mismatch), SESSION_BUSY when reconnecting a CUA client, a launched app copy with zero windows or stuck at its permission gate, or a direct-binary launch that silently inherits the Qoder bundle identity. Covers checking CGSSessionScreenIsLocked and IOConsoleLocked, asking the user to unlock manually, closing stale CUA clients, launching an isolated copy with open -n --env FF_SKIP_PERMISSION_GATE=1, and running binaries with env -u __CFBundleIdentifier."
---

# macOS CUA Lock and Launch Recovery

## Overview

Use this skill when Qoder Computer Use (CUA) stops working mid-task, especially after a long build or test run. Work through the causes in this order:

1. The macOS session is locked.
2. A previous CUA client is still alive (`SESSION_BUSY`).
3. The target app is stuck at its own permission gate.
4. A direct-binary launch inherited the Qoder bundle identity.
5. Qoder itself needs a restart.

Do not start with code signing, notarization, or reinstalling Qoder. The `plugin_signature_invalid` text can be a symptom; in the source incident the signature chain was fine and the actual cause was a locked screen.

## Triage

| Symptom | Check first | Action |
|---|---|---|
| `Automatic unlock is unavailable` / `capabilityUnavailable(...)` | Lock flags | Ask the user to unlock manually; recheck before retrying CUA |
| `SESSION_BUSY: close the previous client...` | Live CUA clients | Close every client, wait about 1 second, create one new client |
| Process exists, zero windows, 0% CPU | `sample` for permission gate or modal | Launch with the app's supported permission-gate bypass |
| Process exists, no window, `ps eww` shows `__CFBundleIdentifier=com.qoder.app` | Inherited bundle identity | Relaunch with `env -u __CFBundleIdentifier` |
| `System Events` reports `windows=0` or cannot set frontmost | UI scripting permission or lock | Treat as inconclusive; confirm with CUA and app logs |

## Step 1: Confirm the screen lock state

```bash
ioreg -n Root -d1 -a | plutil -p - | grep -iE 'CGSSessionScreenIsLocked|IOConsoleLocked'
```

- Any `true` means the session is locked. CUA cannot drive a locked session, and its automatic unlock may be unavailable.
- Ask the user to unlock manually with password or Touch ID. Do not try to unlock, wake-and-type, or bypass the lock screen.
- After the user confirms, run the command again. Continue only when neither flag is true. `CGSSessionScreenIsLocked` may be absent when unlocked; absence is not evidence of a lock.
- A user chatting from another device does not prove the Mac is unlocked.

For long runs, `caffeinate -dimsu` can reduce idle and display sleep. It does not replace a manual unlock, and start it only with the user's consent.

## Step 2: Reconnect CUA without SESSION_BUSY

CUA clients are exclusive within a node-repl session. If CUA worked earlier, its client is probably still alive; a second `createAppClient()` fails with:

`SESSION_BUSY: close the previous client and wait for its cleanup`

Close every live client, wait, then create one new client:

```js
for (const c of [cua, cua2, cua3]) {
  try { if (c) await c.close(); } catch (e) {}
}
await new Promise(r => setTimeout(r, 800));
var cua = await (await import('@ali/qoder-cu-sdk')).ComputerUse.createAppClient();
var app = await cua.getApp('<bundle-id>');
```

- `close()` belongs to the client. The app handle returned by `getApp` has no `close`.
- Keep one live client. Do not create clients in a retry loop.
- If a client cannot be closed, reset the node-repl session as a last resort, then reconnect once.

## Step 3: Launch an isolated copy that CUA can see

Build a unique copy so it does not collide with the user's running app or its defaults:

```bash
SRC="/path/to/FlowFinder.app"
DIR=$(mktemp -d /tmp/macos-ui-verify.XXXXXX)
APP="$DIR/FlowFinderAudit.app"
cp -R "$SRC" "$APP"

BID="com.flowfinder.audit.$(date +%s)"
plutil -replace CFBundleIdentifier -string "$BID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "FlowFinderAudit" "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "FlowFinderAudit" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

defaults write "$BID" onboarding_completed -bool true
# Add the app-specific defaults required for the screen under test.

open -n --env FF_SKIP_PERMISSION_GATE=1 "$APP"
sleep 3
```

Use `open` instead of running the binary: LaunchServices gives the copy its own bundle identity and lets CUA attach by bundle ID. Without an app permission-gate bypass, the process can sit at 0% CPU with zero windows while its log shows content loaded; a `sample` then shows threads inside `FFPermissionGate.requestAccess`.

`FF_SKIP_PERMISSION_GATE` is FlowFinder-specific. Before using it on another app, confirm the app reads that variable (for example, grep its source). If there is no supported bypass, do not invent one; let the app prompt once and ask the user to grant access.

Verify the window before calling CUA:

```bash
REAL=$(cd "$APP" && pwd -P)
PID=""
for p in $(pgrep -f -- "$REAL/Contents/MacOS/"); do
  cmd=$(ps -p "$p" -o command= 2>/dev/null || true)
  case "$cmd" in "$REAL/Contents/MacOS/"*) PID=$p; break;; esac
done
ps -p "$PID" -o pid=,%cpu=,command=
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to get {frontmost, count of windows, name of every window}'
```

Expected: `true, 1, <window name>`. Treat System Events as secondary evidence; if it returns zero windows, confirm with CUA `getAppState`, app logs, and `sample` before concluding the launch failed.

If the process exists but has no window:

```bash
sample "$PID" 1 1 -file /tmp/cua-sample.txt >/dev/null 2>&1 || true
grep -nE 'FFPermissionGate|runModal|NSAlert' /tmp/cua-sample.txt | head -30
```

## Step 4: Direct-binary launches

When running the executable directly (for example, a headless self-test), unset the inherited bundle identity:

```bash
env -u __CFBundleIdentifier FF_SKIP_PERMISSION_GATE=1 \
  "$REAL/Contents/MacOS/FlowFinder"
```

Qoder's shell exports `__CFBundleIdentifier=com.qoder.app`. A directly launched child inherits it, so AppKit may see the Qoder identity instead of the copy's Info.plist. Symptoms include no window, no self-test output, and single-instance behavior. Confirm with:

```bash
ps eww -p "$PID" | tr ' ' '\n' | grep -E '__CFBundleIdentifier|FF_SKIP_PERMISSION_GATE'
```

Use this direct-launch form only for headless runs. When CUA needs to attach, prefer the `open -n --env ...` launch from Step 3.

## Step 5: Confirm recovery

- Lock flags are false (Step 1).
- No `SESSION_BUSY`; one client created after closing old ones (Step 2).
- The copy is frontmost with exactly one window (Step 3).
- CUA `getAppState` returns a window and accessibility tree.
- The user's real app PID is unchanged.

If CUA still fails after the lock is cleared and the client is reconnected, fully quit and reopen Qoder, then retry. Reboot only if that fails. Reinstall is not the first move. Check Accessibility and Screen Recording for Qoder and Qoder Computer Use only after the lock and client checks.

## Step 6: Clean up safely

Kill only the verified copy, never every process with the app name:

```bash
if ps -p "$PID" -o command= | grep -Fq "$REAL/Contents/MacOS/"; then
  kill "$PID"
fi

REAL_DIR=$(cd "$DIR" && pwd -P)
case "$REAL_DIR" in
  /private/tmp/macos-ui-verify.*|/tmp/macos-ui-verify.*) rm -rf "$REAL_DIR" ;;
  *) echo "refused: $REAL_DIR" ;;
esac
```

Remove fixtures created for the test. Re-check the real app is still running before reporting completion.

## Do not

- Attempt automatic unlock, credential injection, or any lock-screen bypass.
- Disable Gatekeeper or SIP, edit TCC.db, or re-sign the user's real app.
- Treat `capabilityUnavailable(...)` as proof that CUA is permanently broken.
- Treat System Events returning zero windows as proof that the app failed to launch.
- Run `pkill -f <AppName>` or `rm -rf /tmp/*`.
- Create CUA clients without closing the previous one.
- Apply `FF_SKIP_PERMISSION_GATE` to an app that does not read it.

## Report

State what was checked, the exact output that changed the diagnosis, and which step restored CUA. If the user had to unlock manually, say so. Do not report CUA as fixed until `getAppState` returns a real window.
