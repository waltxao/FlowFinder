---
name: cua-macos-ui-audit
description: "Audit macOS native app UI on an isolated copy with Computer Use, parallel static code review, baseline tests, fresh screenshots, and AX inspection; classify automation artifacts separately from product defects. Use when asked to audit or fully verify a macOS UI, when the user challenges whether every screen was verified, when CUA reports SESSION_BUSY/no active state/menu no longer open, when System Events or AXPress resolves to the wrong app instance or fails to open a menu, when two same-named processes make PID attribution ambiguous or a capture must be proven to belong to the audit copy, when synthetic modifier shortcuts or dialog text input misfire, when the screen is locked or a new Bundle ID launches without a window, when AX menus look disabled or focus is unreliable, when theme switching or minimum window sizes must be accepted, or when audit evidence and a coverage matrix must be retained. 适用于 macOS 原生应用 UI 审计、CUA 走查、全量界面验收、PID 精确寻址与前台归属断言、菜单与快捷键合成输入、锁屏/权限门恢复、主题与最小窗口验收；不适用于 Web、iOS 或纯设计评审."
---

# CUA macOS UI Audit

## Overview

Run a read-only, evidence-backed audit of a native macOS app on an isolated copy. Combine static code review, baseline tests, Computer Use (CUA) behavior, fresh screenshots, and Accessibility (AX) state. The goal is a defensible verdict per surface, not a pile of screenshots or a list of code smells.

## When to Use

- Audit or fully verify a macOS app's windows, menus, tabs, settings, sheets, popovers, and important states.
- The user asks whether every screen was verified, or says to finish verification before fixing anything.
- Use CUA after AppleScript, System Events, or accessibility automation is unavailable or unreliable.
- The audit copy shares its process name with the user's running instance, so a System Events `whose unix id is PID` lookup or a window-id screenshot can resolve to the wrong process.
- A screenshot, click, or keystroke must be proven to belong to the audit copy before it counts as evidence.
- A menu must be opened or triggered and `AXPress` on the menu-bar item reports success while the menu stays unreadable or empty.
- A keyboard shortcut needs modifier flags, or typed/pasted text will not land in a dialog field.
- CUA reports `SESSION_BUSY`, `No active app state`, stale element IDs, or a menu that is no longer open.
- The Mac is locked, a fresh Bundle ID shows no window, or an application/TCC permission gate blocks the audit.
- Decide whether disabled menu items, stale focus, or odd AX output are product defects.
- Verify screenshot-coordinate interactions where window focus or geometry can change.
- Verify live light/dark switching, minimum window sizes, full screen, or high contrast.
- Prepare an isolated Bundle ID copy for a non-destructive audit.
- Cross-check live behavior against source code and baseline test results.
- Persist screenshots, AX state, logs, and a coverage matrix as evidence that outlives the temporary copy.

Do not use this skill for web or mobile UI, pure code review, design-only critique, or physical drag-feel acceptance. For deep effect rendering, drag mechanics, or XCTest-host isolation, delegate to the relevant existing skill; this skill retains ownership of the audit evidence policy.

## Non-Negotiables

