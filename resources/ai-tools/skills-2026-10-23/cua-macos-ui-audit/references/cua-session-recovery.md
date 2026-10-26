# CUA Session and Environment Recovery

Use this playbook when CUA loses state or the audit environment blocks interaction. Record the error, timestamp, PID, Bundle ID, current window, recovery action, and resulting evidence. A recovery is not complete until the target window and a fresh baseline are verified.

## 1. `SESSION_BUSY`

Symptom:

```text
SESSION_BUSY: close the previous client and wait for its cleanup
```

Actions:

1. Identify the client that is still active in the current node-repl session.
2. Close it if the SDK exposes `close()`.
3. Wait for cleanup, typically 800–1000 ms.
4. Create a new client and bind to the exact Bundle ID or app path.
5. Fetch a full AX baseline before acting.
6. Discard all old element IDs, screenshots, and geometry.

Adapt this pseudocode to the current SDK API; do not copy undefined variable names:

```js
try { await activeClient.close(); } catch (error) { /* record the error */ }
await new Promise(resolve => setTimeout(resolve, 900));

const client = await ComputerUse.createAppClient();
const app = await client.getApp(BUNDLE_ID);
const state = await app.getAXState({ disableDiffing: true, emit: false });
```

If the client does not expose `close()`, inspect the prototype or the SDK API. Do not create another client blindly.

A `SESSION_BUSY` error is not an application defect. If two consecutive reconnect attempts fail, stop and mark the affected surface `Blocked — CUA client unavailable`, preserving the error text and current screenshot.

## 2. `No active app state`, `user changed`, or stale coordinates

Actions:

1. Re-query full state before sending another action.
2. Use `disableDiffing` when supported and confirm the output contains a new accessibility baseline.
3. Rebuild the target map; never reuse an ID from a diff view or a previous screenshot.
4. Re-take the screenshot after the state settles.
5. If a real user or external process changed the app, stop and preserve the new state instead of forcing the old one.

Do not relaunch the application merely because CUA lost state. Relaunch only when the target window is genuinely gone and the launch path has been checked.

## 3. `menu no longer open`

Symptom:

```text
The menu containing this element is no longer open.
Re-query get_app_state before clicking.
```

Actions:

1. Re-fetch full AX state.
2. Reopen the menu and retry once with a fresh element ID.
3. If the menu still closes, enumerate it on the copy's PID — never through System Events `whose unix id is`, which has resolved the audit copy to the user's same-named instance:

   ```bash
   swift scripts/ax-menu.swift items "$PID" "MENU TITLE"
   ```

4. If that prints `AX_PRESS_OK_CHILDREN_EMPTY` or `AX_PRESS_OK_MENU_EMPTY`, AX cannot track this menu. Drive it with a real gesture, after asserting the copy owns the screen:

   ```bash
   scripts/front-assert.sh "$PID" X Y W H /tmp/pre.png
   scripts/open-menu.sh MENU_X MENU_Y [ITEM_X ITEM_Y]
   ```

5. Verify that the expected sheet, panel, or state change appeared.
6. Record that the action used the fallback path.
7. If Accessibility is denied, the PID is ambiguous, or the menu item cannot be found, record `Blocked` and do not guess with coordinates.

An empty `AXMenu.children` under a successful `AXPress` is an automation limitation, not a disabled menu. Nested submenus may not open from synthetic hover; if a real press-drag-release also fails to expand them, record `Blocked — submenu not reachable` with the attempt count.

## 4. Locked screen

Check the session lock state before CUA work and whenever a previously working window becomes unavailable:

```bash
ioreg -n Root -d1 -a 2>/dev/null | plutil -p - 2>/dev/null \
  | grep -i -E 'CGSSessionScreenIsLocked|IOConsoleLocked' || true
```

If either value is true:

1. Stop interacting; the missing window is an environment blocker, not an app defect.
2. Ask the user to unlock manually. Do not attempt automatic unlock.
3. After the user confirms unlock, re-check the lock attributes.
4. Start a bounded keep-awake process and record its PID:

   ```bash
   nohup caffeinate -dimsu -t 7200 >/tmp/cua-audit-caffeinate.log 2>&1 &
   CAFFEINATE_PID=$!
   ```

