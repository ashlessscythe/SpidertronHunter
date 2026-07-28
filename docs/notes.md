# Architecture notes — Spidertron Hunter

## Storage keyed by unit_number

Spider AI lives in `storage.spiders[unit_number]` with a live entity reference.
Destroy registration via `script.register_on_object_destroyed` cleans up without
polling and stays multiplayer-deterministic.

## Settings cache

`settings.global` is snapshotted into `storage.settings_cache` and refreshed only
on init / `on_runtime_mod_setting_changed`. Hot loops never hit the settings table
repeatedly (UPS).

## FSM over a single brain function

States own enter/update/exit. Transitions return a next-state name from update.
Keeps combat/search/restock logic isolated and extensible for squads later.
Scout reuses moving/returning/restocking/waiting with `role == "scout"` and adds
`scout-explore` for goal picking.

## Enemy cache before scan

Shared cache avoids rediscovering the same nest. TTL + death events prune entries.
`find_nearest_enemy` is preferred over broad `find_entities_filtered` (cheaper).

## Lake routing via request_path

Base autopilot is straight-line. We use `LuaSurface.request_path` then
`add_autopilot_destination` along the path. Short hops skip pathfinding.
One path request per spider (first odd leg). If the per-tick budget is full,
requests are queued instead of falling back to direct autopilot (which stuck
group members on lakes). Stuck spiders re-path after ~3s of no progress.

Adapted pathfinding details are attributed in `NOTICE`.

## Restock is wait-with-timeout, not magic insert

No `LuaEntity.repair()`. Restock waits for player logistic requests / construction
robots, then resumes on timeout so spiders never stuck forever.

## Compatibility

Optional soft dependencies on Spidertron Patrols and Spidertron Enhancements.
Hunter is independent and not a replacement for either mod.

When present:

- Force Patrols to manual on Hunter enable; restore previous auto only when we
  know it was auto (remote table, or open schedule switch). If mode cannot be
  read, leave manual on disable so we never flip an already-manual schedule to auto.
  (`set_on_patrol` remote; `get_patrol_data` may omit its return value.)
- Listen for Enhancements `on_spidertron_replaced` to remap AI state.
- Denylist constructron / docked space-spidertron names.

## Path budget

`storage.path_requests_this_tick` resets every tick (`on_nth_tick(1)`), then the
path queue is drained. Caps how many `request_path` calls start per tick so many
hunters cannot flood the pathfinder (UPS / busy pathfinder).

## Death filters

`on_entity_died` uses entity-type filters (spawner/unit/turret/spider-unit) so we do not
run Lua on every tree/rock death.

## Think stagger

`util.for_n_of` processes at most `sh-spiders-per-think` spiders per scan interval.
Cursor persists in `storage.think_cursor` so large fleets amortize over time.

## Player remote vs AI (2026-07-21)

Bug: PATROL pulled spiders home whenever >32 tiles from home, so after a player
remote click they traveled briefly then snapped home. Also exclusive target claims
meant only one of a multi-select group kept the enemy.

Fix:
- PATROL only searches from current position; home return is RETURNING after combat.
- Soft claims (prefer unclaimed, still allow sharing).
- Player click on enemy → all selected hunters adopt that target and keep the
  player-issued autopilot path (`keep_player_destination`).
- Player click on empty ground → WAITING until arrival, then SEARCH in place.
- Pathfinder aborts applying paths while WAITING / keep_player_destination.

## Remote + shortcut

Interfaces: `SpidertronHunter` and alias `spidertron_hunter` with
enable/disable/debug/reset/scan/set_home/clear_home. Toolbar shortcut
`sh-toggle-autonomy` (spidertron tech).

## Sticky home (2026-07-23)

`sh-sticky-home-on-first-enable` (default off) keeps `ai.home` across
disable/enable once pinned (`ai.home_sticky`). First enable with sticky on
captures and pins; Clear home unpins; Set home (GUI / remote) writes current
(or given) position and pins. With the setting off, enable still refreshes home
every time (backwards compatible).

## Pursuit vs home (2026-07-21)

Re-toggling enable felt required to find enemies because enable resets Home, and
scans rejected anything beyond `max_pursuit` from the *original* home — so a
spider already in the field went blind. Fix: near home, enforce max_pursuit from
home; once deployed (>64 tiles from home), accept any enemy within search_radius.

## Post-combat linger

`sh-post-combat-linger-ticks` (default 900 / 15s; was 1800) delays RETURNING so
hunters clear camps instead of snapping home the instant the last biter dies.

## Shortcut icon

Custom spidertron-with-gun art in `graphics/shortcut/`.

## Tactical retreat (2026-07-21)

`sh-retreat-health-percent` (default 25, 0=off) forces RETURNING when combined
defense ratio drops below the threshold. `sh-retreat-include-shields` folds energy
shield equipment into that ratio. Retreat skips post-combat linger and enters
RESTOCKING at home so robots can repair / shields can refill.

## Re-engage after retreat (2026-07-22)

`sh-reengage-after-retreat` (default off) stores the map position where tactical
retreat started. After home restock/repair finishes, REENGAGING pathfinds back
to that origin and resumes SEARCH. Origin is cleared on arrival, disable, or
when the toggle is off at restock completion.

## GUI anchor

Hunter toggle uses `relative_gui_position.right` on the spidertron GUI.

## Shortcut toggle state

