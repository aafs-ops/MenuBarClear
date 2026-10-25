// main.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// Entry point.
//   MenuBarClear          run normally
//   MenuBarClear --list   print the windows at the top of each display and the
//                         frontmost app's menu items (for bug reports)

import AppKit

if CommandLine.arguments.contains("--list") {
    let list = onScreenWindows()
    for screen in NSScreen.screens {
        let bounds = CGDisplayBounds(screen.displayID)
        print("Display \(screen.displayID) bounds=\(bounds)")
        for w in list where abs(w.bounds.minY - bounds.minY) < 1 && w.layer >= 0 && bounds.intersects(w.bounds) {
            print(String(format: "  id=%-6u layer=%-4d %@  owner=%@  name=%@",
                         w.id, w.layer, NSStringFromRect(w.bounds), w.owner, w.name))
        }
    }
    print("Menu items:")
    for item in readMenuItemsOfMenuBarOwner() {
        print("  [\(item.index)] \(item.title)  \(NSStringFromRect(item.frame))")
    }
    print("SkyLight sub-level API available: \(Sky.isAvailable)")
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