5. If the audit copy was launched while locked and has no window, clean up only that copy using the main skill's path-verified kill rules, then relaunch after unlock.
6. Stop the keep-awake process during cleanup:

   ```bash
   [ -n "${CAFFEINATE_PID:-}" ] && kill "$CAFFEINATE_PID" 2>/dev/null || true
   ```

Do not change the user's lock-screen or sleep settings.

## 5. New Bundle ID launches without a window

Check the following before declaring a launch failure:

- Is a TCC permission prompt covering the window? Ask the user to decide.
- Is the app waiting on its own first-run or permission gate?
- Did a direct `Contents/MacOS/...` launch create a process without a LaunchServices window?

Prefer launching the bundle through `open`:

```bash
open -n "$APP_COPY"
```

If the app documents an application-level gate flag, pass it through the launch environment:

```bash
open -n --env "APP_OWN_GATE_VAR=1" "$APP_COPY"
```

Replace `APP_OWN_GATE_VAR` with the app's documented launch variable. This flag skips only the application's own gate. It does **not** bypass macOS TCC, accessibility, screen recording, or folder permissions.

Then verify by exact executable path:

```bash
for p in $(pgrep -f -- "$APP_COPY/Contents/MacOS/"); do
  cmd=$(ps -p "$p" -o command= 2>/dev/null || true)
  case "$cmd" in
    "$APP_COPY/Contents/MacOS/"*) echo "PID=$p"; break ;;
  esac
done
```

A process without a visible target window is not enough to start an audit. If the window still does not appear after two checked launches, record the gate/TCC state and mark the surface `Blocked`.

## 6. Wrong-instance attribution and synthetic input

Symptom: evidence looks correct but describes the user's instance, or a shortcut created a file in the user's real Desktop, or a window you never opened moved.

Root causes, all observed:

- `every application process whose unix id is PID` resolved the audit copy to the user's same-named process.
- `screencapture -l <window-id>` returned a different window when two shared a geometry.
- CGEvents (`cliclick`, `key-combo`, AppleScript `keystroke`, CUA coordinate clicks) go to the frontmost app regardless of which PID you are auditing.
- AppleScript `click at {x, y}` passed through a borderless panel and hit the window behind it.

Recovery:

1. Stop; discard the affected captures rather than reinterpreting them.
2. Re-address everything by PID through AX: `scripts/ax-window.swift`, `scripts/ax-menu.swift`.
3. Before each screenshot and each synthetic event, run `scripts/front-assert.sh "$PID" X Y W H out.png` and require `OWNERSHIP=OK`.
4. If the assertion fails, raise the copy's window (`ax-window.swift raise`) and re-assert; if it still fails, another instance owns those pixels — record `Blocked — instance attribution`, do not proceed.
5. Re-collect the discarded rows and state in the report which batch was voided and why.
6. Disclose side effects on user data: stray files created by a mis-targeted shortcut were moved aside to a temp folder and reported, never silently deleted.

## 7. Recovery verification checklist

- [ ] Reconnect used one client and closed the prior one.
- [ ] Bind was to the exact copy Bundle ID or app path.
- [ ] Full AX baseline was fetched and old IDs were discarded.
- [ ] Target window belongs to the audit copy.
- [ ] Attribution came from AX addressed by PID, not from a System Events `whose unix id` lookup.
- [ ] The window is frontmost and has a current screenshot.
- [ ] The screenshot carries an `OWNERSHIP=OK` assertion for the copy's PID.
- [ ] Each synthetic click or shortcut was preceded by that same assertion.
- [ ] Menu fallback, if used, produced the expected UI.
- [ ] No TCC prompt was clicked or bypassed by the auditor.
- [ ] The recovery and its resulting evidence are recorded in the audit notes.

## 8. Evidence notes to retain

Record these fields for each recovery:

```text
timestamp:
error_text:
surface:
attempts:
pid:
bundle_id:
window_before:
recovery_action:
window_after:
screenshot_before:
screenshot_after:
ownership_assertion: OWNERSHIP=OK / not asserted
baseline_full: yes/no
verdict: Recovered | Blocked | Automation artifact
```
