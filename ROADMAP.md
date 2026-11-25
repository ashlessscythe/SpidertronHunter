# Roadmap

Ideas and planned work for Spidertron Hunter. Nothing here is a commitment; items are roughly ordered by priority within each section. Completed work is recorded in `CHANGELOG.md`.

## Next up

Suggested order (2026-11-23):

1. [x] **"Nearest" mode fallback**: when the nearest nest is too dangerous, fall back to the next safe target instead of idling.
2. [x] **50+ hunter UPS stress test**: check the per-tick budgets hold before building squads.
3. [ ] **Ammo and fuel logic**: low fuel return, per-weapon ammo, "minimum loadout" setting.
4. [ ] **Mid-fight retreat** from a nest that turns out worse than judged.
5. [ ] **Squads / formations**, then **guard zones**.
6. [ ] **In-game stuck-recovery tests**, then restock / scout / migration / save-load tests.
7. [ ] **Multiplayer and Space Age** compatibility checks.
8. [ ] README troubleshooting section and locale key check.

Details for each item are in the sections below.

## Gameplay

- [ ] **Squads / formations**: squad leader, shared retreat, focus-fire. (`docs/notes.md` already keeps the FSM extensible for this.)
- [x] **Threat awareness**: skip nests whose worm/spawner danger exceeds the hunter's health (see `scripts/threat.lua`). Follow-ups: weigh weapons and ammo type, retreat mid-fight from a nest that turns out worse than judged, and in "nearest" mode fall back to the next-nearest safe target instead of idling.
- [x] **Laser-aware combat range**: the "Close in with lasers" setting (off by default) makes hunters with personal laser defense fight at 12 tiles. Follow-up: pick the range per weapon loadout.
- [ ] **Ammo and fuel logic**: return home on low fuel or low ammo per weapon type; "minimum loadout" setting.
- [ ] **Support roles**: medic/repair follower; pollution-source clearing.
- [ ] **Hunter patrol routes / guard zones**: radius-limited hunting instead of only a home point.
- [x] **Alerts**: notify on retreat, stuck, or death (custom alerts + map ping). Possible follow-ups: per-player setting, alert on scout failure.

## Quality and performance

- [x] **Split `scripts/ai.lua`** into orchestration, state handlers and shared helpers.
- [ ] **Pathfinding robustness** (queue starvation fixed; unit, lake and U-shaped bay scenario tests added; still to do): in-game stuck-recovery scenarios.
- [ ] **Multiplayer** (per-player fleet manager window position fixed; still to do): test multiple forces/surfaces and `gui.lua` state.
- [ ] **Compatibility**: Space Age planets and platforms (gravity, enemies on Gleba/Fulgora); extend the denylist for other spidertron mods.

## Testing

- [ ] Restocking, Patrols/Enhancements integration, Scout algorithms (lawnmower, spiral), migrations, save/load persistence.
- [ ] Stress test with 50+ hunters, recording UPS.

## Housekeeping

- [ ] README troubleshooting section (stuck hunters, debug mode).
- [ ] Locale key check for new strings.
