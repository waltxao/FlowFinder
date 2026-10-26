---
name: macos-native-ui-verification
description: "Visually and behaviorally verify a native macOS app build through Computer Use, including exact-artifact launch, AX and screenshot state recovery, per-screen visual acceptance, and main-thread performance sampling. Use when asked to audit all macOS UI screens, verify a desktop build, or when Computer Use reports 'No active app state', invalid element IDs, stale screenshot coordinates, or lost focus. 适用于 macOS 原生应用逐界面视觉验收、AX/截图状态失效恢复、构建产物核验和性能采样。"
---

# macOS Native UI Verification

## Overview

Run a reproducible, evidence-backed UI/UX audit of a native macOS app through Computer Use. Treat the build artifact, process ID, frontmost focus, accessibility tree, and screenshot as one evidence chain. Recover the chain explicitly when any part becomes stale; never keep clicking through an invalid state.

## When to Use

- Audit every reachable window, sheet, panel, popover, menu, and important UI state of a macOS app.
- Verify the build the user actually opens, including a Desktop deployment copy rather than only a DerivedData build.
- Compare live rendering with a design spec, screenshot, or prior version.
- Diagnose Computer Use failures such as `No active app state`, invalid element IDs, stale screenshot coordinates, lost focus, or repeated state loss.
- Collect a main-thread sample as supplementary evidence for a UI performance concern.

Do not use this skill for web or mobile UI, isolated glow/shadow/blur/rounded-corner primitive diagnosis, physical drag-feel acceptance, AppKit hit-test debugging, or drag-frame optimization. Use `appkit-visual-effect-verification` for effect-level rendering defects, and the relevant AppKit regression or drag-performance workflow for those areas.

## Non-Negotiables

- Prefer read-only, reversible actions. Do not modify user files, settings, permissions, or data; do not quit or relaunch the user's app without permission.
- Verify the exact artifact the user cares about. Record its absolute path, bundle ID, version, PID, and build or modification time.
- Refresh state before each decision, not only at the start of the session.
- Never reuse element IDs or screenshot coordinates across a new baseline, PID, window geometry, or app instance.
- Treat automation errors as instrumentation failures until the live UI proves otherwise.
- Do not claim a screen was verified without a screenshot plus enough accessibility state or behavioral evidence to identify what was shown.
- Do not claim frame rate from screenshots, static tests, or `sample`. Treat `sample` as CPU evidence only.

## Preflight: Lock the Artifact

1. Identify the app bundle to inspect. When the user asks about "the app" or a Desktop copy, inspect that copy, not an unrelated Debug build.
2. Check for running instances with `pgrep -fl "<executable-name>"`. If several copies or stale instances exist, identify the correct PID and ask before terminating anything.
3. Bring the exact bundle forward with its absolute path:

   ```bash
   open "/absolute/path/App.app"
   ```

   Avoid ambiguous display-name launches when multiple copies exist.
4. Create one Computer Use client per fresh `node_repl` session and bind the app by exact path or bundle identifier:

   ```js
   var cua = await (await import("@ali/qoder-cu-sdk")).ComputerUse.createAppClient();
   var app = await cua.getApp("<exact-app-path-or-bundle-id>");
   await app.getAXState({ disableDiffing: true });
   await app.getScreenshot();
   ```

5. Record the PID, window title, bundle path, window size, display arrangement, and date. Confirm the visible app is not a background instance.
6. If the user is actively using the app, wait until they stop before automating.

## Establish and Refresh State

Use accessibility elements for actions whenever possible. Use screenshots for visual evidence, and use coordinates only after a current screenshot and unchanged window geometry.

Follow this loop for every interface:

1. Fetch the latest AX state and apply diffs to the current element-ID map.
2. Take a screenshot after the state settles.
3. Perform one focused action, or batch only deterministic actions whose targets are stable.
4. Fetch AX state again before choosing the next target.
5. Capture a new screenshot only after the resulting UI has settled.

A screenshot never supplies element IDs. Fetch AX state before any index-based action. A full tree replaces the mapping; discard every prior ID, even if a number reappears.

### Recovery Matrix

| Signal | Interpretation | Required response |
|---|---|---|
| `No active app state. Call get_app_state first.` | The app binding or state context is stale. | Reacquire with `cua.getApp("<exact-app-path>")` or the bundle ID, then request a full AX baseline. Discard old IDs and screenshots. |
| `New accessibility baseline` or a full tree | Element numbering has been rebuilt. | Discard all previous IDs and rebuild targets from the returned full tree. |
| Removed or reused element ID | The old reference no longer identifies the same element. | Stop using that ID immediately and select from the latest state. |
| `Screenshot coordinates require a current screenshot whose target window still belongs to the app and has unchanged geometry.` | The screenshot or window geometry is stale. | Re-query AX state and take a fresh screenshot. Do not tune or retry the old coordinates. |
| `The user is still interacting with '<App>'.` | The user has control or the app is temporarily unavailable to automation. | Stop. Wait at least five seconds, then reacquire. If it repeats, report the task as blocked rather than racing the user. |
| Only the menu bar appears, `mainWindow` is nil, or menu items are disabled | The app may be backgrounded or another window may own key focus. | Bring the exact app forward with `open`, verify the visible window, then reacquire a full baseline. Do not report disabled menus as a product bug yet. |
| A different PID or app path appears | Another instance replaced or joined the target. | Confirm the correct copy, discard all state, and rebuild the baseline for the intended PID. |
| A pane or list initially shows zero items after launch | The app may still be loading or the folder may genuinely be empty. | Wait, refresh, and verify stable empty-state text before recording it as an empty state or a defect. |

