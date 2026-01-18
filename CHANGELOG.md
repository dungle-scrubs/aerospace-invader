# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-01-18

### Added

- Which-key window auto-closes when AeroSpace mode changes (no more `pkill` needed in config)

## [0.1.5] - 2026-01-16

### Fixed

- `⌥P` toggle now tracks manual workspace switches (via AeroSpace keybinds) correctly

## [0.1.4] - 2026-01-16

### Changed

- `⌥P` now handles workspace toggle internally instead of relying on AeroSpace's `workspace-back-and-forth`
- All navigation hotkeys (`⌥O`, `⌥I`, `⌥P`) now have identical cache-first performance

### Fixed

- `⌥P` shows tab bar instantly (previously waited for API call)

## [0.1.3] - 2026-01-16

### Fixed

- Reverted cache-first for refresh (caused stale data display)

## [0.1.2] - 2026-01-16

### Fixed

- WhichKey window now uses CGEventTap to detect Escape key, fixing the double-press issue

## [0.1.1] - 2026-01-16

### Fixed

- WhichKey window now closes on first Escape press
- Workspace bar no longer steals focus from apps

## [0.1.0] - 2026-01-16

### Added

- Initial release
- Workspace cycling with `⌥O` (back) and `⌥I` (forward)
- Show workspace bar with `⌥P`
- Expandable OSD with `⌥.`
- Drag-to-reorder workspaces in expanded view
- Persistent workspace ordering
- Which-key display for AeroSpace modes
- Auto-enable AeroSpace if not running
- Configurable hotkeys via `~/.config/aerospace-invader/config.json`
- Homebrew formula with service support