`toggleable = true` + `player.set_shortcut_toggled` synced from selection / enable
so the toolbar button highlights while Hunter AI is active on the current selection.

## Combat kiting (2026-07-21)

ATTACKING no longer uses `follow_target` (walked into spitters/acid). `combat.lua`
issues short direct autopilot hops at `sh-combat-range` with styles hold/strafe/
circle/flank, pauses to shoot, and rejects waypoints near `acid-splash-fire-*`.

## Multi-select unify + GUI style (2026-07-21)

Toggle on a multi-selection enables all if any are off, else disables all — so the
toolbar highlight means "whole selection is hunting." Per-spider combat style is
chosen from a drop-down next to the Hunter button; stored on `ai.combat_style`.

## Fleet path queue (2026-07-21)

Group hunts could leave some spiders stuck on lakes: the per-tick path budget was
small, each spider spent it on multiple leg requests, and budget misses fell back
to direct autopilot into water. Fix: one path request per spider, queue overflows,
retry when the engine says try-again-later, and re-path if a spider stops making
progress for ~3 seconds.

## Debug flying text (2026-07-21)

`sh-debug-mode` shows short flying text over the spidertron (not chat). Only
meaningful phases: moving / attacking / returning / restocking / waiting, plus
retreat and restock timeout. Patrol↔search chatter is suppressed. Still writes
to the Factorio log.

## Toggle debounce + keep hunting (2026-07-21)

Hotkey + toolbar both fired (`custom-input` and `on_lua_shortcut` via
`associated_control_input`), so one press enabled then immediately disabled.
Debounce to one toggle per player per tick.

State handlers no longer transition to IDLE on a transient invalid entity — only
explicit disable clears Hunter AI. After combat / return home / restock the spider
stays enabled and resumes PATROL. Think loop recovers stale entity refs via
`get_entity_by_unit_number` before dropping AI; shortcut sync removed from the
hot think path (sync on enable/disable/selection only).

## Migrations + release packaging (2026-07-22)

`scripts/schema.lua` owns storage ensure + AI record hygiene. Versioned
migrations (`0.1.0`, `0.1.5`, `0.1.7`, `0.1.9`) populate path queue / combat
fields and sanitize orphan claims. Pure Lua suite lives in `tests/run.lua`.
GitHub Release workflow emits `SpidertronHunter_<version>.zip` for Mod Portal.

## Patrols exclusive handoff (0.1.11)

Replaced refuse-enable-while-on-patrol with soft-dep handoff in
`scripts/patrols.lua`: on Hunter enable call Patrols `set_on_patrol(false)`;
on disable restore auto only when prior mode was known (remote table or open
`on_patrol_switch`). If mode cannot be read, leave manual so already-manual
schedules are not flipped to auto. Patrols stays an optional `?` dependency.

## Fleet manager (0.2.0)

`scripts/manager_gui.lua` lists spider-vehicles on the player's current surface,
grouped by `entity_label` (fallback: prototype name). Toolbar / `Ctrl+Shift+M`
opens the window; pin keeps it open across remotes and spider GUIs.

While open, create/destroy/rename/color/surface-change (and AI enable/disable)
set a dirty flag only when at least one manager window is open; the existing
`on_nth_tick(1)` path flushes by rebuilding open windows once per tick. Space
platform build/mine handlers register only when `script.feature_flags.space_travel`
is on. Event ids are gated so the same codebase runs on Factorio 2.0 and 2.1.

Group actions call into `scripts/ai.lua`:

- `follow_player` — cancel pathing, WAITING with `wait_reason = "follow-player"`,
  then vanilla `follow_target` on the player character (AI stays enabled).
- `return_home` — active AI enters RETURNING; idle spiders with a home use autopilot.
- AI toggle — same Off→Hunter / all-on→disable semantics as the toolbar (leaves
  active Scouts alone when enabling). Ctrl-click enables Off members as Scout
  (armed spiders refused with flying text; does not convert Hunters).
- Role counts under the group name (`2H, 1S`) show enabled Hunters/Scouts.
- Ctrl-click Home — `set_home` per member at current position (sticky pin).

Remote methods: `follow_player`, `return_home`.

## Scout role (0.1.20)

Any eligible spidertron can be Mode → Scout (no new vehicle entity). Scout remote
(`sh-scout-remote`) appends waypoints; vanilla remote sets focus and clears the
queue. Algorithm is a map setting (`frontier` / `lawnmower` / `spiral`) used only
when the waypoint queue is empty. Scouts `force.chart` around themselves, keep
`sh-scout-standoff-distance` from enemies (cache via targeting), never attack, and
reuse hunter restock/retreat (repair only — scouts do not wait for ammo). Scout
enable is refused while ammo slots or active-defense equipment are present; if
armed mid-run, Scout disables itself. Toolbar toggle still enables Off→Hunter only
and does not convert active Scouts. If a scout zig-zags or loops in place, it is
dodging enemies at standoff — send Hunters to clear the locals so exploration can
continue. After a standoff, the scout blacklists that goal/corridor and nest for
~45s so it picks a different fog target instead of retrying the same path.
Goals snap onto walkable land (chunk centers are often ocean); pathfinding never
falls back to direct-into-water for scouts. Unreachable / timed-out goals (~90s)
are blacklisted and replaced. Hunters still fall back to the raw goal when no
walkable snap exists so re-engage / combat pathing is not blocked in crowded nests.
