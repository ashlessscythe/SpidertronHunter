# Changelog

All notable changes to Spidertron Hunter are documented here.

## [Unreleased]

## [0.2.15] - 2026-11-24

### Added

- Fleet stress tests (50 and 100 hunters against 10 nests across a lake, tagged `stress`, excluded from the default run) check the think stagger and path queue budgets, that no hunter is starved, and log the Lua time of the mod's periodic handlers.

### Changed

- In "nearest" targeting mode, a hunter whose nearest nest is too dangerous now falls back to the next-nearest safe target instead of idling.

### Developer

- Test runners take `--list` and `--run <text>` to list or select tests; the watch script also takes `--speed <n>`.
- The watch script works again on macOS Factorio 2.1.25 (the generated test config needs a `[sound]` setting).
- Multi-nest campaigns only require kiting on nests the hunter spent at least 8 s near.

## [0.2.14] - 2026-11-23

### Fixed

- Hunters no longer ping-pong between home and the field when a restock gives up (no logistics network, or the wait timed out) with ammo still low or health still below the retreat threshold. Before, they resumed hunting immediately, headed back after a few seconds (even firing with empty launchers), and repeated every restock timeout, so later nests were barely fought. They now wait at home until ammo or health recover, then resume, and raise an "out of ammo" / "needs repair" alert (repeated at most every 5 minutes).

### Changed

- Threat awareness is less timid: capacity is now 1 point per 30 hp (a full-health spidertron ~100 points at Normal, ~50 at Cautious). In the multi-nest scenario a nest scoring 19 cost a full-health hunter only ~250 hp, yet Cautious used to refuse it and leave the later nests untouched.

### Added

- "Close in with lasers" setting (off by default): hunters carrying personal laser defense fight at 12 tiles, inside laser range.
- Multi-nest campaigns now also cover every moving combat style (strafe, circle, flank; hold is stationary by design) and spidertrons carrying personal laser defense + batteries, at the default combat range and at a laser-friendly 12. Lasers shortened the clear of three hard nests from about 140-160 s (rockets only) to about 100 s at the default range and about 80 s at range 12, at the cost of noticeably more damage taken at range 12.
- Multi-nest campaign scenarios (`tests/factorio/multi_nest.lua`): three nests in a row with threat awareness off / normal / cautious, easy and hard nests, default and stocked ammo. They check that nests are cleared, the hunter keeps kiting, never attacks from a standstill for long, and does not ping-pong when ammo runs out.
- Unit tests for the resupply blocker and the restocking → waiting → patrol flow.