1. **Audit before fixing.** Complete the read-only coverage pass first. Do not change product code until the coverage matrix and blocked list are delivered and the user explicitly authorizes fixes. Writing the audit report and evidence files is part of the audit, not a product fix.
2. **Never claim a full audit from targeted checks.** Maintain a surface-by-surface coverage matrix. Say "not verified" when it was not observed. A partial pass is not a full pass.
3. **Never operate the user's running app destructively.** Work on a copy you created. Record the source app, copy path, Bundle ID, executable path, PID, version, and window geometry.
4. **Focus and state precede judgment.** A menu item or control inspected while the app is inactive, another window is key, or a sheet is blocking interaction is **Unverified**, not a defect.
5. **Fresh evidence only.** Do not reuse a screenshot coordinate, AX element ID, PID, or window geometry after an action, relaunch, resize, scroll, focus change, theme change, CUA reconnect, or baseline refresh. Record the ownership assertion result with every screenshot so the capture is attributable to a PID.
6. **Do not bypass TCC.** If macOS asks for accessibility, screen recording, or folder access, stop and let the user decide. CUA availability is not permission to bypass the prompt.
7. **Only terminate the audit copy.** Verify the PID still maps to the copy's executable path before killing it. Never use `pkill` or a process name.
8. **Separate isolation artifacts from product findings.** Ad-hoc signing, a new Bundle ID, a new TCC identity, and shared app-support paths can change behavior; report that limitation.
9. **Keep one active CUA client.** Close the previous client and wait for cleanup before creating another. After every reconnect, fetch a full AX baseline and discard all old IDs, screenshots, and geometry.
10. **Environment blockers are not product defects.** A locked screen, application permission gate, TCC prompt, unavailable window, or menu-tracking failure is `Blocked` or an automation artifact until evidence proves otherwise.
11. **Evidence must outlive the temporary copy.** Copy screenshots, AX dumps, logs, and the report to a stable location and verify a manifest before deleting the audit directory or preferences.
12. **Synthetic events are never PID-targeted.** `AXUIElementCreateApplication(pid)` scopes *reads and attribute writes* to one process; CGEvents, `cliclick`, AppleScript `keystroke`, and CUA coordinate clicks go to whatever is frontmost. Assert the audit copy owns the pixels before every such event, or a shortcut can act on the user's real instance — and on the user's real files.

## Evidence Streams

Run three streams and keep their evidence separate:

| Stream | Purpose | Typical evidence |
|---|---|---|
| Static review | Find implementation paths, enablement predicates, labels, and likely failure modes | File/line references and quoted branches |
| Baseline tests | Establish whether a failure predates the audit | Exact command, test count, failures, and known flaky exclusions |
| CUA live audit | Prove what the user actually sees and can do | Current screenshot, AX summary, action result, PID and window state |

Static review and baseline tests can run in parallel. Do not run a test that launches the app or mutates its preferences concurrently with a CUA walk on the same copy. Use a separate copy or serialize the streams.

Record every artifact path, capture time, and the stream it belongs to. A screenshot that cannot be found after cleanup is not evidence.

## Workflow

### 1. Preflight, Coverage Contract, and Audit Gate

1. Confirm the exact app artifact and what "audit" means for this task.
2. Inventory running candidates by executable path and PID, not by display name or process name:

   ```bash
   ps -axo pid=,command= | grep -F "/Contents/MacOS/"
   ```

3. Record the source instance so you can prove it was untouched at the end. Expect this list to contain more instances than you launched: audit copies from earlier sessions often keep running and share the same window geometry, which is how a screenshot gets attributed to the wrong copy. Never treat an unfamiliar copy as yours and never terminate it without asking.
4. Check that the screen is unlocked before launching or binding CUA:

   ```bash
   ioreg -n Root -d1 -a 2>/dev/null | plutil -p - 2>/dev/null \
     | grep -i -E 'CGSSessionScreenIsLocked|IOConsoleLocked' || true
   ```

   If either value is true, stop and ask the user to unlock manually. Do not attempt automatic unlock. After the user unlocks, start `caffeinate -dimsu -t 7200`, record its PID, and stop it during cleanup.
5. Build a coverage matrix from the app's real menus, toolbar, tabs, windows, settings, sheets, popovers, and dialogs. Use at least:

   ```text
   | ID | Surface / state | Entry path | Preconditions | Evidence | AX / behavior | Verdict | Notes |
   ```

   Include the states the app actually supports: empty, populated, loading, error, selected, focused, inactive, light, dark, high contrast, default size, declared minimum size, and full screen where supported.
6. Mark each row as `Unverified` before evidence is collected. Never pre-label a surface `Verified`.
7. Record the declared minimum window size and supported appearances. They are audit rows, not optional checks.
8. **Audit gate:** do not edit product code until the matrix and `Blocked` list are complete, reported, and explicitly authorized for a fix pass.

