#!/usr/bin/env bash
# Read-only CUA preflight plus bounded caffeinate lifecycle.
# Never launches, kills, or deletes an application.

set -uo pipefail

STATE_DIR="${CUA_PREFLIGHT_STATE_DIR:-/tmp/macos-cua-isolated-ui-audit}"
PIDFILE="$STATE_DIR/caffeinate.pid"
LOGFILE="$STATE_DIR/caffeinate.log"
DEFAULT_SECONDS=7200

usage() {
  cat <<'EOF'
Usage:
  cua-preflight.sh [--check]            Read lock state, caffeinate state, audit processes
  cua-preflight.sh --caffeinate [SEC]   Start bounded caffeinate, then report
  cua-preflight.sh --stop-caffeinate    Stop the caffeinate PID recorded by this script
  cua-preflight.sh --help               Show this help

Exit codes:
  0  unlocked, or the requested action succeeded
  1  operational error
  2  locked or unknown lock state (for --check)

Environment:
  CUA_PREFLIGHT_STATE_DIR   Override the PID/log directory (default: /tmp/macos-cua-isolated-ui-audit)
EOF
}

lock_report() {
  local out
  out="$(ioreg -n Root -d1 -a 2>/dev/null \
    | plutil -p - 2>/dev/null \
    | grep -i -E 'IOConsoleLocked|CGSSessionScreenIsLocked' || true)"

  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  else
    echo "LOCK_KEYS=absent"
  fi

  local locked="unknown"
  local any_true any_false
  any_true="$(printf '%s\n' "$out" | grep -Eqi '"(IOConsoleLocked|CGSSessionScreenIsLocked)"[[:space:]]*=>[[:space:]]*true' && echo 1 || echo 0)"
  any_false="$(printf '%s\n' "$out" | grep -Eqi '"(IOConsoleLocked|CGSSessionScreenIsLocked)"[[:space:]]*=>[[:space:]]*false' && echo 1 || echo 0)"

  if [ "$any_true" -eq 1 ]; then
    locked="yes"
  elif [ "$any_false" -eq 1 ]; then
    locked="no"
  fi
  echo "LOCKED=$locked"
}

caffeinate_pid() {
  [ -f "$PIDFILE" ] || return 0
  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  case "$pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  printf '%s\n' "$pid"
}

is_our_caffeinate() {
  local pid="$1" cmd
  cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  case "$cmd" in
    caffeinate\ -dimsu*|*/caffeinate\ -dimsu*) return 0 ;;
    *) return 1 ;;
  esac
}

caffeinate_report() {
  local pid
  pid="$(caffeinate_pid)"
  if [ -z "$pid" ]; then
    echo "CAFFEINATE=stopped"
    return 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "CAFFEINATE=stale_pidfile pid=$pid"
    return 0
  fi
  if is_our_caffeinate "$pid"; then
    echo "CAFFEINATE=running pid=$pid"
  else
    echo "CAFFEINATE=pid_mismatch pid=$pid"
  fi
}

process_report() {
  local matches
  matches="$(ps -axo pid=,command= 2>/dev/null \
    | grep -F "/Contents/MacOS/" \
    | grep -v grep \
    | grep -E '(/private)?/tmp/|macos-ui-verify|Audit\.app' \
    | head -20 || true)"
  if [ -n "$matches" ]; then
    echo "--- PROCESSES ---"
    printf '%s\n' "$matches"
  else
    echo "PROCESSES=none"
  fi
}

check() {
  local report locked
  report="$(lock_report)"
  printf '%s\n' "$report"
  caffeinate_report
  process_report

  locked="$(printf '%s\n' "$report" | awk -F= '/^LOCKED=/{print $2; exit}')"
  case "$locked" in
    no) return 0 ;;
    *) return 2 ;;
  esac
}

caffeinate_start() {
  local seconds="${1:-$DEFAULT_SECONDS}"
  case "$seconds" in
    ''|*[!0-9]*) echo "ERROR: SEC must be a positive integer" >&2; return 1 ;;
  esac
  if [ "$seconds" -lt 1 ] || [ "$seconds" -gt 86400 ]; then
    echo "ERROR: SEC must be between 1 and 86400" >&2
    return 1
  fi

  mkdir -p "$STATE_DIR" || return 1

  local existing
  existing="$(caffeinate_pid)"
  if [ -n "$existing" ] && kill -0 "$existing" 2>/dev/null; then
    if is_our_caffeinate "$existing"; then
      echo "CAFFEINATE_PID=$existing (already running)"
      lock_report
      caffeinate_report
      process_report
      return 0
    fi
    echo "STALE_PIDFILE=$existing (PID is not caffeinate); removing" >&2
    rm -f "$PIDFILE"
  else
    rm -f "$PIDFILE"
  fi

  nohup caffeinate -dimsu -t "$seconds" >"$LOGFILE" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$PIDFILE"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "ERROR: caffeinate exited; see $LOGFILE" >&2
    rm -f "$PIDFILE"
    return 1
  fi
  if ! is_our_caffeinate "$pid"; then
    echo "ERROR: started PID $pid is not caffeinate" >&2
    rm -f "$PIDFILE"
    return 1
  fi

  echo "CAFFEINATE_PID=$pid"
  echo "CAFFEINATE_SECONDS=$seconds"
  lock_report
  caffeinate_report
  process_report
}

caffeinate_stop() {
  local pid
  pid="$(caffeinate_pid)"
  if [ -z "$pid" ]; then
    echo "NO_CAFFEINATE_PIDFILE"
    return 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "STALE_PIDFILE=$pid"
    rm -f "$PIDFILE"
    return 0
  fi
  if ! is_our_caffeinate "$pid"; then
    echo "REFUSED: PID $pid is not caffeinate -dimsu" >&2
    return 1
  fi

  kill "$pid" 2>/dev/null || true
  local i
  for i in 1 2 3 4 5; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "ERROR: caffeinate PID $pid did not exit" >&2
    return 1
  fi
  rm -f "$PIDFILE"
  echo "STOPPED=$pid"
}

case "${1:-check}" in
  check|--check)
    check
    ;;
  --caffeinate)
    caffeinate_start "${2:-$DEFAULT_SECONDS}"
    ;;
  --stop-caffeinate)
    caffeinate_stop
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "ERROR: unknown option $1" >&2
    usage >&2
    exit 1
    ;;
esac