- Threat awareness: hunters now judge a nest before attacking. The worms and spawners within 40 tiles of a candidate target are scored (small worm 3, medium 6, big 12, behemoth 30, spawner 1) against the hunter's current hull + shield health (30 hp per point; a full-health spidertron is about 100). A nest scoring higher is skipped for a minute, and the hunter raises an "is avoiding a nest" alert. A damaged hunter becomes more cautious automatically.
- New runtime-global setting **Threat awareness** (Off / Normal / Cautious, default Normal). Cautious skips at half the danger Normal does. Scouts are unaffected.
- Alerts: a spidertron that retreats at low health, gets stuck (repeated re-paths in the same spot) or is destroyed now alerts you. Retreat and stuck use Factorio's custom alerts (edge-of-screen icon, click to locate); a destroyed spidertron prints a chat line with a map ping. Each kind is throttled per spider to 30 s.
- New runtime-global setting **Alerts** (Off / Important / All). Important is the default; All also alerts when a hunter heads home for ammo.
- Unit tests for alert levels, throttling, stuck counting and the death message, and in-game checks that a real retreat raises (or, with alerts off, doesn't raise) a custom alert.

## [0.2.13] — 2026-11-23

### Fixed

- A Hunter-AI spider ordered with Ctrl+right-click onto water now walks to the nearest shore and resumes hunting, instead of pushing at the shore for the whole travel budget. If only water is in range the order is refused with a "no path" message.

### Added

- Unit tests for the lake-order snapping, plus in-game scenarios for a hunter ordered into a lake and for a U-shaped bay (hunter and Ctrl+RMB go-to must leave through the mouth and go around an arm).

## [0.2.12] — 2026-11-23

### Fixed

- Ctrl+right-click (Hunter off) on a spot inside a lake now ends on the nearest shore instead of leaving the spider pushing at the water's edge toward the clicked point forever.
- Fleet manager window position is now remembered per player instead of shared, so multiplayer clients no longer move each other's window.
- A spider whose path request is queued keeps its place in line when its goal changes (including via `request_path_to`), so it can't be starved by a full path budget.
- Hunters now return home after combat even when their target dies to auto-targeting while they are still walking toward it; previously they idled at the kill site forever.
- "Spawners first" and "Units first" target priority now applies to a hunter's first target; before, the nearest enemy always won until the enemy cache warmed up.

### Changed

- Split `scripts/ai.lua` into `ai.lua` (orchestration), `ai_states.lua` (state handlers) and `ai_common.lua` (shared helpers). No behaviour change.

### Added

- Pathfinder unit tests (`tests/pathfinder_spec.lua`) against a fake lake: water snapping for hunters vs scouts, budget/queue ordering, busy back-off, resolution retries, exhausted-path fallbacks, waypoint thinning and stuck recovery.
- In-game lake scenarios (`tests/factorio/lake_paths.lua`): Ctrl+RMB around a lake, goal inside a lake, scout waypoint across a lake, hunter return trip, and six hunters sharing the path budget.
- In-game test suite using [factorio-test](https://github.com/GlassBricks/FactorioTest), run headless in Docker (`scripts/run_factorio_tests.sh`) or step by step in a real Factorio window (`scripts/watch_factorio_tests.sh`).
- Visual hunter scenarios: lone biter, biter nest, and a lake the hunter must walk around.
- CI job running the in-game tests on headless Factorio.
- Behaviour tests: disable stops the spider, nearest-target priority, low-health retreat, scout waypoint without attacking, following the player, two hunters splitting nests, and keeping combat distance.

## [0.2.11] — 2026-11-22

### Fixed

- Hunters now actually use lake-aware paths when going after targets. Spiders previously used with Ctrl+RMB while Hunter was off kept stale path state that discarded every autonomous path result, leaving hunters walking straight lines.
- Hunters re-targeting a far mob after a kill (or a target that moved far away) now travel with the lake-aware pathfinder instead of straight-line kiting hops.
- Ctrl+RMB no longer races the vanilla remote event, which could override the lake-aware path.
- Enemy cache pruning now sweeps the whole cache, and killing one enemy no longer forgets same-named neighbours in its chunk.
- Dead spider records release their claims and path state; standalone path state is freed when a spidertron is destroyed.
- Pathfinder busy responses back off instead of re-requesting every tick.
- Hunter toolbar icon is no longer cropped; thumbnail reduced to 144x144.
- AI records are sanitized on every mod/game version change.

### Added

- Debug mode logs path requests, results and drop reasons.

## [0.2.10] — 2026-11-22

### Changed

- Reworded the Mod Portal description intro; release pipeline now publishes to the Mod Portal automatically.

## [0.2.9] — 2026-08-30

### Added

- **Built-in lake-aware Ctrl+right-click** works on any spidertron with a vanilla remote — **no Hunter AI required** and no dependency on Spidertron Enhancements. Includes own `large_entity` collision layer for routing around large buildings.
- Vertical spidertron settings panel (Mode, Style, Home buttons, status) to the right of the inventory GUI.
- Gallery screenshot for the vertical settings panel (`media/combat_style_gui.png`).

### Changed

- All lake-aware pathing (autonomous AI and Ctrl+RMB) shares one pathfinder module; optional mods remain compat-only (Patrols handoff, Enhancements entity remap).

## [0.2.8] — 2026-08-10

### Added

- Hunters return home to restock when on-hand ammo drops to **Restock ammo %** of their logistic ammo request (default 20; 0 disables). Counts quality-specific requests (e.g. legendary rockets). Falls back to ammo count at enable if there is no ammo request. At-home restock waits until requests are filled (with timeout).

### Changed

- Targets Factorio **2.1** only going forward.

## [0.2.6] — 2026-07-28

### Added

- Hunter Ctrl+right-click with a spidertron remote: lake-aware path via the Hunter pathfinder (ground travel then hunt; enemy path then fight). Plain right-click remains straight vanilla autopilot.

## [0.2.4] — 2026-07-27

### Added

- Fleet manager AI: **Ctrl-click** enables Off members as Scout (armed spiders refused with flying text; does not convert active Hunters). Plain click still Off→Hunter / all-on→disable.
- Fleet manager group cards show active role counts under the name (e.g. `2H, 1S`).
- Scout Ctrl+right-click with a spidertron remote: lake-aware path via the Hunter pathfinder (waypoint or focus depending on remote).

## [0.2.3] — 2026-07-27

### Changed

- Targets Factorio 2.1.

## [0.2.2] — 2026-07-25

### Fixed

- Fleet manager now refreshes while open when spidertrons are created, destroyed, renamed, recolored, or when the player changes surface (UPS-friendly dirty flag + deferred rebuild).
- AI enable/disable (toolbar, relative GUI, or manager) updates fleet manager AI button state when the window is open.

## [0.2.1] — 2026-07-24

### Changed

- Targets Factorio 2.0.

## [0.2.0] — 2026-07-24

### Added

- Fleet manager GUI (`Ctrl+Shift+M` / **Hunter fleet** toolbar): spidertrons on the current surface grouped by entity label, with follow player, group remote, go home (Ctrl-click to set home), remote-view, open settings, AI toggle, and pin.
- Remote interface: `follow_player`, `return_home`.
- Gallery screenshot for the fleet manager (`media/fleet_manager.png`).

## [0.1.26] — 2026-07-24

### Fixed

- Scout remote item flags no longer use a Factorio 2.1-only flag when targeting 2.0.

## [0.1.25] — 2026-07-23

### Added

- Gallery screenshot for scout explore paths (`media/scout_paths.png`).

### Changed

- Targets Factorio 2.0.

## [0.1.24] — 2026-07-23

### Fixed

- Hunter re-engage / combat pathing: walkable-land requirement is scout-only again. Hunters fall back to the raw goal when no snap exists so crowded nests no longer softlock pathing.

## [0.1.22] — 2026-07-23

### Fixed

- Scout zigzag after standoff: temporarily blacklist the blocked goal/corridor so the scout picks a different fog target instead of oscillating.
- Scout stuck on ocean/unreachable goals: snap destinations to walkable land, never direct-autopilot into water, and abandon goals that time out (~90s).

### Added

- Pure Lua tests for walkable snap, path-failure blacklist, and scout goal timeout.

## [0.1.20] — 2026-07-23

### Added

- Scout role on any eligible spidertron (GUI Mode: Off / Hunter / Scout). Scouts explore and chart fog, keep standoff from biters, record nests into the shared enemy cache, and never engage. Scout requires empty ammo (and no active-defense equipment); refused at enable and aborted if armed mid-run.
- Scout remote (`sh-scout-remote`, Alt+Shift+A / toolbar): append explore waypoints. Vanilla spidertron remote sets scout focus (clears waypoints).
- Scout map settings: algorithm (`frontier` / `lawnmower` / `spiral`), max distance, max time, standoff, chart radius, auto-resume.
- Remote interface: `get_role`, `set_role`, `set_scout_focus`, `add_scout_waypoint`, `clear_scout_waypoints`.

## [0.1.17] — 2026-07-23

### Added

- Optional sticky home (`sh-sticky-home-on-first-enable`, default off): when enabled, home is set on first enable and kept across disable/enable until Clear home. Per-spider Set home / Clear home buttons on the spidertron GUI; remote `set_home` pins and `clear_home` unpins.

### Changed

- Targets Factorio 2.1.

## [0.1.16] — 2026-07-23

### Changed

- Targets Factorio 2.0.

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
