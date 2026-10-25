// BarOverlay.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// One click-through panel per display, covering that display's menu bar.
//
// Two stacking modes:
//   native  — menu bar layer + SkyLight sub-level 1: above the bar background,
//             below the real status items. Used whenever macOS already tints the
//             status items correctly for the wallpaper.
//   recolor — status-item layer, in front of the status items, showing a live
//             recoloured copy of them (see IconStream). Used when macOS tints
//             them the wrong way, e.g. white icons on a bright wallpaper.

import AppKit
import ScreenCaptureKit

@MainActor
final class BarOverlay {
    let displayID: CGDirectDisplayID
    let panel: NSPanel
    let view = BarView()
    let iconStream = IconStream()

    private(set) var barRect: CGRect = .zero          // CoreGraphics global coordinates
    private(set) var recolor = false
    private var statusLayer = 25
    private var capturing = false
    private var missingTicks = 0

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }
    var scale: CGFloat { NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2 }

    init(screen: NSScreen) {
        displayID = screen.displayID
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.contentView = view
        iconStream.onImage = { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, self.recolor else { return }
                self.view.icons = image
            }
        }
    }

    func teardown() {
        iconStream.stop()
        panel.orderOut(nil)
    }

    /// Keeps the panel on top of the bar background. Called every tick.
    func update(list: [WinInfo], locked: Bool) {
        guard let backdrop = menuBarBackdrop(for: displayID, in: list) else {
            // Locked: keep the panel up so it's already in place on unlock.
            // Otherwise (full-screen space, hidden menu bar) hide it after a short grace period.
            if !locked {
                missingTicks += 1
                if missingTicks >= 3 { panel.orderOut(nil) }
            }
            return
        }
        missingTicks = 0
        statusLayer = backdrop.layer + 1

        if backdrop.bounds != barRect {
            barRect = backdrop.bounds
            view.origin = barRect.origin
            panel.setFrame(cgToNS(barRect), display: true)
            iconStream.stop()
            Task { await captureWallpaper() }
        }

        let me = windowID
        let myIndex = list.firstIndex { $0.id == me }
        let backdropIndex = list.firstIndex { $0.id == backdrop.id }
        let iconIndices = list.indices.filter {
            list[$0].layer == statusLayer && list[$0].id != me && list[$0].bounds.width > 0
                && barRect.intersects(list[$0].bounds)
        }

        if recolor {
            if panel.level.rawValue != statusLayer { panel.level = NSWindow.Level(rawValue: statusLayer) }
            if myIndex == nil || iconIndices.contains(where: { $0 < myIndex! }) { panel.orderFrontRegardless() }
            if !iconStream.isRunning || Int.random(in: 0..<16) == 0 {      // pick up added/removed icons
                let (d, b, l, s) = (displayID, barRect, statusLayer, scale)
                Task { await iconStream.update(displayID: d, bar: b, statusLayer: l, scale: s, excluding: [me]) }
            }
        } else {
            let placed = myIndex != nil && backdropIndex != nil && myIndex! < backdropIndex!
                && iconIndices.allSatisfy { $0 < myIndex! }
            if !placed {
                if panel.level.rawValue != backdrop.layer { panel.level = NSWindow.Level(rawValue: backdrop.layer) }
                if !panel.isVisible { panel.orderFrontRegardless() }
                Sky.setSubLevel(panel.windowNumber, 1)
            }
        }
    }

    func setItems(_ items: [MenuItem]) {
        view.items = items.filter { barRect.intersects($0.frame) }
    }

    /// `point` in global AppKit coordinates (NSEvent.mouseLocation).
    func ripple(atGlobal point: CGPoint) {
        guard panel.isVisible, panel.frame.contains(point) else { return }
        view.ripple(at: CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y))
    }

    /// Chooses native vs. recolor mode from how macOS currently tints status items.
    func setMode(systemIconsDark: Bool) {
        let wantRecolor = systemIconsDark != view.darkText
        iconStream.darkTarget = view.darkText
        guard wantRecolor != recolor else { return }
        recolor = wantRecolor
        if !wantRecolor {
            iconStream.stop()
            view.icons = nil
        }
        Sky.setSubLevel(panel.windowNumber, 0)
        panel.orderOut(nil)      // re-placed by the next update()
    }

    // MARK: Wallpaper

    func captureWallpaper() async {
        guard !capturing, barRect.width > 0 else { return }
        capturing = true
        defer { capturing = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
            // Desktop-picture windows sit below the normal window layer; skip Finder's desktop icons.
            let wallpaperWindows = content.windows.filter {
                $0.windowLayer < 0
                    && $0.owningApplication?.bundleIdentifier != "com.apple.finder"
                    && $0.frame.intersects(display.frame)
            }
            guard !wallpaperWindows.isEmpty else { setWallpaper(fallbackWallpaper()); return }

            let filter = SCContentFilter(display: display, including: wallpaperWindows)
            let config = SCStreamConfiguration()
            let displayBounds = CGDisplayBounds(displayID)
            config.sourceRect = CGRect(x: barRect.minX - displayBounds.minX, y: barRect.minY - displayBounds.minY,
                                       width: barRect.width, height: barRect.height)
            config.width = Int(barRect.width * scale)
            config.height = Int(barRect.height * scale)
            config.showsCursor = false
            setWallpaper(try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
        } catch {
            setWallpaper(fallbackWallpaper())
        }
    }

    private func setWallpaper(_ image: CGImage?) {
        guard let image else { return }
        view.wallpaper = image
        view.darkText = averageLuminance(of: image) > 150
    }

    private func averageLuminance(of image: CGImage) -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return 0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])
    }

    /// Used only if the desktop-picture windows can't be captured: crops the wallpaper file.
    private func fallbackWallpaper() -> CGImage? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = NSImage(contentsOf: url),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sw = screen.frame.width, sh = screen.frame.height
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let fill = max(sw / iw, sh / ih)
        let ox = (iw * fill - sw) / 2, oy = (ih * fill - sh) / 2
        return cg.cropping(to: CGRect(x: ox / fill, y: oy / fill,
                                      width: barRect.width / fill, height: barRect.height / fill).integral)
    }
}