### 2. Create the Audit Copy

Use the bundled helper:

```bash
scripts/prepare-audit-copy.sh "/absolute/path/App.app"
```

It prints `SOURCE_APP`, `ORIGINAL_BUNDLE_ID`, `VERIFY_DIR`, `APP_COPY`, `BUNDLE_ID`, and `EXECUTABLE`. The helper only copies and signs; it never launches, kills, or deletes the source.

Record before proceeding:

```text
source_app:
original_bundle_id:
verify_app:
bundle_id:
executable:
version:
window_geometry:
```

Rules:

- Copy to a unique temporary directory; never modify or re-sign the user's app.
- The new Bundle ID creates a new TCC identity and usually a new defaults domain. Request permissions normally; do not copy TCC state.
- The app may still share `~/Library/Application Support/...`, caches, or indexes across Bundle IDs. Keep audit fixtures in `/tmp` and never operate on user documents.
- If the app is sandboxed, note that changing the Bundle ID can change its container behavior.
- If re-signing breaks entitlements or the app fails to launch, stop and report the isolation limitation. Do not modify the original to work around it.

### 3. Set Test Preferences Safely

Prefer the copy's fresh defaults domain. When a scenario requires a preset:

1. Quit the audit copy before writing preferences.
2. Record each key's value, or record that it does not exist.
3. Write only the keys needed for the scenario, using the copy's unique Bundle ID.
4. Launch, verify the state took effect, and re-read the key.
5. At cleanup, quit first, restore each key, and delete keys that did not exist before.
6. Verify the restored values. Never delete the entire preferences domain.

Never write audit settings into the original Bundle ID's domain. If the app shares app-support data across Bundle IDs, do not use that shared area for destructive tests.

### 4. Launch and Bind to the Exact Copy

```bash
open -n "$APP_COPY"
```

If the app's own onboarding or permission gate prevents a window from appearing, the app may support an explicit launch flag that skips only that application-level gate:

```bash
open -n --env "APP_OWN_GATE_VAR=1" "$APP_COPY"
```

Replace `APP_OWN_GATE_VAR` with the app's documented launch variable. This does **not** bypass macOS TCC. If a system permission prompt appears, record it and let the user decide. Prefer `open` over directly executing `Contents/MacOS/...`; a direct binary launch can create no visible window and is not proof that the app failed.

Resolve the PID by exact executable path:

```bash
PID=""
for p in $(pgrep -f -- "$APP_COPY/Contents/MacOS/"); do
  cmd=$(ps -p "$p" -o command= 2>/dev/null || true)
  case "$cmd" in
    "$APP_COPY/Contents/MacOS/"*) PID="$p"; break ;;
  esac
done
[ -n "$PID" ] || { echo "Audit copy did not launch" >&2; exit 1; }
ps -p "$PID" -o pid=,rss=,command=
```

Bind CUA with the copy's absolute app path or unique Bundle ID. A launch tool reporting success does not prove the intended copy is frontmost; verify PID and window ownership. If no target window appears after two launches, inspect the app gate and TCC prompts and mark the surface `Blocked`; do not keep relaunching blindly.

**Address the copy by PID through the AX API, not through System Events.** `every application process whose unix id is PID` has returned the *user's* same-named instance instead of the audit copy, silently attributing an entire evidence batch to the wrong process. The binary name is unchanged by a new Bundle ID, so name-based and System Events process lookups stay ambiguous:

```bash
swift scripts/ax-window.swift list "$PID"          # titles, subroles, AXPosition, AXSize
swift scripts/ax-window.swift get "$PID" "WINDOW"  # geometry to capture
swift scripts/ax-menu.swift menus "$PID"           # menu-bar titles, read-only
```

Then prove the pixels before anything depends on them, and re-prove it after every activation, resize, or relaunch:

