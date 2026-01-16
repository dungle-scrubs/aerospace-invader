# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.3] - 2026-01-16

### Fixed

- `⌥P` (refresh) now shows tab bar instantly using cached data like `⌥O`/`⌥I`

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
