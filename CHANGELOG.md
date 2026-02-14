# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0](https://github.com/dungle-scrubs/aerospace-invader/compare/v0.2.1...v0.3.0) (2026-02-14)


### Features

* **formula:** add arm64_sonoma bottle ([4458759](https://github.com/dungle-scrubs/aerospace-invader/commit/445875913d9dd01e42867d2a801aa09a15dac5c5))


### Bug Fixes

* **hotkey:** add debouncing and signal handlers ([c793cc1](https://github.com/dungle-scrubs/aerospace-invader/commit/c793cc1edf031329ed625c17e172856b2ca08580))
* **managers:** add thread safety, error logging, protocol conformance ([6e192f1](https://github.com/dungle-scrubs/aerospace-invader/commit/6e192f11102905708811058676388dc730ac9a69))
* **ui:** remove IUOs, add deinit cleanup, fix force unwraps ([b9754dc](https://github.com/dungle-scrubs/aerospace-invader/commit/b9754dc3822def8ac5ebcb8356cd0fd01bf97e38))

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
