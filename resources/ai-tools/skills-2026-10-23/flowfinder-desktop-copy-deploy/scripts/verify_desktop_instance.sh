#!/bin/bash
# Verify the Desktop copy is actually the running instance, with PID attribution.
# Usage: verify_desktop_instance.sh [needle]   (needle = expected version label, e.g. 0.8.0-26102235)
set -euo pipefail

DEST="$HOME/Desktop/FlowFinder.app"
NEEDLE="${1:-}"
EXEC="$DEST/Contents/MacOS/FlowFinder"

fail() { echo "FAILED: $1"; exit 1; }
[ -d "$DEST" ] || fail "桌面副本不存在：$DEST"

BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$DEST/Contents/Info.plist" 2>/dev/null || echo unknown)
SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Contents/Info.plist" 2>/dev/null || echo unknown)
echo "EVIDENCE bundle=$SHORT-$BUILD"

codesign --verify --deep --strict "$DEST" 2>/dev/null \
  && echo "EVIDENCE codesign --verify --deep：通过" \
  || fail "codesign --verify --deep 未通过"

# Resolve PIDs by exact executable path, never by process name.
PIDS=$(pgrep -f "^$EXEC$" || true)
if [ -z "$PIDS" ]; then
  echo "ACTION required：桌面副本未运行。执行 open '$DEST' 后重跑本脚本。"
  exit 2
fi
COUNT=$(echo "$PIDS" | wc -w | tr -d ' ')
[ "$COUNT" -eq 1 ] || echo "WARN 有 $COUNT 个实例共用该可执行路径：$PIDS"
PID=$(echo "$PIDS" | awk '{print $1}')
echo "EVIDENCE pid=$PID path=$EXEC"

# Window geometry via AXUIElementCreateApplication(pid).
# System Events 'whose unix id is N' is known to return a different PID on this machine — do not use it for attribution.
GEOM=$(xcrun -f swift >/dev/null 2>&1 && xcrun swift - "$PID" "$NEEDLE" <<'SW' 2>/dev/null || true
import ApplicationServices
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let needle = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
  var v: CFTypeRef?
  return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func point(_ v: CFTypeRef?) -> String? {
  guard let v, let d = AXValueGetType(v as! AXValue) as AXValueType? else { return nil }
  var p = CGPoint.zero, s = CGSize.zero
  if d == .cgPoint { AXValueGetValue(v as! AXValue, .cgPoint, &p); return "\(Int(p.x)),\(Int(p.y))" }
  if d == .cgSize { AXValueGetValue(v as! AXValue, .cgSize, &s); return "\(Int(s.width))x\(Int(s.height))" }
  return nil
}
var texts: [String] = []
func walk(_ e: AXUIElement, _ depth: Int) {
  if depth > 40 { return }
  if let r = attr(e, kAXRoleAttribute) as? String, r == "AXStaticText",
     let v = attr(e, kAXValueAttribute) as? String { texts.append(v) }
  if let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] { kids.forEach { walk($0, depth + 1) } }
}
guard let wins = attr(app, kAXWindowsAttribute) as? [AXUIElement], !wins.isEmpty else {
  print("AX unavailable (no windows / no accessibility permission) — 回退到 screencapture 肉眼核对"); exit(0)
}
print("WINDOWS count=\(wins.count)")
for w in wins {
  let t = (attr(w, kAXTitleAttribute) as? String) ?? ""
  print("WINDOW title=\"\(t)\" pos=\(point(attr(w, kAXPositionAttribute)) ?? "?") size=\(point(attr(w, kAXSizeAttribute)) ?? "?")")
  walk(w, 0)
}
let hits = texts.filter { !needle.isEmpty && $0.contains(needle) }
if needle.isEmpty { print("LABELS \(texts.prefix(8).joined(separator: " | "))") }
else if hits.isEmpty { print("VERSION LABEL not in AX static texts (seen \(texts.count)) — 回退：按主窗口几何 screencapture 侧栏区域肉眼核对") }
else { print("VERSION LABEL found: \(hits[0])") }
SW
)
if [ -z "$GEOM" ]; then
  echo "WARN AX 读取失败（无辅助功能权限或 swift 不可用）。改用截图：按窗口几何区域 screencapture 后肉眼读侧栏版本标签。"
  exit 2
fi
echo "$GEOM"
if echo "$GEOM" | grep -q "回退\|unavailable"; then
  echo "ACTION required：证据不完整，须按上面的回退提示补截图后再写文档。"
  exit 2
fi
echo "NEXT 把以上实测值（PID、窗口几何、版本标签）写进文档，不得沿用上一轮数字。"
