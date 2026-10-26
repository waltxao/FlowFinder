# CUA Recovery Snippets

All snippets were exercised in a real macOS CUA session. Replace placeholders in angle brackets.

## Connect once per node_repl session

```js
var cua = await (await import('@ali/qoder-cu-sdk')).ComputerUse.createAppClient();
var app = await cua.getApp('<BUNDLE_ID>');
var ax = await app.getAXState({ disableDiffing: true, emit: false });
nodeRepl.write(ax.split('\n').filter(l => /Window:|button |text field /.test(l)).slice(0, 80).join('\n'));
```

## Close and reconnect

Use after `SESSION_BUSY` or `Computer Use connection is closed`. The client has `close()`; the app object does not.

```js
try { await cua.close(); } catch (e) { nodeRepl.write('close: ' + e.message); }
await new Promise(r => setTimeout(r, 1000));

var cua = await (await import('@ali/qoder-cu-sdk')).ComputerUse.createAppClient();
var app = await cua.getApp('<BUNDLE_ID>');
var ax = await app.getAXState({ disableDiffing: true, emit: false });
nodeRepl.write(ax.split('\n').filter(l => /Window:|button |text field /.test(l)).slice(0, 80).join('\n'));
```

When several stale clients exist, close each known variable in its own `try/catch`, wait, then create one new client. Do not create a client while another is busy.

## Screenshot to a file

```js
const fs = await import('node:fs');
const png = await app.getScreenshot({ emit: false });
fs.writeFileSync('/tmp/cua-evidence.png', png);
nodeRepl.write('/tmp/cua-evidence.png');
```

## Find an element from a fresh AX tree

Element IDs are valid only for the tree that produced them.

```js
var ax = await app.getAXState({ disableDiffing: true, emit: false });
var id = null;
for (const line of ax.split('\n')) {
  if (line.includes('button <LABEL>')) {
    id = Number(line.match(/^\s*(\d+)/)[1]);
    break;
  }
}
nodeRepl.write({ id });
if (id !== null) await app.click(id);
```

## Launch an isolated copy

`APP_SKIP_PERMISSION_GATE` stands for the app's own test flag. Do not invent one and do not treat it as a TCC bypass.

```bash
set -euo pipefail
SRC="/absolute/path/App.app"
DIR=$(mktemp -d /tmp/macos-ui-verify.XXXXXX)
APP="$DIR/AppAudit.app"
cp -R "$SRC" "$APP"

BID="com.example.audit.$(date +%s)"
plutil -replace CFBundleIdentifier -string "$BID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "AppAudit" "$APP/Contents/Info.plist" 2>/dev/null || true
plutil -replace CFBundleDisplayName -string "AppAudit" "$APP/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

open -n --env APP_SKIP_PERMISSION_GATE=1 "$APP"
sleep 3

REAL=$(cd "$APP" && pwd -P)
PID=""
for p in $(pgrep -f -- "$REAL/Contents/MacOS/"); do
  cmd=$(ps -p "$p" -o command= 2>/dev/null || true)
  case "$cmd" in
    "$REAL/Contents/MacOS/"*) PID=$p; break ;;
  esac
done
[ -n "$PID" ] || { echo "NO_PID_FOR=$REAL" >&2; exit 1; }

printf '%s\n' "$BID" > /tmp/cua-copy-bid
printf '%s\n' "$PID" > /tmp/cua-copy-pid
printf '%s\n' "$APP" > /tmp/cua-copy-app

echo "BID=$BID PID=$PID"
ps -p "$PID" -o pid=,command=
```

## Window geometry and region screenshot

```bash
PID=$(cat /tmp/cua-copy-pid)
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to get {frontmost, count of windows, name of every window}'
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to set {position of window 1, size of window 1} to {{0, 30}, {1440, 900}}'
osascript -e 'tell application "System Events" to tell (item 1 of (every application process whose unix id is '"$PID"')) to get {position of window 1, size of window 1}'
```

Use the returned `x, y, w, h` immediately:

```bash
screencapture -x -R "$X,$Y,$W,$H" /tmp/cua-evidence.png
```

## Lock check and bounded caffeinate

```bash
scripts/cua-preflight.sh
scripts/cua-preflight.sh --caffeinate 7200
scripts/cua-preflight.sh --stop-caffeinate
```

## Cleanup

```bash
APP=$(cat /tmp/cua-copy-app)
CID=$(cat /tmp/cua-copy-pid)
REAL=$(cd "$APP" && pwd -P)
cmd=$(ps -p "$CID" -o command= 2>/dev/null || true)
case "$cmd" in
  "$REAL/Contents/MacOS/"*) kill "$CID" ;;
  *) echo "REFUSED: $CID is not the copy executable" ;;
esac

case "$APP" in
  /tmp/macos-ui-verify.*|/private/tmp/macos-ui-verify.*) rm -rf "$(dirname "$APP")" ;;
  *) echo "REFUSED: $APP" ;;
esac

BID=$(cat /tmp/cua-copy-bid)
defaults delete "$BID" 2>/dev/null || true
scripts/cua-preflight.sh --stop-caffeinate
```
