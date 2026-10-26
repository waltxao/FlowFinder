#!/usr/bin/env swift
import AppKit
import Foundation

// Validates SF Symbol names against the macOS that runs this script.
// It cannot prove availability on an older deployment target.

func fail(_ message: String) {
    fputs(message + "\n", stderr)
}

var names = Array(CommandLine.arguments.dropFirst())

if names.isEmpty {
    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            continue
        }
        names.append(trimmed)
    }
}

guard !names.isEmpty else {
    fail("Usage: swift validate-sf-symbols.swift <symbol> [symbol ...]")
    fail("   or: printf '%s\\n' arrow.left rectangle.grid.1x2 | swift validate-sf-symbols.swift")
    exit(2)
}

var invalid: [String] = []

for name in names {
    if NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
        invalid.append(name)
        print("INVALID \(name)")
    } else {
        print("OK \(name)")
    }
}

if !invalid.isEmpty {
    fail("")
    fail("Invalid SF Symbols (\(invalid.count)):")
    for name in invalid {
        fail("  - \(name)")
    }
    fail("Validated on the current macOS only; re-check the minimum deployment target.")
    exit(1)
}

print("")
print("All \(names.count) SF Symbol name(s) resolve on this macOS.")
print("Re-check on the minimum deployment target before shipping.")
