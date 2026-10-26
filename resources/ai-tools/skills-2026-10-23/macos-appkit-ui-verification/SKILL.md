---
name: macos-appkit-ui-verification
description: "Verify macOS AppKit UI behavior when synthetic CGEvents, Accessibility automation, or XCTest hosts are unreliable. Use for drag/drop, hit testing, window gestures, AppKit self-test runs, NSWorkspace/LaunchServices test hangs, 合成拖拽、坐标校准、测试宿主卡住、以及转人工手感验收."
---

# macOS AppKit UI Verification

## Overview

Use an evidence ladder, not a single test run. Separate what pure logic proves, what the real executable proves, what synthetic input can prove, and what only a person can validate. The goal is to close UI work honestly without mistaking automation artifacts for product bugs or product success.

## When to Use

Use this skill when:

- Verifying macOS AppKit interactions that depend on real mouse input, WindowServer, LaunchServices, or multi-display coordinates.
- Synthetic CGEvents, AppleScript, or Accessibility automation produce inconsistent drag, click, or drop results.
- An XCTest host hangs, takes tens of seconds per test, or stalls during sidebar/list layout.
- A UI task needs a manual acceptance handoff and an explicit "verified / unverified" record.

Do not use it for pure logic tests, web UI, or cases where normal UI automation already reproduces behavior reliably.

## Evidence Ladder

Work top-down and stop at the first level that is sufficient for the claim being made.

1. **Pure logic tests**
   - Test decision tables, hit-test policies, geometry conversion, drop resolution, and state transitions without AppKit.
   - Record the exact command, test count, and failure count.

2. **Real-executable self-test**
   - Run the app with its self-test and permission-gate bypass flags when available, for example:
     `<APP>_SELFTEST=1 <APP>_SKIP_PERMISSION_GATE=1 <path-to-app>/Contents/MacOS/<app>`
   - Confirm the build artifact path and checksum used for the run.
   - Record the assertion count and confirm zero failures.

3. **Time-boxed synthetic input**
   - Use synthetic mouse input only to gather evidence about coordinates, hit testing, or state transitions.
   - Do not claim physical feel, smoothness, or display frame rate from synthetic input.
   - Allow at most two calibration attempts. Stop and switch to manual verification when delivery is not deterministic.

4. **Manual acceptance**
   - Validate drag feel, cross-window behavior, occlusion edge cases, visual fidelity, and real frame pacing.
   - Ask the user to report per-item pass/fail. Never substitute a successful synthetic script for this step.

## Synthetic Input Calibration

Check these in order before concluding that the app is broken.

### Coordinates

- Obtain window bounds with `CGWindowListCopyWindowInfo`; its bounds use a top-left screen origin.
- Remember that CGEvent screen coordinates also use a top-left origin, while AppKit window coordinates and `NSEvent.mouseLocation` use a bottom-left origin.
- Convert with `window.convertPoint(fromScreen:)` or `window.convertPoint(toScreen:)`; never compare raw coordinate spaces.
- Handle secondary displays explicitly. A window can be at a large x offset on another display.
- Inside event handlers, prefer `event.locationInWindow` over `NSEvent.mouseLocation` when the event path may be synthetic. `NSEvent.mouseLocation` may reflect the hardware cursor rather than the posted event's position.

### Delivery and occlusion

- Activate the app and confirm it is frontmost before posting events.
- Dismiss TCC or accessibility prompts; they can consume otherwise valid clicks.
- Check for Finder, floating utility windows, or other overlays above the target window.
- Post a short sequence: mouseMoved, leftMouseDown, stepped leftMouseDragged events, leftMouseUp.
- Add a temporary debug log at gesture start and drop resolution. Use it to prove which view and target received the event.

### Stop-loss rules

Stop automating and hand off to manual verification when any of these occur:

- The debug log shows a different target than the intended view.
- The app state changes in a way that contradicts the synthetic path.
- A permission dialog, overlay window, or display arrangement cannot be controlled.
- Two calibration rounds still produce inconsistent results.
- The test requires evaluating human feel, latency perception, or visual smoothness.

Do not keep tuning coordinates after these signals. Preserve the logs and report the limitation.

## XCTest Host Triage

When the host hangs or each test takes an unexpected fixed amount of time:

1. Run one test in isolation and compare its duration with the full suite.
2. Sample the host's main thread:

   ```bash
   sample <pid> 2 -file /tmp/<app>-main-thread.txt
   ```

3. Inspect for a synchronous AppKit I/O stack. A known fingerprint is:

   `NSWorkspace.iconForFile` → LaunchServices → `BindingBlueprint` → `__getattrlist`

   This can occur while an outline/table view creates sidebar rows for custom favorites. A typical symptom is roughly 26 seconds per controller or per test, not a crash.
4. Isolate the test process with a test home, for example `CFFIXED_USER_HOME=/tmp/<app>-test-home`.
5. Add a test-only switch to skip unrelated sidebar icon loading. Verify the switch actually reaches the test host. In Xcode schemes, `shouldUseLaunchSchemeArgsEnv="YES"` can mean the environment variables that matter are taken from `LaunchAction`, not only `TestAction`.
6. Prove the fix by timing a single test before and after the environment change. If the duration does not change, the variable probably did not reach the host.
7. Prefer targeted layout over forcing full-window layout when the test does not need it. Full layout can trigger sidebar row creation and expensive LaunchServices work.

Do not treat a test-only icon bypass as a production fix. Keep the production path unchanged, record the synchronous-load debt, and state that the test bypass is evidence isolation only.

## Manual Acceptance Handoff

Provide a compact checklist with preconditions, exact gesture, expected result, and reset path. Adapt this template:

1. In a single-pane window with tabs A/B/C, drag B to the right half. Expect A/C to remain on the left and only B on the right.
2. Drag a tab onto another single-pane window's content area. Expect a split with all existing target tabs preserved.
3. Release over the sidebar, traffic-light area, or "+" button. Expect the tab to return to its original position and no new window.
4. Drag the last tab out of a window. Expect the source window to close; reopening from the Dock must work.
5. Drag continuously for three seconds. Check hand-following, a complete tab capsule ghost, and no visible stalls. If a p95 frame-time target exists, measure it separately; otherwise mark performance unverified.
6. Record any rollback switch, such as a native-window-drag fallback, in the handoff.

Ask for one outcome per item. Do not mark the task complete while physical acceptance is outstanding.

## Evidence Report

Report each claim with one of these labels:

- **Verified**: Reproduced with evidence and a recorded command/result.
- **Unverified**: Not yet proven; name the missing measurement.
- **Blocked**: A permission, environment, or hardware condition prevents verification.

Include exact commands, test/assertion counts, log paths, test durations, artifact paths, and checksums when relevant. State separately what unit tests, self-tests, synthetic input, and manual checks each cover.

Never claim:

- 60 fps or smoothness from synthetic-event timing.
- XCTest success if the host hung, timed out, or only a subset ran.
- A production performance fix when only a test-only bypass was added.
- A physical drag works because a synthetic drag changed state once.

## Pitfalls

- Comparing CGWindow/CGEvent top-left coordinates with AppKit bottom-left coordinates.
- Using `NSEvent.mouseLocation` for a synthetic gesture path.
- Forgetting TCC prompts or overlay windows during a drag.
- Assuming a 26-second test is a code deadlock before sampling the main thread.
- Adding a test environment variable only to `TestAction` and assuming the host received it.
- Letting sidebar icon loading during full layout contaminate drag or integration tests.
- Treating a test-only skip flag as a fix for the production app.
- Marking a UI task complete while manual feel and performance remain unverified.
