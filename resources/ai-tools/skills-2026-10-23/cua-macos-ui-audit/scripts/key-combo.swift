#!/usr/bin/env swift
// key-combo.swift — post a keyboard shortcut through CGEvent with modifier flags.
//
//   swift key-combo.swift KEY [FLAGS]        # FLAGS = comma list: cmd,alt,shift,ctrl
//   swift key-combo.swift a cmd,shift
//   swift key-combo.swift 4 cmd              # raw virtual key code also accepted
//   swift key-combo.swift --list             # print the named key table
//   swift key-combo.swift KEY FLAGS --dry-run  # resolve and create the event, post nothing
//
// Why a custom tool: `cliclick` has no `ke:` verb and its kd:/ku: modifier bookkeeping is
// easy to get wrong (a stuck modifier changes every later click). osascript `keystroke ...
// using {command down}` works but is NOT PID-scoped, and CGEvents are not PID-scoped either:
// both hit the frontmost app. Assert ownership with front-assert.sh first, otherwise a
// shortcut can create files in the user's real Desktop and you will attribute it to the audit.

import Cocoa
import Foundation

let names: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
    "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "cmd": 55, "shift": 56,
    "capslock": 57, "option": 58, "control": 59, "rightshift": 60, "rightoption": 61,
    "rightcontrol": 62, "fn": 63, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
    "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    "left": 123, "right": 124, "down": 125, "up": 126,
]

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--list" {
    print("NAMED KEYS: " + names.keys.sorted().joined(separator: " "))
    exit(0)
}
let dryRun = args.contains("--dry-run")
let positional = args.filter { $0 != "--dry-run" }
guard positional.count >= 1 else {
    FileHandle.standardError.write(Data("usage: swift key-combo.swift KEY [cmd,alt,shift,ctrl] [--dry-run]\n".utf8))
    exit(2)
}

var flags: CGEventFlags = []
let flagList = positional.count >= 2 ? positional[1].split(separator: ",") : []
for part in flagList {
    switch part {
    case "cmd": flags.insert(.maskCommand)
    case "alt", "option": flags.insert(.maskAlternate)
    case "shift": flags.insert(.maskShift)
    case "ctrl", "control": flags.insert(.maskControl)
    default:
        print("UNKNOWN_FLAG \(part) — supported: cmd, alt, shift, ctrl")
        exit(2)
    }
}

let key = positional[0]
guard let code = names[key] ?? UInt16(key) else {
    print("UNKNOWN_KEY '\(key)' — pass a virtual key code or run --list")
    exit(2)
}

let src = CGEventSource(stateID: .hidSystemState)
guard let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) else {
    print("EVENT_CREATE_FAILED"); exit(3)
}
down.flags = flags
if dryRun {
    print("DRY_RUN key=\(key) code=\(code) flags=\(flags.rawValue) — nothing posted")
    exit(0)
}
down.post(tap: .cghidEventTap)
usleep(60_000)
if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
    up.flags = flags
    up.post(tap: .cghidEventTap)
}
print("POSTED key=\(key) code=\(code) flags=\(flags.rawValue) — verify the resulting UI; a posted event has no PID target")
