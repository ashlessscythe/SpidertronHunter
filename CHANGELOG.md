# Changelog

All notable changes to Spidertron Hunter are documented here.

## [0.1.15] — 2026-07-22

### Added

- Optional re-engage after tactical retreat: when enabled, hunters return to the coordinates where they retreated from after restock/repair, then resume hunting. Default off (`sh-reengage-after-retreat`).

### Changed

- Targets Factorio 2.1.

## [0.1.13] — 2026-07-22

### Added

- README / Mod Portal gallery with activation demo and combat-style GUI screenshot (`media/`, excluded from the release zip).

## [0.1.12] — 2026-07-22

### Fixed

- Mod Portal release package no longer includes shell scripts or other executables (Portal rejects them).

## [0.1.11] — 2026-07-22

### Added

- Spidertron Patrols soft-dep handoff: while Hunter AI is enabled, force Patrols to manual; restore automatic when disable can confirm it was auto (open schedule switch or remote data).

### Changed

- No longer refuse Hunter enable when a Patrols schedule is active; modes are handed off instead.

## [0.1.10] — 2026-07-22

### Changed

- User-focused GitHub Release notes; packaging validation and release concurrency in CI.
- Added maintainer release docs, CONTRIBUTING guide, and repository CHANGELOG.

## [0.1.9] — 2026-07-22

### Added

- Pure Lua test suite and GitHub Actions CI/release packaging for Mod Portal ZIPs.
- Storage schema helpers and versioned migrations (`0.1.0`, `0.1.5`, `0.1.7`, `0.1.9`).

## [0.1.8] — 2026-07-21

### Fixed

- Hunter toggle debounce so hotkey and toolbar no longer double-toggle in one tick.
- Hunter AI stays enabled after combat, return home, and restock (only explicit disable turns it off).

## [0.1.7] — 2026-07-21

### Fixed

- Group lake pathing: queue path requests instead of falling back to direct autopilot into water.

## [0.1.6] — 2026-07-21

### Changed

- Documented public release compatibility, development notes, and pathfinder attribution.

## [0.1.5] — 2026-07-21

### Added

- Unified multi-select toggle behavior and per-spider combat style dropdown.
- New toolbar shortcut icon.

## [0.1.4] — 2026-07-21

### Added

- Combat kiting styles (hold / strafe / circle / flank).
- Shortcut toggle highlight and README.

## Earlier

- Tactical retreat by health/shields; Hunter GUI on the right of the spidertron GUI.
- Field hunting, soft multi-target claims, and player remote fight handling.
- Initial autonomous Spidertron Hunter AI for Factorio 2.1.
