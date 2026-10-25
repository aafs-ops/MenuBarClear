// AppDelegate.swift
// MenuBarClear — https://github.com/aafs-ops/MenuBarClear
// Copyright © 2026 aafs-ops. MIT License.
//
// App lifecycle, the MenuBarClear status item and its menu, launch at login and
// the permission prompts.
//
// Hiding the status item: "Hide Menu Bar Icon" removes it. Opening MenuBarClear
// again (Finder, Spotlight, Launchpad, `open -a MenuBarClear`) while it's running
// brings the icon back. This is the usual approach for menu bar utilities.

import AppKit
import ApplicationServices
import ServiceManagement

enum Defaults {
    static let showMenuBarIcon = "ShowMenuBarIcon"
    static let enabled = "Enabled"
}

enum AppInfo {
    static let name = "MenuBarClear"
    static let author = "aafs-ops"
    static let repository = URL(string: "https://github.com/aafs-ops/MenuBarClear")!
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = Controller()
    private var statusItem: NSStatusItem?
    private let defaults = UserDefaults.standard

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Defaults.showMenuBarIcon: true, Defaults.enabled: true])

        setUpStatusItem()
        requestPermissions()

        if !Sky.isAvailable {
            NSLog("MenuBarClear: SkyLight sub-level API unavailable; the overlay may not stack correctly.")
        }
        controller.setEnabled(defaults.bool(forKey: Defaults.enabled))
    }

    /// Opening the app again while it's running brings back a hidden menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setMenuBarIconVisible(true)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.setEnabled(false)
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "MenuBarClearStatusItem"
        if let button = item.button {
            let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.appearsDisabled = !defaults.bool(forKey: Defaults.enabled)
            button.toolTip = AppInfo.name
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        item.isVisible = defaults.bool(forKey: Defaults.showMenuBarIcon)
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // Left or right click: show the menu.
        guard let statusItem else { return }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil          // keep handling clicks ourselves next time
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Clear Menu Bar", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = controller.isEnabled ? .on : .off
        menu.addItem(enabled)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !hasAllPermissions {
            menu.addItem(.separator())
            let permissions = NSMenuItem(title: "Grant Permissions…", action: #selector(showPermissionsHelp),
                                         keyEquivalent: "")
            permissions.target = self
            permissions.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(permissions)
        }

        menu.addItem(.separator())

        let hide = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        let about = NSMenuItem(title: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let restart = NSMenuItem(title: "Restart", action: #selector(relaunch), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func setMenuBarIconVisible(_ visible: Bool) {
        defaults.set(visible, forKey: Defaults.showMenuBarIcon)
        statusItem?.isVisible = visible
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        let enabled = !controller.isEnabled
        controller.setEnabled(enabled)
        defaults.set(enabled, forKey: Defaults.enabled)
        statusItem?.button?.appearsDisabled = !enabled     // dimmed icon while paused
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "Couldn't change Launch at Login",
                      message: "\(error.localizedDescription)\n\nMove MenuBarClear to the Applications folder and "
                          + "try again, or add it manually in System Settings → General → Login Items.")
        }
    }

    @objc private func hideMenuBarIcon() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hide the MenuBarClear icon?"
        alert.informativeText = "MenuBarClear keeps running. To show the icon again, open MenuBarClear "
            + "again from Applications, Spotlight or Launchpad."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            setMenuBarIconVisible(false)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(
            string: "Removes the menu bar background on macOS.\nCreated by \(AppInfo.author).\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(
            string: AppInfo.repository.absoluteString,
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: AppInfo.repository]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Permissions

    private var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }
    private var hasAccessibility: Bool { AXIsProcessTrusted() }
    private var hasAllPermissions: Bool { hasScreenRecording && hasAccessibility }

    private func requestPermissions() {
        guard !hasAllPermissions else { return }
        // These calls add MenuBarClear to the lists in System Settings.
        if !hasScreenRecording { CGRequestScreenCaptureAccess() }
        if !hasAccessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.showPermissionsHelp() }
        }
    }

    @objc private func showPermissionsHelp() {
        guard !hasAllPermissions else { return }
        NSApp.activate(ignoringOtherApps: true)
        var missing: [String] = []
        if !hasScreenRecording { missing.append("• Screen & System Audio Recording: to see the wallpaper behind the bar") }
        if !hasAccessibility { missing.append("• Accessibility: to read menu positions and see menu bar clicks") }

        let alert = NSAlert()
        alert.messageText = "MenuBarClear needs permission"
        alert.informativeText = missing.joined(separator: "\n")
            + "\n\nTurn MenuBarClear on in System Settings → Privacy & Security, then restart MenuBarClear."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Restart MenuBarClear")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let pane = hasScreenRecording ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