```bash
scripts/front-assert.sh "$PID" X Y W H capture.png
# TOP=16340 WIN=20975 OWNER=... (want 16340) -> capture.png
# OWNERSHIP=OK        -> usable evidence
# OWNERSHIP=MISMATCH  -> not evidence; another same-geometry window owns these pixels
```

`screencapture -l <window-id>` is not a substitute: it has returned a different window when two share a geometry. Capture the region and assert ownership.

### 5. CUA Session Lifecycle

Use one active CUA client per node-repl session. A stale client can outlive a tool call and make the next bind fail.

On `SESSION_BUSY`:

1. Close the previous client if the SDK exposes `close()`.
2. Wait for cleanup (about 800–1000 ms in verified runs).
3. Create a new client and bind to the copy by Bundle ID or exact app path.
4. Fetch a full AX baseline before acting.
5. Discard all old element IDs, screenshots, and window geometry.

If the client does not expose a close method, inspect its prototype or API instead of creating another client blindly. Do not mark the app as broken because the CUA client is busy.

On `No active app state` or `user changed`:

1. Re-query full state before sending another action; if supported, use `disableDiffing` to force a complete tree.
2. Rebuild the target map from the new baseline.
3. Do not relaunch the app merely because CUA lost state.
4. If a real user or external process changed the app, stop and preserve the new state.

Record each reconnect, close, and full-baseline refresh in the audit notes. Recovery is part of the evidence chain.

### 6. CUA State and Focus Discipline

Use one state loop throughout:

1. Fetch current AX state. Prefer a full baseline when starting, reconnecting, or recovering.
2. Take a screenshot after the UI settles.
3. Perform one meaningful action, or only deterministic actions with stable targets.
4. Re-fetch AX state.
5. Take a new screenshot after the resulting state settles.

Additional rules:

- **Element actions first, coordinates last.** Use an AX element action when the target and action are stable.
- **Coordinates are valid only for the current screenshot.** The target window must still belong to the copy and keep the same geometry. Re-screenshot after every state change.
- **Activate before inspecting menus.** If the app is backgrounded, click a tab strip or content area belonging to the target window, or otherwise bring that exact window forward. Verify `frontmost`, `AXMain`, or a focused target window before judging menu enablement.
- **A wall of disabled menu items usually indicates focus/activation loss.** Reacquire the correct window and inspect again. If the menu remains disabled, label the item `Unverified` until code evidence or a second trigger explains it.
- **Do not infer menu state from an inactive tree.** Menu items may be reported disabled when the menu has no active target.
- **Recover explicitly.** On `No active app state`, `user changed`, a closed menu, or stale-coordinate errors, reacquire full state, discard old IDs and screenshots, and rebuild the target map.
- **Stop after two failed recoveries** for the same surface. Preserve the error, timestamp, PID, screenshot, and exact menu/window path, then mark it `Blocked`.

### Menu-Tracking Fallback

CUA can lose a menu while the element list is being queried:

```text
The menu containing this element is no longer open.
Re-query get_app_state before clicking.
```

Use this sequence:

1. Re-fetch full AX state and reopen the menu.
2. Retry once with a fresh element ID.
3. Try the PID-exact AX path:

   ```bash
   swift scripts/ax-menu.swift items "$PID" "显示"      # list items + AXEnabled, then close
   swift scripts/ax-menu.swift press "$PID" "编辑" "批量重命名…"
   ```

   If it prints `AX_PRESS_OK_CHILDREN_EMPTY` or `AX_PRESS_OK_MENU_EMPTY`, AX cannot read that menu. This has been observed on real AppKit menus where `AXPress` returned success and `AXMenu.children` stayed empty — an automation limitation, **not** a disabled menu.
