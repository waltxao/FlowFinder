#!/usr/bin/env bash
set -euo pipefail

PIDFILE="/tmp/cua-caffeinate.pid"
LOGFILE="/tmp/cua-caffeinate.log"

usage() {
  cat <<'EOF'
Usage:
  cua-preflight.sh                     Read lock state only
  cua-preflight.sh --caffeinate [SEC]  Start bounded caffeinate and read lock state
  cua-preflight.sh --stop-caffeinate   Stop the caffeinate process recorded in the PID file
EOF
}

lock_state() {
  local out
  out="$(ioreg -n Root -d1 -a 2>/dev/null | plutil -p - 2>/dev/null \
    | grep -i -E 'IOConsoleLocked|CGSSessionScreenIsLocked' || true)"
  printf '%s\n' "$out"
  if printf '%s' "$out" | grep -qi '=> true'; then
    echo "LOCKED=yes"
  else
    echo "LOCKED=no"
  fi
}

caffeinate_start() {
  local seconds="${1:-7200}"
  case "$seconds" in
    ''|*[!0-9]*) echo "ERROR: SEC must be a positive integer" >&2; exit 2 ;;
  esac
  if [ "$seconds" -le 0 ]; then
    echo "ERROR: SEC must be greater than 0" >&2
    exit 2
  fi

  if [ -f "$PIDFILE" ]; then
    local existing
    existing="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$existing" ] && kill -0 "$existing" 2>/dev/null; then
      local cmd
      cmd="$(ps -p "$existing" -o command= 2>/dev/null || true)"
      case "$cmd" in
        caffeinate\ -dimsu*) echo "CAFFEINATE_PID=$existing (already running)"; return 0 ;;
        *) echo "STALE_PIDFILE=$existing (PID is not caffeinate)"; rm -f "$PIDFILE" ;;
      esac
    else
      rm -f "$PIDFILE"
    fi
  fi

  nohup caffeinate -dimsu -t "$seconds" >"$LOGFILE" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$PIDFILE"
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    echo "CAFFEINATE_PID=$pid"
    echo "CAFFEINATE_SECONDS=$seconds"
  else
    echo "ERROR: caffeinate exited; see $LOGFILE" >&2
    rm -f "$PIDFILE"
    exit 1
  fi
}

caffeinate_stop() {
  if [ ! -f "$PIDFILE" ]; then
    echo "NO_CAFFEINATE_PIDFILE"
    return 0
  fi
  local pid cmd
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    echo "STALE_PIDFILE=$pid"
    rm -f "$PIDFILE"
    return 0
  fi
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  case "$cmd" in
    caffeinate\ -dimsu*) kill "$pid"; echo "STOPPED=$pid"; rm -f "$PIDFILE" ;;
    *) echo "REFUSED: PID $pid is not caffeinate -dimsu"; echo "STALE_PIDFILE=$pid" ;;
  esac
}

case "${1:-check}" in
  check) lock_state ;;
  --caffeinate) caffeinate_start "${2:-7200}"; lock_state ;;
  --stop-caffeinate) caffeinate_stop ;;
  -h|--help) usage ;;
  *) echo "ERROR: unknown option $1" >&2; usage >&2; exit 2 ;;
esac
