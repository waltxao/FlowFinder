# PID-exact automation: failed command → verified replacement

Load this when an automation command silently targets the wrong process, a menu will not open, or a shortcut or keystroke misfires. Every row below replaced a command that had already produced bad audit evidence; run the replacement, then still verify the resulting UI.

Scope note: `AXUIElementCreateApplication(pid)` scopes **attribute reads and writes** to one process. It does **not** scope injected input. CGEvents, `cliclick`, AppleScript `keystroke`, and coordinate clicks reach the frontmost app whatever you believe is frontmost.

## Replacement table

| Failing or unsafe command | Observed outcome | Replacement |
|---|---|---|
| `tell application "System Events"` / `every application process whose unix id is PID` | With the audit copy and the user's app both running, this resolved the copy's PID to the user's PID; an entire main-window evidence batch was voided and re-shot | `swift scripts/ax-window.swift` / `ax-menu.swift` — `AXUIElementCreateApplication(pid)` on the PID resolved from the copy's executable path |
| `set frontmost of (first application process whose unix id is PID) to true`, then judge the menu | Menu items reported disabled because a tool window was key, not because the command was unavailable | `swift scripts/ax-window.swift raise "$PID" "TITLE"` (`kAXMain` + `AXRaise`), then `front-assert.sh` |
| `set size of window 1 to {W, H}` in System Events | Ambiguous under duplicate instances — it can resize the user's window | `swift scripts/ax-window.swift set-size "$PID" "TITLE" W H`, then read the printed `ACTUAL POS=… SIZE=…` |
| `click menu item "X" of menu 1 of menu bar item "Y" of menu bar 1` | AppleScript returns the item reference even when the click never acted on the copy | `swift scripts/ax-menu.swift press "$PID" "Y" "X"`, then confirm the sheet/panel actually appeared |
| `AXUIElementPerformAction(menuBarItem, kAXPressAction)` | Returns success while `AXMenu.children` stays empty, so no item can be read or triggered | `scripts/open-menu.sh MENU_X MENU_Y [ITEM_X ITEM_Y]` — a real press-drag-release the menu tracker honours |
| `cliclick ke:2,56` | `ke:` is not a cliclick verb — the call silently does nothing intended | `swift scripts/key-combo.swift KEY [cmd,alt,shift,ctrl]`, which sets `CGEventFlags` on both keydown and keyup |
| `cliclick kd:cmd kd:shift g ku:shift ku:cmd` | Works but leaves a modifier stuck if any step fails, corrupting every later event | Same `key-combo.swift`; verify with `--dry-run` first |
| `osascript -e '… keystroke "n" using {command down, shift down}'` | Not PID-scoped: `⇧⌘N` created `未命名文件夹` on the user's real Desktop | Assert `OWNERSHIP=OK` for the copy, then `key-combo.swift`; disclose any side effect |
| `click at {x, y}` in AppleScript | Clicked through a borderless panel onto the window behind it and submitted a dialog early | `cliclick c:x,y` at coordinates read from the current geometry |
| `cliclick t:"some text"` / `⌘V` into a dialog field | Characters never landed; a pinyin input source turned a leading `/` into `、` | Judge the field from app state or code, or ask the user to type; record `Blocked — synthetic text input unreliable` |
| `screencapture -o -l <window-id>` | Returned a different window when two shared the same geometry | `scripts/front-assert.sh "$PID" X Y W H out.png` — region capture plus ownership assertion |

## Order of operations for one surface

```bash
PID=…                                   # resolved from "$APP_COPY/Contents/MacOS/", not by name
swift scripts/ax-window.swift list "$PID"
swift scripts/ax-window.swift raise "$PID" "FlowFinder"
swift scripts/ax-window.swift get  "$PID" "FlowFinder"     # -> POS=x,y SIZE=WxH
scripts/front-assert.sh "$PID" X Y W H shot.png            # -> OWNERSHIP=OK
# … one action …
scripts/front-assert.sh "$PID" X Y W H shot-after.png      # re-assert; never reuse the old region
```

Read the menu bar from AX first; only fall back to the gesture path when it reports an empty menu:

```bash
swift scripts/ax-menu.swift menus "$PID"                   # titles only, nothing opened
swift scripts/ax-menu.swift items "$PID" "显示"               # items + AXEnabled, closes after
swift scripts/ax-menu.swift press "$PID" "编辑" "批量重命名…"
# AX_PRESS_OK_CHILDREN_EMPTY ->
scripts/open-menu.sh 250 11                                # press-drag-release on the title; menu stays open
scripts/open-menu.sh --click 250 11                        # plain click, if the tracker needs one
scripts/open-menu.sh 250 11 300 140                        # press-drag-release onto the item
```

## Interpreting the output

| Output | Meaning | Action |
|---|---|---|
| `OWNERSHIP=OK` | The pixels belong to the copy | Screenshot is usable evidence |
| `OWNERSHIP=MISMATCH`, `TOP=other PID` | Another instance or window owns them | Discard the capture; raise the copy and re-assert |
| `AX_PRESS_OK_CHILDREN_EMPTY` / `AX_PRESS_OK_MENU_EMPTY` | AX cannot track this menu | Gesture path; never report the menu as disabled |
| `NO_SUBMENU` after a real drag | Nested submenu not reachable by injection | `Blocked — submenu not reachable`, with attempt count |
| `SET_SIZE err=0` but a different `ACTUAL` | The window clamped the request | Judge layout at `ACTUAL`; a `minSize` clamp is itself a finding |
| `WIN_NOT_FOUND` | Title changed or wrong PID | Re-list windows; do not fall back to `window 1` |
| `POSTED key=…` with no visible change | Wrong app was frontmost, or the shortcut is unbound | Re-assert ownership, then check the key equivalent in code |

`key-combo.swift --dry-run` and `ax-menu.swift menus` post and open nothing — use them to sanity-check arguments before touching a live UI.

## Residual risks

- All three Swift helpers need Accessibility granted to the process that runs them. A denial is an environment blocker, not an app defect; record `Blocked — accessibility unavailable`.
- `swift file.swift` compiles per invocation, so expect a second or two of latency; it does not cache between runs.
- Ad-hoc signing plus a new Bundle ID can change gate and container behaviour; see `references/audit-report-template.md` for the isolation caveats block.