Stop after two failed recovery attempts for the same state. Preserve the error text, PID, screenshot, and last known window title; report a concrete blocker instead of looping.

When a terminal command, debugger attach, or another app changes foreground focus, reopen the exact app and reacquire its full baseline before continuing. If `lldb` was attached, detach it and let the main thread settle. Do not leave a debugger attached.

## Inventory Every Surface

Build the surface list from the app's actual menus, toolbar, and windows; do not invent screens. At minimum inspect what exists from this set:

- Main window in dual-pane and single-pane modes.
- Sidebar, toolbar, tab strip, breadcrumb/path controls, content list or grid, and footer/details region.
- Empty, loading, error, populated, selected, focused, and inactive states.
- Details collapsed and expanded, including long paths and missing metadata.
- Tool popover, overflow menus, and context menus.
- Settings pages and every visible section.
- Search center with empty, results, no-results, and error states.
- Duplicate scan before, during, and after a scan, including no-result handling.
- Batch rename, task center, file info, conflict sheets, and confirmation dialogs that the app actually exposes.
- Light and dark appearance where the app supports both; keyboard focus and accessibility labels where relevant.

For each surface, record:

- Entry path and preconditions.
- Screenshot reference and AX summary.
- Expected result from the product requirement or visual reference.
- Actual result.
- Verdict: `Verified`, `Unverified`, or `Blocked`.

Do not infer visual quality from source tokens alone. A radius, color, or blur constant does not prove the live composition is correct. Inspect the rendered window at the actual size and appearance.

## Visual and Behavioral Checks

- Check the radius hierarchy: window, cards, popovers, sheets, controls, and nested containers. Flag inverted nesting, mismatched radii, clipping, and accidental double frames.
- Check spacing alignment, toolbar density, label truncation, icon optical alignment, and overlapping content at the tested window sizes.
- Check selection, active/inactive pane, hover, pressed, disabled, focus, warning, error, and empty states.
- Check that active-pane emphasis does not overpower content or reduce text contrast.
- Check system appearance behavior: window background, sidebar, separators, secondary labels, and accent use in both light and dark modes.
- Check pointer affordances and hit targets for visible controls; do not validate physical feel through synthetic input.
- Check keyboard flow, default and destructive button order, Escape behavior, and whether menu enablement tracks the key window.
- Check dialogs, sheets, and popovers for correct attachment, initial focus, clipping, and restoration of the previous window.
- Ask one focused question only when a visual issue requires a product decision. Keep the audit read-only until that decision is confirmed.

## Performance Smoke

Use `sample` only after identifying the exact running PID and the UI state under test:

```bash
sample <pid> 3 -file /tmp/<app>-ui-sample.txt
```

- Pair a baseline with a defined interaction when comparing CPU cost.
- Inspect the main-thread call graph, not raw top-of-stack counts across idle worker threads.
- Record the active screen, whether a menu or sheet was open, window size, and the action being performed.
- Do not sample during an unrelated open menu or modal unless that state is the subject of the test.
- Restore the app to the foreground and reacquire state after terminal or debugger work.

Report `sample` results as CPU-stack evidence. For frame pacing, real drag feel, or 60/120 Hz acceptance, use the AppKit drag-performance and manual-acceptance workflows.

## Evidence and Completion

Name or reference screenshots by app, surface, state, appearance, and time. Keep raw samples and relevant AX excerpts. In the final report, include:

- Exact app path, bundle ID, version, PID, and build time.
- Screenshots and state evidence for every claimed surface.
- Verified findings, unresolved findings, and blocked automation paths.
- Commands and sample log paths when performance evidence is included.
- Any state intentionally changed and whether it was restored.

Use these labels:

- **Verified**: observed in the correct build with a current screenshot and state or behavioral evidence.
- **Unverified**: plausible from code or a partial view but not observed live.
- **Blocked**: automation, focus, permissions, or the environment prevented a reliable check.

Never claim "all screens reviewed" when only a subset has evidence. Never claim the user's copy is fixed when only another build path was tested.

## Pitfalls

- Inspecting a Debug or DerivedData copy while the user is looking at a Desktop deployment.
- Assuming the first screenshot is current after the app was relaunched, resized, or backgrounded.
- Clicking an old element index after a full-tree or baseline notice.
- Retrying stale screenshot coordinates instead of re-querying state.
- Repeating a click after `No active app state` without reacquiring the app.
- Treating a disabled menu or missing window as a product regression before restoring key focus.
- Treating a transient empty list during loading as a final empty state.
- Reusing a previous PID after the app relaunches.
- Continuing automation while the user is interacting with the app.
- Sampling the main thread during an unrelated menu or modal and attributing it to the app's normal workload.
- Leaving a terminal or debugger in front and then blaming accessibility for missing windows.
- Claiming visual correctness from design tokens or screenshots of the wrong build.
