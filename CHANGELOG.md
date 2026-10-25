# Changelog

All notable changes to MenuBarClear are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-25

### Added
- Removes the menu bar background on macOS Sequoia: menus and status items float directly on the wallpaper.
- Live wallpaper tracking: the bar updates the moment the wallpaper changes, including cross-fades.
- Adaptive text: black menus on bright wallpapers, white on dark ones.
- Status items are recoloured live to match when macOS tints them the wrong way for the wallpaper.
- Liquid-glass ripple at the exact point of every menu bar click.
- Menu bar icon with: Clear Menu Bar (pause/resume), Launch at Login, Hide Menu Bar Icon, About, Restart, Quit.
- Hidden menu bar icon comes back by opening MenuBarClear again.
- Multi-display support, Spaces, full-screen apps and lock/unlock handling.
- Instant menu redraw when switching apps (per-app cache; previous menus stay until new ones are ready).
- `--list` diagnostics flag for bug reports.
- Drag-to-install DMG with custom background and volume icon (`make dmg`).
