#!/bin/bash
# open-menu.sh — open a macOS menu bar title with REAL mouse events.
#
#   open-menu.sh MENU_X [MENU_Y] [ITEM_X ITEM_Y]   # press-drag-release
#   open-menu.sh --click MENU_X [MENU_Y]           # single click on the title
#
# Why not AXPress: on AppKit apps AXPress on a menu-bar item returns success while
# `AXMenu.children` stays empty, so no item can be read or triggered (see ax-menu.swift
# AX_PRESS_OK_CHILDREN_EMPTY). A real down-move-release gesture tracks the menu open.
# MENU_Y is 11 on a standard menu bar; read MENU_X from the menu-bar item's AXPosition,
# never from a stale screenshot. `cliclick` posts CGEvents, which go to the frontmost app:
# run front-assert.sh for the audit PID immediately before this script.

set -u
CLICLICK=$(command -v cliclick || echo /opt/homebrew/bin/cliclick)
[ -x "$CLICLICK" ] || { echo "cliclick not found (brew install cliclick); cannot drive menus" >&2; exit 3; }

MODE=drag
if [ "${1:-}" = "--click" ]; then MODE=click; shift; fi
[ $# -ge 1 ] || { echo "usage: open-menu.sh MENU_X [MENU_Y] [ITEM_X ITEM_Y] | open-menu.sh --click MENU_X [MENU_Y]" >&2; exit 2; }

MX=$(printf '%.0f' "$1" 2>/dev/null) || { echo "MENU_X must be a number" >&2; exit 2; }
MY=${2:-11}
MY=$(printf '%.0f' "$MY" 2>/dev/null) || { echo "MENU_Y must be a number" >&2; exit 2; }

if [ "$MODE" = "click" ]; then
  "$CLICLICK" "c:$MX,$MY" >/dev/null 2>&1
  sleep 0.5
  echo "CLICKED menu-bar title at $MX,$MY — verify the open menu in a fresh screenshot"
  exit 0
fi

if [ $# -ge 3 ] && [ $# -lt 4 ]; then
  echo "ITEM_X needs ITEM_Y too: open-menu.sh MENU_X [MENU_Y] ITEM_X ITEM_Y" >&2
  exit 2
fi
[ $# -le 4 ] || { echo "too many arguments" >&2; exit 2; }

"$CLICLICK" "m:$MX,$MY" >/dev/null 2>&1
sleep 0.3
"$CLICLICK" "dd:$MX,$MY" >/dev/null 2>&1
sleep 0.4

if [ $# -ge 4 ]; then
  IX=$(printf '%.0f' "$3" 2>/dev/null) || { echo "ITEM_X must be a number" >&2; exit 2; }
  IY=$(printf '%.0f' "$4" 2>/dev/null) || { echo "ITEM_Y must be a number" >&2; exit 2; }
  # drag in steps so AppKit tracks the highlight, then release on the item
  "$CLICLICK" "m:$((MX + 12)),$((MY + 16))" >/dev/null 2>&1
  sleep 0.2
  "$CLICLICK" "m:$IX,$IY" >/dev/null 2>&1
  sleep 0.3
  "$CLICLICK" "du:$IX,$IY" >/dev/null 2>&1
  sleep 0.5
  echo "DRAGGED $MX,$MY -> $IX,$IY — verify the expected sheet/panel/state actually appeared"
else
  # release on the title itself so the menu stays open instead of triggering an item
  "$CLICLICK" "du:$MX,$MY" >/dev/null 2>&1
  sleep 0.5
  echo "OPENED menu at $MX,$MY and left it open — screenshot now, then press Escape before the next surface"
fi