4. Drive the menu with a real mouse gesture instead, after asserting the copy owns the screen:

   ```bash
   scripts/front-assert.sh "$PID" X Y W H /tmp/pre.png
   swift scripts/ax-menu.swift menus "$PID"      # confirm the title exists
   scripts/open-menu.sh MENU_X MENU_Y            # press-drag-release, leaves it open
   scripts/open-menu.sh MENU_X MENU_Y ITEM_X ITEM_Y
   ```

   Take `MENU_X` from the menu-bar item's current `AXPosition`; the menu bar sits near `y=11` on a standard display. A synthetic hover does not expand a nested submenu — if the sub-item never appears after a real drag, record `Blocked`, not a defect.
5. Verify that the expected sheet, panel, or state change actually appeared. A successful AppleScript or `AXPress` return without the expected UI is not proof.
6. Record that the command was executed through a fallback path.
7. If Accessibility is denied or the menu item cannot be found, record `Blocked — accessibility unavailable` or `Blocked — menu path unresolved`; do not bypass TCC.

Do not fall back to a System Events menu click for this. It resolves the process by `unix id`, which has targeted the user's instance, and its `click menu item` success return proves nothing about the audit copy. For enablement, use a fresh AX tree plus code evidence.

If AppleScript or System Events is denied, do not treat that as an app failure. Use CUA if it is authorized and available. If neither path can interact, record `Blocked — accessibility unavailable`.

### Synthetic Input Boundaries

Keyboard and mouse injection is the least controllable part of an audit. These are the observed limits and the paths that replaced them:

**Modifier shortcuts.** `cliclick` has no `ke:` verb and its `kd:/ku:` press/release bookkeeping is easy to leave half-applied, so a stuck modifier corrupts every later click. `osascript ... keystroke "n" using {command down, shift down}` works but is not PID-scoped. Use the CGEvent helper, which sets `CGEventFlags` on both down and up:

```bash
swift scripts/key-combo.swift g cmd,shift --dry-run   # resolve key + flags, post nothing
scripts/front-assert.sh "$PID" X Y W H /tmp/pre.png    # prove the copy is frontmost
swift scripts/key-combo.swift g cmd,shift
```

Run the assertion every time. A posted shortcut has no PID target: in a recorded audit, `⇧⌘N` created `未命名文件夹` in the user's real Desktop because the user's instance was frontmost, not the copy. Disclose such side effects in the report; move stray files aside rather than deleting them.

**Text into dialog fields.** `cliclick t:` and `⌘V` paste have both failed to land characters in a Connect-to-Server field, and a Chinese pinyin input source converted a leading `/` into `、` before the field saw it. When a value cannot be entered, do not judge the field from the failed attempt: use the app's own state, code evidence, or ask the user to type it, and record the row `Blocked — synthetic text input unreliable`.

**Clicks that miss their target.** AppleScript `click at {x, y}` has hit the window *behind* a borderless panel, submitting a dialog prematurely. Real mouse events (`cliclick c:x,y`) land on the panel. Coordinates are only valid for the screenshot they came from — re-read geometry and re-assert after any open, close, resize, or activation.

**Activation and teardown.** Raise and close windows through AX on the copy, which is PID-scoped and leaves no menu tracking behind:

```bash
swift scripts/ax-window.swift raise "$PID" "WINDOW TITLE"   # kAXMain + AXRaise
swift scripts/ax-window.swift close "$PID" "WINDOW TITLE"   # AXCloseButton press
swift scripts/ax-menu.swift items "$PID" "显示"               # inspect, then AXCancel
```

Close extra tool windows before judging menus: while a floating tool window held key status, every item in one app menu reported `enabled=false`, and the two captures taken from it were reclassified as automation artifacts rather than defects.

### 7. Audit Every Claimed Surface

For each coverage row, collect:

```text
surface:
entry_path:
preconditions:
screenshot:
AX_summary:
expected:
actual:
verdict: Verified | Unverified | Blocked
notes:
```

Audit behavior, not just appearance:

