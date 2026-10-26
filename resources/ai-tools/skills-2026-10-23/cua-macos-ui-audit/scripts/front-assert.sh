#!/bin/bash
# front-assert.sh — capture a region AND prove which process owns the pixels.
#
#   front-assert.sh WANT_PID X Y W H OUT.png
#   front-assert.sh WANT_PID --point X Y            # ownership only, no capture
#
# A screenshot is only evidence for the surface you think it shows. `screencapture -l`
# can return a different window when two windows share the same geometry, so capture
# the region and then assert the topmost non-desktop window under its centre belongs
# to WANT_PID. Run this assertion before every synthetic click or keystroke too:
# CGEvents are posted to whatever is frontmost, not to a PID.
#
# Exit 0 = OWNERSHIP=OK, 1 = mismatch/no window, 2 = bad args.

set -u
WANT=${1:-}
[ -n "$WANT" ] || { echo "usage: front-assert.sh WANT_PID X Y W H OUT.png | WANT_PID --point X Y" >&2; exit 2; }
case "$WANT" in (*[!0-9]*) echo "WANT_PID must be a number, got: $WANT" >&2; exit 2 ;; esac

if [ "${2:-}" = "--point" ]; then
  [ $# -ge 4 ] || { echo "usage: front-assert.sh WANT_PID --point X Y" >&2; exit 2; }
  X=$(printf '%.0f' "$3" 2>/dev/null) || exit 2
  Y=$(printf '%.0f' "$4" 2>/dev/null) || exit 2
  OUT=""
  W=1; H=1
else
  [ $# -ge 6 ] || { echo "usage: front-assert.sh WANT_PID X Y W H OUT.png" >&2; exit 2; }
  X=$(printf '%.0f' "$2" 2>/dev/null) || exit 2
  Y=$(printf '%.0f' "$3" 2>/dev/null) || exit 2
  W=$(printf '%.0f' "$4" 2>/dev/null) || exit 2
  H=$(printf '%.0f' "$5" 2>/dev/null) || exit 2
  OUT=$6
  [ "$W" -gt 0 ] && [ "$H" -gt 0 ] || { echo "W/H must be positive" >&2; exit 2; }
fi

[ -n "$OUT" ] && screencapture -x -o -R"$X,$Y,$W,$H" "$OUT" 2>/dev/null

TOP=$(swift - "$X" "$Y" "$W" "$H" <<'SWIFT' 2>/dev/null | tail -1
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let x = Double(a[1])!, y = Double(a[2])!, w = Double(a[3])!, h = Double(a[4])!
let skip: Set<String> = ["Dock", "程序坞", "Window Server", "WindowManager", "Wallpaper", "墙纸", "通知中心", "Spotlight", "Control Center", "控制中心"]
let cx = x + w / 2, cy = y + h / 2
guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
  print("none"); exit(0)
}
for win in list {
  let owner = (win[kCGWindowOwnerName as String] as? String) ?? "?"
  let layer = win[kCGWindowLayer as String] as? Int ?? -999
  if skip.contains(owner) || layer != 0 { continue }
  let b = win[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
  let bx = Double(b["X"] ?? 0), by = Double(b["Y"] ?? 0)
  let bw = Double(b["Width"] ?? 0), bh = Double(b["Height"] ?? 0)
  if cx >= bx && cx < bx + bw && cy >= by && cy < by + bh {
    let pid = win[kCGWindowOwnerPID as String] as? Int ?? -1
    let num = win[kCGWindowNumber as String] as? Int ?? -1
    print("\(pid) WIN=\(num) OWNER=\(owner)")
    exit(0)
  }
}
print("none")
SWIFT
)

TOP=${TOP:-none}
echo "TOP=$TOP (want $WANT)${OUT:+ -> $OUT}"
case "$TOP" in
  "$WANT "*) echo "OWNERSHIP=OK"; exit 0 ;;
  *) echo "OWNERSHIP=MISMATCH — do not record this capture as evidence for PID $WANT"; exit 1 ;;
esac
