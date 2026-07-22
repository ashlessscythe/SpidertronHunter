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