- Check enabled/disabled, selected, focused, hover/pressed, empty, loading, error, and inactive states that exist.
- Open menus while the correct window is active; verify item labels, check marks, enablement, and keyboard equivalents where applicable.
- Exercise tabs, sheets, popovers, settings, and confirmation dialogs through their real entry paths.
- Recheck after any action that changes selection, directory, active pane, window size, appearance, or modal state.
- Use screenshots as visual evidence and AX as state evidence. Neither one alone proves a control worked. If one is missing, the row is not `Verified`.
- Do not invent screens, states, or requirements that the app does not expose.

### 8. Appearance and Geometry Acceptance

Treat appearance and window size as first-class acceptance surfaces.

**Theme switching**

1. Start in light, capture the settled window and AX state.
2. Switch to dark, wait for a stable frame, capture again.
3. Switch back to light, wait, capture again.
4. Restart the copy once and capture the same light state.
5. Compare all four states. A mismatch that appears only after a live switch, while restart is normal, is still a confirmed runtime theme-refresh defect; it is not a screenshot artifact.
6. Record whether the mismatch persists after settle and whether restart clears it.

Do not accept a single dark screenshot or a single restart screenshot as proof that live switching works.

**Window geometry**

1. Test the app's default size and the declared minimum size. If the design spec requires a specific constrained size, test that exact size.
2. Set the size on the copy's PID through AX, then read back what the window accepted:

   ```bash
   swift scripts/ax-window.swift set-size "$PID" "WINDOW TITLE" 1060 700
   # SET_SIZE err=0
   # ACTUAL POS=260,30 SIZE=1060x700      <- only this line is evidence
   ```

   Do not size the window with System Events here: it selects the process by `unix id`, so under a duplicate instance it can resize the user's window instead. A requested size is not evidence that the window accepted it; neither is `SET_SIZE err=0`.
3. Capture the constrained window and inspect toolbar rows, tab strip, search controls, columns, details, and empty states.
4. Verify all required columns and controls are present, reachable, and not clipped or overlapping.
5. Test full screen and high contrast when the app supports them.
6. Restore the original geometry, appearance, and preferences before cleanup.

A minimum-size layout break, missing column, or clipped toolbar is a product finding when the window is confirmed to be at the declared size. Do not dismiss it as a screenshot or scaling artifact without evidence.

### 9. Classify Findings

Use these labels consistently:

| Verdict | Criteria |
|---|---|
| **Confirmed** | Reproduced on the correct PID/copy with the target window active, a fresh screenshot or state, and code or a second behavioral path explaining the result. |
| **Suspected** | Visually or behaviorally plausible, but one required condition is missing (reproduction, code evidence, or a clean state). |
| **Automation artifact** | Caused by inactive focus, stale IDs/screenshot, wrong instance, loading transition, overlay, menu-tracking loss, or coordinate reuse. State what caused it. |
| **Blocked** | Permissions, locked screen, unavailable window, menu path failure, or repeated state loss prevented a reliable check. Include the exact unblock action. |

Before calling a live observation a defect:

1. Restore the intended window and focus.
2. Reacquire state and take a new screenshot.
3. Reproduce through a second path when available.
4. Compare with source logic and baseline tests.
5. Check whether isolation (new Bundle ID, ad-hoc signing, clean defaults) explains the result.

Never dismiss a visible defect as an artifact merely because automation is inconvenient. If the live evidence is clear but code evidence is absent, keep it `Confirmed` or `Suspected` with the missing evidence stated.

### 10. Report and Coverage Gate

Write the report before changing product code. Include:

- Coverage matrix with every row's verdict, including `Unverified`.
- A separate `Blocked` table with attempt count, exact blocker, observed state, unblock action, and retest plan.
- Exact artifact path, Bundle ID, version, executable, PID, and window geometry.
- Baseline test command, executed count, failures, and known exclusions.
- Each finding: severity, surface, reproduction, expected/actual, screenshot, AX excerpt, code reference, and classification.
- Isolation caveats and permission events.
- Explicit list of surfaces not audited.
- Evidence manifest and stable evidence paths.

Required final wording:

