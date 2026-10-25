// Controller.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// Owns one BarOverlay per display and keeps them in sync with the system:
// app switches, Spaces, display changes, lock/unlock, wallpaper changes, clicks.

import AppKit

@MainActor
final class Controller {
    private(set) var isEnabled = false

    private var overlays: [BarOverlay] = []
    private let menuReader = MenuReader()
    private var timers: [Timer] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var wallpaperWatchers: [DispatchSourceFileSystemObject] = []
    private var clickMonitor: Any?
    private var locked = false

    /// Zero-width status item whose appearance tells us how macOS tints status items right now.
    private let appearanceProbe = NSStatusBar.system.statusItem(withLength: 0)
    private var systemIconsDark = false

    init() {
        menuReader.onChange = { [weak self] in
            guard let self else { return }
            self.overlays.forEach { $0.setItems(self.menuReader.items) }
        }
    }

    // MARK: Enable / disable

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? start() : stop()
    }

    private func start() {
        rebuildOverlays()

        let nc = NotificationCenter.default
        let wnc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        observe(nc, NSApplication.didChangeScreenParametersNotification) { $0.rebuildOverlays() }
        observe(wnc, NSWorkspace.activeSpaceDidChangeNotification) { $0.tick(); $0.captureAll() }
        observe(wnc, NSWorkspace.didActivateApplicationNotification) { $0.menuReader.refresh(); $0.tick() }
        observe(wnc, NSWorkspace.sessionDidBecomeActiveNotification) { $0.settle() }
        observe(wnc, NSWorkspace.screensDidWakeNotification) { $0.settle() }
        observe(dnc, .init("com.apple.screenIsLocked")) { $0.locked = true }
        observe(dnc, .init("com.apple.screenIsUnlocked")) { $0.locked = false; $0.settle() }
        observe(dnc, .init("com.apple.desktop")) { $0.wallpaperChanged() }

        // Ripple wherever the menu bar is clicked. Global monitors only observe; clicks pass through untouched.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.overlays.forEach { $0.ripple(atGlobal: point) } }
        }

        timers = [
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            },
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.captureAll() }
            },
        ]
        timers.forEach { RunLoop.main.add($0, forMode: .common) }     // keep running while menus are open
        watchWallpaperStore()
    }

    private func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        wallpaperWatchers.forEach { $0.cancel() }
        wallpaperWatchers = []
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        overlays.forEach { $0.teardown() }
        overlays = []
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (Controller) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        }
        observers.append((center, token))
    }

    // MARK: Work

    private func rebuildOverlays() {
        overlays.forEach { $0.teardown() }
        overlays = NSScreen.screens.map { BarOverlay(screen: $0) }
        tick()
        overlays.forEach { $0.setItems(menuReader.items) }
        captureAll()
    }

    private func tick() {
        let list = onScreenWindows()
        menuReader.refresh()
        if let appearance = appearanceProbe.button?.effectiveAppearance {
            // A light (aqua / vibrantLight) menu bar means macOS draws status items dark.
            systemIconsDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
        }
        for overlay in overlays {
            overlay.setMode(systemIconsDark: systemIconsDark)
            overlay.update(list: list, locked: locked)
        }
    }

    private func captureAll() {
        for overlay in overlays {
            Task { [weak self] in
                await overlay.captureWallpaper()
                self?.tick()
            }
        }
    }

    /// After unlock / wake / login: re-anchor right away and a few more times while the system settles.
    private func settle() {
        for delay in [0.0, 0.05, 0.15, 0.3, 0.6, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        captureAll()
    }

    /// Re-capture repeatedly to follow the wallpaper cross-fade until it settles.
    private func wallpaperChanged() {
        for delay in [0.0, 0.15, 0.35, 0.6, 1.0, 1.6, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.captureAll() }
            }
        }
    }

    /// macOS 14+ stores the wallpaper configuration here; it changes the instant a wallpaper is picked.
    private func watchWallpaperStore() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper")
        for dir in [base.appendingPathComponent("Store"), base] {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.wallpaperChanged() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            wallpaperWatchers.append(source)
        }
    }
}
