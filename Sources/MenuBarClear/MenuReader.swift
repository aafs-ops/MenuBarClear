// MenuReader.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// Reads the frontmost app's menu titles and positions through the
// Accessibility API so they can be redrawn on top of the cleared bar.
//
// Switching apps must never leave the bar empty:
//   • Accessibility reads run off the main thread.
//   • Every app's last good menu layout is cached, so switching back to an app
//     redraws its menus instantly.
//   • An app with no cached layout keeps the previous menus on screen until its
//     own layout has actually arrived; an empty or failed read never clears the bar.

import AppKit
import ApplicationServices

struct MenuItem: Equatable {
    let title: String
    /// CoreGraphics global coordinates.
    let frame: CGRect
    /// 0 = Apple menu, 1 = application menu (bold), 2… = regular menus.
    let index: Int
}

private func axValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? T
}

/// Synchronously reads an app's menu bar. Returns `nil` when the app isn't ready.
func readMenuItems(pid: pid_t) -> [MenuItem]? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    var menuBarRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
          let menuBarRef,
          let children: [AXUIElement] = axValue(menuBarRef as! AXUIElement, kAXChildrenAttribute) else { return nil }

    var items: [MenuItem] = []
    for (index, element) in children.enumerated() {
        var position = CGPoint.zero, size = CGSize.zero
        if let v: AXValue = axValue(element, kAXPositionAttribute) { AXValueGetValue(v, .cgPoint, &position) }
        if let v: AXValue = axValue(element, kAXSizeAttribute) { AXValueGetValue(v, .cgSize, &size) }
        guard size.width > 0, size.height > 0 else { continue }
        items.append(MenuItem(title: axValue(element, kAXTitleAttribute) ?? "",
                              frame: CGRect(origin: position, size: size),
                              index: index))
    }
    return items
}

/// Convenience for the `--list` debug command.
func readMenuItemsOfMenuBarOwner() -> [MenuItem] {
    guard let app = NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication else { return [] }
    return readMenuItems(pid: app.processIdentifier) ?? []
}

@MainActor
final class MenuReader {
    /// Items currently shown (never cleared by a failed or in-progress read).
    private(set) var items: [MenuItem] = []
    var onChange: (() -> Void)?

    private var shownPID: pid_t = 0
    private var cache: [pid_t: [MenuItem]] = [:]
    private var inFlight = false
    private var rerunRequested = false
    private let queue = DispatchQueue(label: "io.github.aafs-ops.MenuBarClear.menus", qos: .userInteractive)
    private var ownerObservation: NSKeyValueObservation?
    private var terminateObserver: NSObjectProtocol?

    init() {
        // React the moment the menu bar changes hands, not on the next timer tick.
        ownerObservation = NSWorkspace.shared.observe(\.menuBarOwningApplication, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { _ = self?.cache.removeValue(forKey: pid) }
        }
    }

    private var ownerPID: pid_t? {
        (NSWorkspace.shared.menuBarOwningApplication ?? NSWorkspace.shared.frontmostApplication)?.processIdentifier
    }

    func refresh() {
        guard let target = ownerPID else { return }

        // Instant switch from the cache.
        if target != shownPID, let cached = cache[target] {
            shownPID = target
            publish(cached)
        }

        guard !inFlight else { rerunRequested = true; return }
        inFlight = true
        queue.async { [weak self] in
            let result = readMenuItems(pid: target)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.inFlight = false
                    // A valid menu bar always has at least the Apple menu and the app menu.
                    if let result, result.count >= 2 {
                        self.cache[target] = result
                        if self.ownerPID == target {
                            self.shownPID = target
                            self.publish(result)
                        }
                    }
                    if self.rerunRequested {
                        self.rerunRequested = false
                        self.refresh()
                    }
                }
            }
        }
    }

    private func publish(_ newItems: [MenuItem]) {
        guard newItems != items else { return }
        items = newItems
        onChange?()
    }
}
