#!/usr/bin/env swift
import Foundation
import AppKit

func usage() -> Never {
    print("""
    usage: measure_centerline.swift <image.png> [options]

      --mode red|dark|light   red: red-dominant pixels; dark/light: luminance
      --mode probe            print RGB for every pixel in a small region
      --region x0,y0,x1,y1   pixel region of the image (y measured from top)
      --scale N              image pixels per point, default 2
      --origin x,y           crop origin in window pixels, default 0,0
      --threshold N          dark default 128; light default 200
      --flip-y               use if colorAt() returns bottom-up coordinates

    Output is a bounding box and center in pixels and points. Measure one
    control per region; do not include icons or neighboring labels.
    """)
    exit(2)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let path = arguments.first, !path.hasPrefix("--") else { usage() }

var mode = "dark"
var threshold: Int?
var scale = 2.0
var origin = (x: 0.0, y: 0.0)
var region: (x0: Int, y0: Int, x1: Int, y1: Int)?
var flipY = false

var index = 1
while index < arguments.count {
    let key = arguments[index]
    switch key {
    case "--mode":
        guard index + 1 < arguments.count else { usage() }
        mode = arguments[index + 1]
        index += 2
    case "--threshold":
        guard index + 1 < arguments.count, let value = Int(arguments[index + 1]) else { usage() }
        threshold = value
        index += 2
    case "--scale":
        guard index + 1 < arguments.count, let value = Double(arguments[index + 1]), value > 0 else { usage() }
        scale = value
        index += 2
    case "--origin":
        guard index + 1 < arguments.count else { usage() }
        let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { fail("--origin expects x,y") }
        origin = (parts[0], parts[1])
        index += 2
    case "--region":
        guard index + 1 < arguments.count else { usage() }
        let parts = arguments[index + 1].split(separator: ",").compactMap { Int($0) }
        guard parts.count == 4 else { fail("--region expects x0,y0,x1,y1") }
        region = (parts[0], parts[1], parts[2], parts[3])
        index += 2
    case "--flip-y":
        flipY = true
        index += 1
    case "--help", "-h":
        usage()
    default:
        fail("unknown argument: \(key)")
    }
}

guard ["red", "dark", "light", "probe"].contains(mode) else {
    fail("--mode must be red, dark, light or probe")
}

guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let bitmap = NSBitmapImageRep(data: data) else {
    fail("cannot read image: \(path)")
}

let imageWidth = bitmap.pixelsWide
let imageHeight = bitmap.pixelsHigh
let x0 = max(0, region?.x0 ?? 0)
let y0 = max(0, region?.y0 ?? 0)
let x1 = min(imageWidth, region?.x1 ?? imageWidth)
let y1 = min(imageHeight, region?.y1 ?? imageHeight)
guard x1 > x0, y1 > y0 else {
    fail("empty region \(x0),\(y0),\(x1),\(y1) for image \(imageWidth)x\(imageHeight)")
}

var minX = Int.max
var minY = Int.max
var maxX = Int.min
var maxY = Int.min
var count = 0

for y in y0..<y1 {
    let sourceY = flipY ? imageHeight - 1 - y : y
    for x in x0..<x1 {
        guard let color = bitmap.colorAt(x: x, y: sourceY)?.usingColorSpace(.sRGB) else { continue }
        if color.alphaComponent < 0.1 { continue }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        let luminance = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)

        if mode == "probe" {
            print("probe x=\(x) y=\(y) rgb=(\(r),\(g),\(b))")
            continue
        }

        let matched: Bool
        switch mode {
        case "red":
            matched = r >= 200 && r - g >= 70 && r - b >= 70
        case "dark":
            matched = luminance <= Double(threshold ?? 128)
        default:
            matched = luminance >= Double(threshold ?? 200)
        }

        if matched {
            count += 1
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

if mode == "probe" { exit(0) }

print("image=\(imageWidth)x\(imageHeight) scale=\(String(format: "%.2f", scale))")
print("mode=\(mode) region_px=\(x0),\(y0),\(x1),\(y1) count=\(count)")

guard count > 0 else {
    print("bbox_px=none")
    print("hint=no pixels matched; check --region, --mode and --threshold (dark text vs light text)")
    exit(1)
}

let centerX = Double(minX + maxX) / 2.0
let centerY = Double(minY + maxY) / 2.0
let absoluteX = (centerX + origin.x) / scale
let absoluteY = (centerY + origin.y) / scale

print("bbox_px=\(minX),\(minY)..\(maxX),\(maxY)")
print(String(format: "bbox_pt=%.2f,%.2f..%.2f,%.2f",
             Double(minX) / scale, Double(minY) / scale,
             Double(maxX) / scale, Double(maxY) / scale))
print(String(format: "center_px=(%.2f,%.2f)", centerX, centerY))
print(String(format: "center_pt=(%.2f,%.2f)", centerX / scale, centerY / scale))
print(String(format: "absolute_pt=(%.2f,%.2f)", absoluteX, absoluteY))
