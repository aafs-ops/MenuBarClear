# Contributing

Thanks for helping improve MenuBarClear!

## Building

```sh
xcode-select --install   # once, if you don't have Xcode
make run                 # build and launch from ./build
make install             # build and install into /Applications
```

Every ad-hoc build has a new code signature, so macOS asks for **Screen & System Audio Recording** and **Accessibility** again after each rebuild. Remove the old MenuBarClear entries in System Settings → Privacy & Security, then allow the new one.

## Project layout

| File | Purpose |
| --- | --- |
| `main.swift` | Entry point and the `--list` diagnostics command |
| `AppDelegate.swift` | Menu bar icon, its menu, launch at login, permission prompts |
| `Controller.swift` | Wires system events (app switches, Spaces, lock, wallpaper, clicks) to the overlays |
| `BarOverlay.swift` | One click-through panel per display; stacking and wallpaper capture |
| `BarView.swift` | Draws wallpaper, menus and the liquid-glass ripple |
| `MenuReader.swift` | Reads menu titles/positions via Accessibility, with a per-app cache |
| `IconStream.swift` | Live recoloured copy of status items (ScreenCaptureKit) |
| `WindowServer.swift` | CGWindowList helpers and the SkyLight sub-level call |

## Bug reports

Please include your macOS version, Mac model and the output of:

```sh
/Applications/MenuBarClear.app/Contents/MacOS/MenuBarClear --list
```

## Pull requests

- Keep changes focused; one feature or fix per PR.
- Match the existing style (4-space indent, `// MARK:` sections).
- Test on at least one display with a bright and a dark wallpaper.
