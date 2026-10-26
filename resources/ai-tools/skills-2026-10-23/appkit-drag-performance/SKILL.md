---
name: appkit-drag-performance
description: "Diagnose and repair macOS AppKit drag stutter for tab reorder, pane/tab detach, cross-window drops, and window dragging. Use when drags feel laggy, drop overlays lag or flicker, or a sample shows per-event Auto Layout, NSTableView column rebuilds, full-window hitTest, or manual setFrameOrigin. 适用于 macOS AppKit/Swift 拖动卡顿、标签或窗口拖动掉帧、跨窗口落点迟滞。"
---

# AppKit Drag Performance

## Overview

Use this skill to repair jerky drag interactions in macOS AppKit apps. The target pattern is: replace per-event layout, hit-testing, and window-server churn with frame-based visuals, cached drop geometry, a pure drop resolver, and coalesced display-frame updates. Prove the result with real drag measurements, not only unit tests.

## Non-negotiables

- Measure before changing. Do not optimize a drag without a main-thread sample of both an idle baseline and the actual drag.
- Never claim 60fps from structural tests. Structure tests prove a known cascade is absent; only a real drag plus Instruments or signposts prove frame pacing.
- Preserve mouse ownership. Do not consume `mouseDown` for custom press or drag gestures unless `mouseUp` recovery is guaranteed. A lost `mouseUp` can make the whole OS behave as if the mouse is still down.
- Lock drop semantics with tests before rewriting the event path.
- Keep app-specific dimensions (tab buffer, title-band height, minimum pane width) as local constants; do not bake them into the workflow.

## When to use

- Tab, pane, window, or cross-window dragging is visibly choppy.
- Drop highlights, insertion lines, ghosts, or snap indicators lag behind the pointer.
- A main-thread `sample` shows `layout`, table column rebuilds, `hitTest`, `setFrameOrigin`, repeated `orderFront`, or synchronous I/O during drag.
- A drag refactor needs a repeatable performance and behavior acceptance process.

Do not use for non-AppKit frameworks, unrelated animation polish, or file-operation performance unless dragging is the measured bottleneck.

## 1. Build a drag test matrix

Record the exact conditions before profiling:

- window size, sidebar width, single-pane or double-pane, number of tabs and files;
- monitor refresh rate and whether the window uses transparency, blur, or rounded masks;
- target type: tab strip, pane content, invalid chrome, another window, outside all windows;
- scenarios: idle, reorder within strip, drag out and back, cross-window drop, invalid drop, last-tab drag, window drag.

Let launch work, directory loading, thumbnails, caches, and indexing settle before collecting a drag sample. Use real manual drags for the final verdict; synthetic mouse events are useful for setup but unreliable for feel.

## 2. Capture evidence before touching code

Run a time-based sample during a continuous drag and an equal idle baseline:

```bash
sample <pid> 3 -file /tmp/drag-before.txt
sample <pid> 3 -file /tmp/idle-before.txt
```

Inspect only the main-thread call graph. Time-based `sample` includes idle worker threads, so raw top-of-stack counts are misleading.

Look for these per-event costs:

- Auto Layout constraint changes that invalidate a whole window;
- a table's `layout()` doing width fitting, adding or removing `NSTableColumn`, or reloading rows;
- full-window `hitTest` and ancestor walks for every pointer update;
- moving an `NSPanel` or overlay with `orderFront` and `needsDisplay` on every event;
- manual `setFrameOrigin` on a transparent or blurred window on every event;
- synchronous disk, xattr, Spotlight, FFI, or `UserDefaults` writes;
- debug logging in the hot path.

Keep raw before/after samples. A real-world signal worth recognizing: 61 of 82 active main-thread samples in a 3-second tab drag were inside a table's `layout → column-fit → column-rebuild` chain. That is a cascade, not a rendering-cost problem.

Add `os_signpost` intervals around the per-frame drag work and decision changes. Use those intervals in Instruments to measure frame pacing; `sample` shows CPU cost, not display latency.

## 3. Break layout and data cascades

### Frame-based moving views

The insertion indicator, drop outline, and ghost are transient and must not participate in constraint solving. Create them once, use `translatesAutoresizingMaskIntoConstraints = true`, keep no constraints, and update `frame` or `layer.position` directly.

```swift
let indicator = NSView(frame: .zero)
indicator.wantsLayer = true
indicator.layer?.backgroundColor = accent.cgColor
indicator.translatesAutoresizingMaskIntoConstraints = true
addSubview(indicator)

func placeIndicator(x: CGFloat) {
    indicator.frame = CGRect(x: x, y: 3, width: 2, height: bounds.height - 6)
}
```

Do not activate a new `centerX` constraint per drag event. Do not call `layoutSubtreeIfNeeded()` in the hot path.

### Guard column fitting

A layout pass is not evidence that columns need refitting. Gate the work on an actual width change, and coalesce it:

```swift
enum FFColumnFitPolicy {
    static func shouldFit(previousWidth: CGFloat,
                          currentWidth: CGFloat,
                          epsilon: CGFloat = 1) -> Bool {
        abs(currentWidth - previousWidth) > epsilon
    }
}

override func layout() {
    super.layout()
    guard bounds.width > 0,
          FFColumnFitPolicy.shouldFit(previousWidth: lastFitWidth,
                                      currentWidth: bounds.width) else { return }
    lastFitWidth = bounds.width
    scheduleColumnFitOnce()
}
```

An async reentrancy flag that is reset before the real fit runs does not break the loop. The reliable guard is "width actually changed."

Only rebuild `NSTableColumn` objects when the visible-column set changes. Adding a column can create row views, thumbnails, icons, and accessibility work for every visible row. Do not reload list and grid data when only selection changed; use an explicit reload policy.

