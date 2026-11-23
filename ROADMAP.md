# Roadmap

Ideas and planned work for Spidertron Hunter. Nothing here is a commitment; items are roughly ordered by priority within each section. Completed work is recorded in `CHANGELOG.md`.

## Gameplay

- [ ] **Squads / formations**: squad leader, shared retreat, focus-fire. (`docs/notes.md` already keeps the FSM extensible for this.)
- [ ] **Threat awareness**: judge nests by worms, spawner count and evolution tier; skip or retreat from nests the hunter can't beat.
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