```text
Coverage: X verified, Y blocked, Z unverified, W not audited.
This is not a full audit unless every coverage row has current evidence.
```

No claim such as "all UI passed" is allowed unless every claimed row has evidence. Only after the report is complete should you propose fixes. If the user said "verify everything before fixing," deliver the matrix and `Blocked` list and wait for explicit acknowledgement before any product code change. A later fix pass must rerun the affected coverage rows and baseline checks.

### 11. Evidence Retention and Cleanup

Before deleting anything:

1. Create a stable evidence directory outside `/tmp` (for example under the audit report's `images/` or `artifacts/` directory).
2. Copy screenshots, AX dumps, logs, and the report there. Copy, do not move, until the manifest is verified.
3. Write a manifest with file name, capture time, pixel dimensions, PID/Bundle ID, window geometry, surface, and what the file proves.
4. Re-read each image and verify its dimensions with `sips -g pixelWidth -g pixelHeight`.
5. Verify that every referenced artifact exists. Do not clean the audit copy until this check passes.
6. Keep evidence local unless the user authorizes sharing. Redact user paths or file names before external upload.

Then stop only the audit copy:

```bash
cmd=$(ps -p "$PID" -o command= 2>/dev/null || true)
case "$cmd" in
  "$APP_COPY/Contents/MacOS/"*) kill "$PID" ;;
  *) echo "Refusing to kill PID $PID: unexpected command" >&2 ;;
esac
```

Stop the keep-awake process if you started one:

```bash
[ -n "${CAFFEINATE_PID:-}" ] && kill "$CAFFEINATE_PID" 2>/dev/null || true
```

Verify the original instance is still running, restore preference keys and window geometry, and then remove only your own temporary audit directory:

```bash
case "$VERIFY_DIR" in
  /tmp/cua-macos-ui-audit.*) rm -rf "$VERIFY_DIR" ;;
  *) echo "Refusing to remove unexpected path: $VERIFY_DIR" >&2 ;;
esac
```

Report whether cleanup, preference restoration, geometry restoration, and evidence retention succeeded. Never delete the stable evidence directory as part of cleanup.

## Common False Positives

| Signal | First interpretation | Required action |
|---|---|---|
| All or many menu items disabled | App/window not active, or another window is key | Activate the exact target window, reacquire AX, inspect again |
| Menu item disabled while another control works | Different target/focus context | Verify key window and selection before judging |
| `SESSION_BUSY` from CUA | A previous client is still active | Close it, wait for cleanup, create a new client, fetch a full baseline |
| Menu closes during state query | Menu tracking ended; not proof the command is disabled | Reopen with fresh state; retry once; use the PID-exact AX path, then a real press-drag-release, and verify the resulting UI |
| `AXPress` on a menu-bar item succeeds but `AXMenu.children` is empty | AX cannot track that menu | Open it with a real press-drag-release and screenshot; never report the menu as disabled from this |
| Every item in a menu reports disabled | A tool or panel window is the key window | Close the extra windows, raise the target window by PID, reopen the menu |
| Screenshot looks right but came from another copy | Two windows share one geometry; `screencapture -l` picked the other one | Capture the region and run `front-assert.sh`; discard captures without an `OWNERSHIP=OK` line |
| Typed or pasted text never appears in a field | Synthetic text input fails; an IME can substitute characters | Do not judge the field; use state or code evidence, or ask the user to type it |
| `click at {x, y}` triggers the wrong control | The click passed through a borderless panel to the window behind | Use real mouse events at coordinates read from the current geometry |
| Click has no visible effect | Stale screenshot, wrong instance, overlay, or coordinate drift | Reacquire state, confirm PID, take a fresh screenshot, retry once by AX |
| AX tree looks empty or unstable | Baseline changed, app is loading, or another window owns focus | Refresh full state; wait for stable UI; do not diagnose from the first tree |
| Light/dark switch looks broken | Transition not settled or a real theme refresh bug | Wait for settle; capture; switch back; restart once; record both |
| Screen is locked or CUA cannot unlock | Environment blocker, not an app defect | Ask the user to unlock; record `Blocked`; start keep-awake after unlock |
| New Bundle ID has no window | App-level gate, TCC prompt, or direct-binary launch | Prefer `open`; use only the app's documented gate flag; let the user decide on TCC |
| Minimum-size layout overlaps | A real constrained-layout defect, or a false window size | Re-read accepted AX size; capture again; verify against spec before classifying |
| Screenshot shows a system permission prompt | New Bundle ID/TCC identity | Record the overlay; ask the user to decide; never click blindly |
| Test failure appears during audit | Existing baseline failure or audit interference | Run the baseline separately; compare failure names and counts |

## Completion Checklist

- [ ] Coverage matrix and `Blocked` list exist; every claimed surface has a verdict.
- [ ] No "all UI passed" claim is made while any row is `Unverified`, `Blocked`, or unaudited.
- [ ] Target copy, Bundle ID, executable path, PID, version, and accepted geometry recorded.
- [ ] Source instance was never modified, re-signed, or terminated.
- [ ] Screen was unlocked before CUA work; keep-awake process was stopped at cleanup.
- [ ] One CUA client was active at a time; every reconnect used a full baseline and discarded old IDs.
- [ ] Application gate and TCC prompts are separated; neither was bypassed.
- [ ] Menu judgments used the correct active window; menu-tracking fallback was verified by its resulting UI.
- [ ] Every menu and window operation addressed the copy by PID through AX; no System Events `whose unix id` lookup decided attribution.
- [ ] Every screenshot has an `OWNERSHIP=OK` assertion for the copy's PID in the manifest.
- [ ] Each synthetic click or shortcut was preceded by a fresh ownership assertion; side effects on user files or the user's instance are disclosed.
- [ ] No menu was judged disabled from an empty `AXPress` result or while a tool window was key.
- [ ] Static evidence, baseline tests, and live CUA evidence are separated.
- [ ] Light → dark → light and restart comparison completed; persistent vs transient mismatch recorded.
- [ ] Default and declared minimum window sizes tested; geometry restored.
- [ ] Every screenshot and AX artifact is in the evidence manifest and exists at its reported path.
- [ ] Findings were reported before any product code change.
- [ ] Audit PID stopped only after path verification; temporary copy, preferences, and keep-awake process cleaned up.
- [ ] Stable evidence directory was retained.

## Resources

- `scripts/prepare-audit-copy.sh` — copy an app to a unique temp directory, assign a unique Bundle ID, ad-hoc re-sign it, and print the paths needed for CUA.
- `scripts/ax-window.swift` — PID-exact window list / geometry / `set-size` / raise / close through `AXUIElementCreateApplication`; prints the re-read size.
- `scripts/ax-menu.swift` — PID-exact menu-bar enumeration, item listing with `AXEnabled` and key equivalents, and item press; reports `AX_PRESS_OK_CHILDREN_EMPTY` when AX cannot read the menu and closes the menu after inspection.
- `scripts/front-assert.sh` — capture a region and prove the topmost window under it belongs to the copy's PID (`OWNERSHIP=OK` / `MISMATCH`).
- `scripts/open-menu.sh` — open a menu bar title, or reach one of its items, with a real press-drag-release gesture when AX cannot track the menu.
- `scripts/key-combo.swift` — post a modifier shortcut through CGEvent with explicit `CGEventFlags`; `--dry-run` resolves the key and flags without touching the machine.
- `references/pid-exact-automation.md` — failed command → verified replacement table with copy-paste recipes for targeting, menus, geometry, and synthetic input.
- `references/cua-session-recovery.md` — verified recovery paths for `SESSION_BUSY`, lost state, closed menus, locked screens, permission gates, and no-window launches.
- `references/audit-report-template.md` — coverage matrix, finding, blocked-item, evidence-manifest, and completion-language templates.