### Stop unrelated observers

Check `NSWindow.didMove`/`didResize`, split-view resize callbacks, Combine sinks, KVO, and notification observers for work that runs during drag. Do not write persistence on every frame. Do not recalculate disk statistics, metadata, or layout metrics from a mouse event.

## 4. Cache geometry and use a pure drop resolver

At drag start, snapshot everything needed to resolve a target:

- window identity and frame;
- pane content rectangles and tab-strip rectangles;
- invalid chrome rectangles (sidebar, traffic-light area, controls);
- tab midpoints for insertion index;
- all rectangles in one coordinate space, normally screen space.

Resolve the drop from the snapshot and the latest pointer:

```swift
enum FFDropDecision: Equatable {
    case reorder(windowID: ObjectIdentifier, side: PaneSide, index: Int)
    case merge(windowID: ObjectIdentifier, side: PaneSide, index: Int?)
    case split(windowID: ObjectIdentifier, side: PaneSide)
    case newWindow
    case returnToSource
}
```

Keep the resolver pure and table-testable. Do not walk the view hierarchy with `hitTest` on every pointer event. Re-snapshot at drag start and whenever the set of target windows changes.

Convert coordinates at boundaries and test the conversions. AppKit screen coordinates, window coordinates, and `NSSplitView`'s flipped coordinate system are a common source of "always outside" or "wrong half" bugs.

## 5. Coalesce pointer updates to display frames

Mouse events can arrive faster than the display can present. Store only the latest pointer and run at most one drag update per display frame:

```swift
final class FFDragFrameScheduler {
    private var timer: Timer?
    private var latest: CGPoint = .zero
    private let onFrame: (CGPoint) -> Void

    func update(_ point: CGPoint) { latest = point }

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onFrame(self.latest)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
```

Per frame: move the overlay, resolve once, and update the visual only when the decision changes. Create the overlay once; do not call `orderFrontRegardless` or `needsDisplay` on every event. Disable implicit animations for frame-only updates.

On ProMotion displays, prefer display-refresh synchronization; 60Hz is a floor, not a universal target. Measure whether the scheduler adds perceptible latency.

## 6. Prefer native window dragging, with a tested fallback

If the app can use a native drag region, call `window.performDrag(with: event)` and let the system coalesce window movement. This is usually smoother than moving a transparent, blurred window with `setFrameOrigin` on every mouse event.

If native dragging conflicts with a custom monitor or requires custom hit regions:

- preserve the native path when possible;
- implement a frame-coalesced fallback that computes absolute positions from the drag start, not incremental deltas;
- expose the fallback behind a debug flag while testing;
- test both paths on a real drag; do not ship an untested fallback as the default.

## 7. Route events without breaking clicks

- Use one app-level local monitor and route by `event.window`, or install and remove exactly one monitor per window.
- Do not rely on a global monitor that requires Accessibility permission as the normal path.
- Do not consume `mouseDown` for tab, window, or press gestures. Let AppKit retain mouse ownership so `mouseUp` returns; manage internal drag state separately.
- Preserve click behavior on controls inside drag regions. Press feedback must not swallow the event.
- Reset drag state on app deactivation and synthesize a safe mouse-up recovery if the interaction can be interrupted.
- Remove monitors and observers when a window closes.

## 8. Lock behavior with tests

Add tests before or with the refactor:

- Pure resolver matrix: same/cross window, single/double pane, tab strip/pane content/invalid chrome, insertion at each half, outside all windows.
- Source preservation: splitting a single pane keeps all sibling tabs; dragging one tab never wipes the remaining tabs.
- Target preservation: dropping onto another single-pane window keeps every existing target tab.
- Invalid drop: returns to source and creates no window.
- Last tab: dragging it out closes or collapses the source, and Dock reopen creates a window when none is visible.
- Structure: insertion indicator is frame-based and constraint-free; column fit is width-gated; scheduler keeps only the latest pointer; selection-only changes do not reload.
- Coordinates: flipped split views, screen-to-window conversion, and pointer-half decisions.

Run the full suite, not just the new tests. Test counts are evidence of coverage, not evidence of frame rate.

## 9. Verify with real drags

1. Build the app and run the complete test suite and any app self-test.
2. Use a clean build and a settled app.
3. Perform separate real drags of at least 3 seconds: tab reorder, drag out and back, cross-window drop, window drag.
4. Record with Instruments Time Profiler and the drag signposts. Collect frame intervals and main-thread stalls.
5. Acceptance target: p95 frame interval at or below 16.7ms (60fps), no visible hitch, and the previously dominant stack is gone or sharply reduced. On a 120Hz display, use the display's frame interval.
6. Re-run the behavior matrix: source/target tabs, invalid target, last tab, split side, cross-window insertion, clicks inside drag regions.
7. Compare before/after samples and keep them as evidence.

If a real drag or frame-interval measurement is not possible, report: "structure improved; real drag and 60fps unverified." Do not turn a passing structural test into a performance claim.

## Red flags

- Concluding from `sample` top-of-stack counts that include idle worker threads.
- "Fixing" lag only by lowering the event rate while layout still runs per event.
- Rebuilding table columns or rows inside `layout()`.
- Changing an Auto Layout constraint on every mouse move.
- Full-hierarchy `hitTest` for every pointer update.
- `orderFront` or snapshot work per event.
- Forgetting source/target tab preservation when adding split and merge semantics.
- Assuming a synthetic drag proves feel.
- Shipping a native-drag fallback that was never exercised.

## Completion report

State separately:

- measured before/after hot paths and samples;
- structural changes made;
- tests and builds that passed;
- behavior scenarios manually verified;
- real frame pacing result, or explicitly "unverified";
- remaining risks or fallback paths.
