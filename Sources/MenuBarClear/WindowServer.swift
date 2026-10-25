// WindowServer.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// Helpers for talking to the WindowServer: listing on-screen windows, finding
// the menu bar background window and controlling our own window's sub-level.

import AppKit

/// A snapshot of one on-screen window, as reported by CGWindowList.
struct WinInfo {
    let id: CGWindowID
    let layer: Int
    /// CoreGraphics global coordinates (origin top-left of the primary display).
    let bounds: CGRect
    let owner: String
    let pid: pid_t
    let name: String
}

/// All on-screen windows, front to back.
func onScreenWindows() -> [WinInfo] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return list.compactMap { d in
        guard let id = d[kCGWindowNumber as String] as? CGWindowID,
              let layer = d[kCGWindowLayer as String] as? Int,
              let boundsDict = d[kCGWindowBounds as String],
              let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary) else { return nil }
        return WinInfo(id: id,
                       layer: layer,
                       bounds: rect,
                       owner: d[kCGWindowOwnerName as String] as? String ?? "",
                       pid: d[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                       name: d[kCGWindowName as String] as? String ?? "")
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

/// The WindowServer-owned "Menubar" window for a display. On macOS 15 this single
/// window draws both the bar background and the frontmost app's menus.
func menuBarBackdrop(for displayID: CGDirectDisplayID, in list: [WinInfo]) -> WinInfo? {
    let displayBounds = CGDisplayBounds(displayID)
    return list.first {
        $0.owner == "Window Server" && $0.name == "Menubar"
            && abs($0.bounds.minY - displayBounds.minY) < 1
            && displayBounds.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY))
    }
}

/// CoreGraphics (top-left origin) → AppKit (bottom-left origin) global rect.
func cgToNS(_ r: CGRect) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
}

/// SkyLight (private WindowServer client framework), loaded at runtime.
///
/// AppKit can't order a window relative to windows of other processes, but the
/// WindowServer honours a window *sub-level* set by its owner. Placing our panel
/// on the menu bar's layer with sub-level 1 puts it above the bar background and
/// below every status item.
enum Sky {
    typealias MainConnectionFn = @convention(c) () -> Int32
    typealias SetSubLevelFn = @convention(c) (Int32, UInt32, Int32) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static let mainConnection: MainConnectionFn? = handle
        .flatMap { dlsym($0, "SLSMainConnectionID") }
        .map { unsafeBitCast($0, to: MainConnectionFn.self) }

    private static let setSubLevelFn: SetSubLevelFn? = handle
        .flatMap { dlsym($0, "SLSSetWindowSubLevel") }
        .map { unsafeBitCast($0, to: SetSubLevelFn.self) }

    static var isAvailable: Bool { mainConnection != nil && setSubLevelFn != nil }

    static func setSubLevel(_ windowNumber: Int, _ level: Int32) {
        guard let mainConnection, let setSubLevelFn else { return }
        _ = setSubLevelFn(mainConnection(), UInt32(windowNumber), level)
    }
}
