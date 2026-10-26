#!/usr/bin/env swift
// ax-menu.swift — PID-exact menu-bar enumeration and item execution.
//
//   swift ax-menu.swift menus  PID
//   swift ax-menu.swift items  PID "MENU" [ITEM]
//   swift ax-menu.swift press  PID "MENU" "ITEM" [SUBITEM]
//
// `items`/`press` AXPress the menu-bar item first. On many AppKit apps the press
// returns success while `AXMenu.children` stays empty — that is an automation
// limitation, not a disabled menu. The script says so explicitly; fall back to a
// real press-drag-release (scripts/open-menu.sh) and prove the resulting UI.

import ApplicationServices
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let pid = Int32(args[2]) else { usage() }
let mode = args[1]
let app = AXUIElementCreateApplication(pid)

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: swift ax-menu.swift menus PID
           swift ax-menu.swift items PID "MENU" [ITEM]
           swift ax-menu.swift press PID "MENU" "ITEM" [SUBITEM]

    """.utf8))
    exit(2)
}

func attr(_ el: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
}
func kids(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func title(_ el: AXUIElement) -> String { (attr(el, kAXTitleAttribute) as? String) ?? "" }
func press(_ el: AXUIElement) -> Bool { AXUIElementPerformAction(el, kAXPressAction as CFString) == .success }

// AppKit labels use "…" while menus may report "..." and vice versa.
func matches(_ label: String, _ want: String) -> Bool {
    let a = label.replacingOccurrences(of: "...", with: "…")
    let b = want.replacingOccurrences(of: "...", with: "…")
    return a == b || a.hasPrefix(b)
}
func find(_ menu: AXUIElement, _ want: String) -> AXUIElement? {
    kids(menu).first { matches(title($0), want) }
}
func describe(_ el: AXUIElement) -> String {
    let enabled = (attr(el, "AXEnabled") as? Bool).map(String.init) ?? "?"
    let cmd = (attr(el, "AXMenuItemCmdChar") as? String).map { " key=\($0)" } ?? ""
    let subs = kids(el).count
    return "'\(title(el))' enabled=\(enabled)\(cmd) submenus=\(subs)"
}

guard let mbRef = attr(app, "AXMenuBar") else {
    print("NO_MENUBAR pid=\(pid) — the audit copy is not registered with AX; check focus/launch state")
    exit(3)
}
let mb = mbRef as! AXUIElement
let barItems = kids(mb)
let names = barItems.map(title)
print("MENUS=" + names.joined(separator: " | "))

if mode == "menus" { exit(0) }

guard args.count >= 4 else { usage() }
guard let target = barItems.first(where: { matches(title($0), args[3]) }) else {
    print("MENU_NOT_FOUND '\(args[3])'; have: " + names.joined(separator: " | "))
    exit(4)
}
if !press(target) {
    print("MENU_PRESS_FAILED '\(args[3])' — use open-menu.sh")
    exit(5)
}
usleep(400_000)
guard let menu = kids(target).first else {
    print("AX_PRESS_OK_CHILDREN_EMPTY '\(title(target))' — AX cannot read this menu; use open-menu.sh + screenshot")
    exit(6)
}
let items = kids(menu)
if items.isEmpty {
    print("AX_PRESS_OK_MENU_EMPTY '\(title(target))' — not proof the menu is disabled; use open-menu.sh")
    exit(6)
}
func closeMenu() { _ = AXUIElementPerformAction(menu, "AXCancel" as CFString) }

print("OPENED '\(title(target))' ITEMS=\(items.count)")
for it in items { print("  " + describe(it)) }
if args.count < 5 {
    closeMenu()
    print("CLOSED")
    exit(0)
}

let wantItem = args[4]
guard let item = find(menu, wantItem) else {
    closeMenu()
    print("ITEM_NOT_FOUND '\(wantItem)'; have: " + items.map(title).joined(separator: " | "))
    exit(7)
}
print("TARGET " + describe(item))
if mode == "items" { closeMenu(); print("CLOSED"); exit(0) }

if args.count >= 6 {
    guard let sub = kids(item).first else { closeMenu(); print("NO_SUBMENU '\(title(item))' — synthetic hover may not expand it; record Blocked") ; exit(8) }
    guard let subItem = find(sub, args[5]) else {
        closeMenu()
        print("SUB_NOT_FOUND '\(args[5])'; have: " + kids(sub).map(title).joined(separator: " | "))
        exit(9)
    }
    print("PRESS_SUB err=\(press(subItem) ? "OK" : "FAILED")")
    exit(0)
}
print("PRESS err=\(press(item) ? "OK" : "FAILED") — a success return is not proof; verify the expected sheet/panel appeared")
