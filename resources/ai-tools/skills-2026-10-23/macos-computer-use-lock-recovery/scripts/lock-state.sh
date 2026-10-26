#!/bin/bash
set -u

raw="$(ioreg -n Root -d1 -a 2>/dev/null | plutil -p - 2>/dev/null | grep -iE 'IOConsoleLocked|CGSSessionScreenIsLocked' || true)"

if printf '%s\n' "$raw" | grep -qiE '=>[[:space:]]*true'; then
  printf 'LOCKED\n'
  [ -n "$raw" ] && printf '%s\n' "$raw"
  exit 3
fi

if printf '%s\n' "$raw" | grep -qiE '=>[[:space:]]*false'; then
  printf 'UNLOCKED\n'
  [ -n "$raw" ] && printf '%s\n' "$raw"
  exit 0
fi

printf 'UNKNOWN\n'
printf 'No lock keys found; do not assume the screen is unlocked.\n' >&2
exit 4
