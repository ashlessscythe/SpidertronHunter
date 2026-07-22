# Architecture notes — Spidertron Hunter

## Storage keyed by unit_number

Spider AI lives in `storage.spiders[unit_number]` with a live entity reference.
Destroy registration via `script.register_on_object_destroyed` cleans up without
polling. This matches SpidertronPatrols and stays multiplayer-deterministic.

## Settings cache

`settings.global` is snapshotted into `storage.settings_cache` and refreshed only
on init / `on_runtime_mod_setting_changed`. Hot loops never hit the settings table
repeatedly (UPS).

## FSM over a single brain function

States own enter/update/exit. Transitions return a next-state name from update.
Keeps combat/search/restock logic isolated and extensible for squads later.

## Enemy cache before scan

Shared cache avoids rediscovering the same nest. TTL + death events prune entries.
`find_nearest_enemy` is preferred over broad `find_entities_filtered` (cheaper).

## Lake routing via request_path

Base autopilot is straight-line. We use `LuaSurface.request_path` then
`add_autopilot_destination` along the path (Enhancements pattern, owned code).
Short hops skip pathfinding. Concurrent requests are capped for UPS.

## Restock is wait-with-timeout, not magic insert

No `LuaEntity.repair()`. Restock waits for player logistic requests / construction
robots, then resumes on timeout so spiders never stuck forever.

## Compatibility

Refuse enable while SpidertronPatrols has `on_patrol` when their remote returns data.
Soft deps only. Denylist constructron / docked space-spidertron names.

Listen for Enhancements `on_spidertron_replaced` when that custom event prototype exists.

## Path budget

`storage.path_requests_this_tick` resets every tick (`on_nth_tick(1)`). Caps concurrent
`request_path` calls so many hunters cannot flood the pathfinder (UPS / busy pathfinder).

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
enable/disable/debug/reset/scan. Toolbar shortcut `sh-toggle-autonomy` (spidertron tech).

## Pursuit vs home (2026-07-21)

Re-toggling enable felt required to find enemies because enable resets Home, and
scans rejected anything beyond `max_pursuit` from the *original* home — so a
spider already in the field went blind. Fix: near home, enforce max_pursuit from
home; once deployed (>64 tiles from home), accept any enemy within search_radius.

## Post-combat linger

`sh-post-combat-linger-ticks` (default 1800) delays RETURNING so hunters clear
camps instead of snapping home the instant the last biter dies.

## Shortcut icon

Custom `__SpidertronHunter__/graphics/shortcut/hunter-*.png` — RTS tool flipped
180° and amber-tinted so it is distinct from the vanilla remote shortcut.

## Tactical retreat (2026-07-21)

`sh-retreat-health-percent` (default 25, 0=off) forces RETURNING when combined
defense ratio drops below the threshold. `sh-retreat-include-shields` folds energy
shield equipment into that ratio. Retreat skips post-combat linger and enters
RESTOCKING at home so robots can repair / shields can refill.

## GUI anchor

Hunter toggle uses `relative_gui_position.right` (same column as Spidertron Patrols
schedule/camera) instead of `top`, which was floating above the whole screen.

## Shortcut toggle state

`toggleable = true` + `player.set_shortcut_toggled` synced from selection / enable
so the toolbar button highlights while Hunter AI is active on the current selection.

## Combat kiting (2026-07-21)

ATTACKING no longer uses `follow_target` (walked into spitters/acid). `combat.lua`
issues short direct autopilot hops at `sh-combat-range` with styles hold/strafe/
circle/flank, pauses to shoot, and rejects waypoints near `acid-splash-fire-*`.

