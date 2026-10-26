#!/usr/bin/env swift
// ax-window.swift — PID-exact window geometry / activation / close via the AX API.
//
//   swift ax-window.swift list      PID
//   swift ax-window.swift get       PID "WINDOW TITLE"
//   swift ax-window.swift set-size  PID "WINDOW TITLE" WIDTH HEIGHT
//   swift ax-window.swift raise     PID "WINDOW TITLE"
//   swift ax-window.swift close     PID "WINDOW TITLE"
//
// Do not resolve the target with System Events `whose unix id is PID`: with two
// same-named instances (audit copy + the user's app) it has been observed returning the
// user's PID, which silently attributed a whole evidence batch to the wrong instance.
// set-size prints the re-read ACTUAL size; a requested size is not evidence.

import ApplicationServices
import Cocoa
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let pid = Int32(args[2]) else { usage() }
let mode = args[1]
let app = AXUIElementCreateApplication(pid)

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: swift ax-window.swift list PID
           swift ax-window.swift get|raise|close PID "WINDOW TITLE"
           swift ax-window.swift set-size PID "WINDOW TITLE" W H

    """.utf8))
    exit(2)
}

func attr(_ el: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
}
func kids(_ el: AXUIElement, _ a: String) -> [AXUIElement] { (attr(el, a) as? [AXUIElement]) ?? [] }
func str(_ el: AXUIElement, _ a: String) -> String { (attr(el, a) as? String) ?? "?" }

func geometry(_ w: AXUIElement) -> String {
    let posv = attr(w, kAXPositionAttribute)
    let sizev = attr(w, kAXSizeAttribute)
    var p = CGPoint.zero
    var s = CGSize.zero
    if let v = posv { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = sizev { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return "POS=\(Int(p.x)),\(Int(p.y)) SIZE=\(Int(s.width))x\(Int(s.height))"
}

let windows = kids(app, kAXWindowsAttribute)
if mode == "list" {
    print("PID=\(pid) WINDOWS=\(windows.count)")
    for (i, w) in windows.enumerated() {
        print("  [\(i)] '\(str(w, kAXTitleAttribute))' subrole=\(str(w, kAXSubroleAttribute)) \(geometry(w))")
    }
    exit(0)
}

guard args.count >= 4 else { usage() }
let want = args[3]
guard let w = windows.first(where: { str($0, kAXTitleAttribute) == want }) else {
    print("WIN_NOT_FOUND '\(want)'; have: " + windows.map { str($0, kAXTitleAttribute) }.joined(separator: " | "))
    exit(4)
}

switch mode {
case "get":
    print("ACTUAL \(geometry(w))")
case "set-size":
    guard args.count >= 6, let width = Double(args[4]), let height = Double(args[5]) else { usage() }
    var sz = CGSize(width: width, height: height)
    guard let sizeVal = AXValueCreate(.cgSize, &sz) else { print("VALUE_CREATE_FAILED"); exit(5) }
    let err = AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sizeVal)
    usleep(400_000)
    print("SET_SIZE err=\(err.rawValue)")
    print("ACTUAL \(geometry(w))")
case "raise":
    let main = AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    let raise = AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    usleep(250_000)
    print("RAISE main=\(main.rawValue) raise=\(raise.rawValue) \(geometry(w))")
case "close":
    guard let button = kids(w, kAXChildrenAttribute).first(where: { str($0, kAXSubroleAttribute) == "AXCloseButton" }) else {
        print("NO_CLOSE_BUTTON")
        exit(6)
    }
    print("CLOSE err=\(AXUIElementPerformAction(button, kAXPressAction as CFString).rawValue)")
default:
    usage()
}
