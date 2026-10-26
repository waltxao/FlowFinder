#!/usr/bin/env swift
import Foundation
import CoreGraphics
import AppKit

func usage() -> Never {
    print("""
    usage:
      window_capture.swift list [owner-filter] [--all] [--all-layers]
      window_capture.swift capture <window-id> <output.png>
      window_capture.swift screen <output.png>
    """)
    exit(2)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func number(_ value: Any?) -> Double {
    if let number = value as? NSNumber { return number.doubleValue }
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    return 0
}

func windowList(all: Bool) -> [[String: Any]] {
    let options: CGWindowListOption = all
        ? CGWindowListOption(arrayLiteral: .optionAll, .excludeDesktopElements)
        : CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        fail("CGWindowListCopyWindowInfo returned no windows")
    }
    return list
}

func bounds(of window: [String: Any]) -> (x: Double, y: Double, width: Double, height: Double) {
    guard let rect = window[kCGWindowBounds as String] as? [String: Any] else {
        return (0, 0, 0, 0)
    }
    return (number(rect["X"]), number(rect["Y"]), number(rect["Width"]), number(rect["Height"]))
}

func runCapture(_ arguments: [String], output: String) -> NSBitmapImageRep {
    try? FileManager.default.removeItem(atPath: output)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = arguments
    do {
        try process.run()
    } catch {
        fail("failed to launch screencapture: \(error)")
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("screencapture exited with status \(process.terminationStatus)")
    }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: output)),
          let bitmap = NSBitmapImageRep(data: data) else {
        fail("no readable image at \(output). Check Screen Recording permission and window state.")
    }
    return bitmap
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
case "list":
    var all = false
    var allLayers = false
    var filter: String?
    for argument in arguments.dropFirst() {
        if argument == "--all" {
            all = true
        } else if argument == "--all-layers" {
            allLayers = true
        } else if !argument.hasPrefix("--") {
            filter = argument
        }
    }

    let windows = windowList(all: all)
    print("id\towner\ttitle\tx\ty\tw\th\tlayer")
    for window in windows {
        let layer = Int(number(window[kCGWindowLayer as String]))
        if !allLayers && layer != 0 { continue }
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        if let filter, !owner.lowercased().contains(filter.lowercased()) { continue }
        let rect = bounds(of: window)
        let id = Int(number(window[kCGWindowNumber as String]))
        let title = window[kCGWindowName as String] as? String ?? ""
        print("\(id)\t\(owner)\t\(title)\t\(rect.x)\t\(rect.y)\t\(rect.width)\t\(rect.height)\t\(layer)")
    }

case "capture":
    guard arguments.count >= 3, let id = Int(arguments[1]) else { usage() }
    let output = arguments[2]
    let bitmap = runCapture(["-x", "-o", "-l\(id)", output], output: output)

    var scale = 0.0
    if let window = windowList(all: true).first(where: { Int(number($0[kCGWindowNumber as String])) == id }) {
        let rect = bounds(of: window)
        if rect.width > 0 {
            scale = Double(bitmap.pixelsWide) / rect.width
        }
    }
    print("captured \(output) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) scale=\(String(format: "%.2f", scale))")

case "screen":
    guard arguments.count >= 2 else { usage() }
    let output = arguments[1]
    let bitmap = runCapture(["-x", output], output: output)
    print("screen \(output) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")

default:
    usage()
}
