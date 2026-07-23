# Spidertron Hunter

Autonomous Spidertron AI for **Factorio 2.1**.

**[Mod Portal](https://mods.factorio.com/mod/SpidertronHunter)** · Factorio 2.1

Enable Hunter AI on a spidertron and it will search for enemies, path around lakes, kite at range (with optional strafe/circle/flank), retreat when damaged, then return home to restock/repair before hunting again.

No manual patrol routes required.

## Gallery

![Enable Hunter AI on multiple spidertrons](media/activate.gif)

*Multi-select activation — toggle Hunter AI on several spidertrons at once.*

![Combat style dropdown in the spidertron GUI](media/combat_style_gui.png)

*Per-spidertron combat style: Hold / Strafe / Circle / Flank.*

For the Mod Portal description, use absolute `raw.githubusercontent.com` URLs to the same files on the `public` branch.

## Requirements

- Factorio **2.1**
- Install: [Spidertron Hunter on the Mod Portal](https://mods.factorio.com/mod/SpidertronHunter)
- Optional: [Spidertron Patrols](https://mods.factorio.com/mod/SpidertronPatrols), [Spidertron Enhancements](https://mods.factorio.com/mod/SpidertronEnhancements), Space Age

## How to use

1. Unlock spidertrons (and the Hunter toolbar shortcut).
2. Select one or more spidertrons with the remote (or open a spidertron GUI).
3. Toggle Hunter AI via:
   - Toolbar shortcut **Toggle Spidertron Hunter** (highlights when the whole selection is active)
   - Hotkey `Ctrl+Shift+H`
   - **Hunter AI** button on the right side of the spidertron GUI
4. Home is set to the spidertron's position when AI is enabled.
5. Multi-select toggle: if any selected hunter is off → enable all; if all are on → disable all.
6. Per-spidertron combat style via the dropdown next to the enable button.

## Behavior

```
Patrol → Search → Move → Attack (kite) → linger / retreat → Return home → Restock → (optional re-engage) → Patrol
```

- **Search:** bounded radius scans + shared enemy cache (not the whole map)
- **Move:** vanilla autopilot, lake-aware via `request_path` when needed
- **Attack:** preferred combat range; styles `hold` / `strafe` / `circle` / `flank`; acid puddle avoidance
- **Retreat:** configurable hull/shield % threshold forces a return home
- **Re-engage:** optional; after retreat + restock, return to the retreat origin and hunt again (default off)
- **Linger:** after a fight clears, keep scanning locally briefly (default 15s) before returning home
- **Restock:** waits on logistics/repairs with a hard timeout (never stuck forever)
- **Persistence:** Hunter AI stays enabled through combat, return home, and restock — only an explicit disable turns it off
- **Debug:** `sh-debug-mode` shows short flying text over the spidertron for major state changes

## Settings

All options are **runtime-global** (Map settings → Mod settings). Setting IDs match the in-game names (`sh-*`). Ticks: 60 = 1 second.

| Setting | Default | What it does |
|---------|---------|--------------|
| Search radius (`sh-search-radius`) | `256` | How far from the spidertron (or home) to search for enemies. Range 32–2048. |
| Maximum pursuit distance (`sh-max-pursuit-distance`) | `512` | Maximum distance from home a spidertron may travel while hunting. Range 64–4096. |
| Scan interval (`sh-scan-interval`) | `60` (1s) | How often autonomous brains run, in ticks. Higher is cheaper. Range 10–600. |
| Scan budget per update (`sh-scan-budget`) | `4` | Maximum expensive scan operations per spidertron think. Range 1–32. |
| Return home after combat (`sh-return-home-after-combat`) | `true` | After an area is clear, eventually return to home before resuming patrol. |
| Post-combat linger (`sh-post-combat-linger-ticks`) | `900` (15s) | How long to keep hunting near the last fight before returning home. `0` = return immediately when clear. Range 0–36000. |
| Tactical retreat health % (`sh-retreat-health-percent`) | `25` | Abort the hunt and return home when hull (and optionally shields) drop below this percent. `0` disables tactical retreat. Range 0–100. |
| Tactical retreat includes shields (`sh-retreat-include-shields`) | `true` | When enabled, retreat uses combined hull + energy shield integrity. When disabled, only hull health is considered. |
| Re-engage after retreat (`sh-reengage-after-retreat`) | `false` | After a tactical retreat and restock/repair, return to the retreat coordinates and resume hunting. |
| Restock at home (`sh-restock-enabled`) | `true` | After returning home, wait for logistics to fulfill requests (with a timeout). |
| Wait for repair at home (`sh-repair-enabled`) | `true` | After returning home, wait for construction robots to repair (with a timeout). |
| Maximum restock wait (`sh-max-restock-ticks`) | `3600` (60s) | Never wait longer than this for restock/repair; resume patrol anyway. Range 60–36000. |
| Enemy prioritization (`sh-enemy-prioritization`) | `nearest` | How to choose among scan candidates: `nearest`, `spawners-first`, or `units-first`. |
| Maximum idle time (`sh-max-idle-time`) | `600` (10s) | If stuck in WAITING longer than this, resume patrol. Range 60–18000. |
| Spiders processed per think tick (`sh-spiders-per-think`) | `8` | Cap how many spidertrons update each think tick (UPS safety). Range 1–64. |
| Enemy cache TTL (`sh-enemy-cache-ttl`) | `18000` (5 min) | How long discovered enemies stay in the shared cache. Range 600–216000. |
| Combat range (`sh-combat-range`) | `22` | Preferred distance from enemies while attacking (tiles). Hunters kite instead of walking into melee. Range 8–64. |
| Combat movement style (`sh-combat-style`) | `strafe` | Default combat movement: `hold` (keep range on the radial line), `strafe` (side-step with pauses), `circle` (orbit), or `flank` (angled approach). Per-spidertron GUI can override. |
| Avoid acid puddles (`sh-avoid-acid`) | `true` | Steer combat waypoints away from acid splash fires and leave puddles urgently. |
| Combat move interval (`sh-combat-move-interval`) | `90` (1.5s) | Minimum ticks between voluntary combat reposition moves (strafe/circle/flank). Range 20–600. |
| Combat pause between moves (`sh-combat-pause-ticks`) | `45` (0.75s) | After each combat hop, pause this long to stand still and shoot before the next hop. Range 0–300. |
| Debug mode (`sh-debug-mode`) | `false` | Show flying text for state transitions and scan results. |

## Remote interface

```lua
/c remote.call("spidertron_hunter", "debug")
/c remote.call("spidertron_hunter", "reset")
/c remote.call("spidertron_hunter", "scan")
/c remote.call("spidertron_hunter", "enable", game.player.selected)
/c remote.call("spidertron_hunter", "disable", game.player.selected)
```

Alias: `SpidertronHunter` (same methods).

## Compatibility

Spidertron Hunter ([Mod Portal](https://mods.factorio.com/mod/SpidertronHunter)) is an independent project. It is not a fork of, and is not intended as a replacement for, [Spidertron Patrols](https://mods.factorio.com/mod/SpidertronPatrols) or [Spidertron Enhancements](https://mods.factorio.com/mod/SpidertronEnhancements).

Those mods are listed as optional dependencies. When they are installed, Spidertron Hunter enables optional compatibility features where appropriate (for example, forcing Spidertron Patrols to manual while Hunter AI is enabled and restoring automatic on disable when prior mode is known, and remapping AI state if a spidertron entity is replaced).

**0.1.11:** While Hunter AI is enabled, Patrols is switched to manual so the two mods do not fight over autopilot destinations. Disabling Hunter restores automatic only when the schedule was auto before (otherwise it stays manual).

## Development

This project is developed with AI-assisted tooling. All architecture, testing, and release decisions are reviewed before publication.

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, tests, packaging, and PR expectations. Maintainers: [docs/releasing.md](docs/releasing.md).

### Tests

```bash
lua tests/run.lua
```

### Packaging for Mod Portal

```bash
./scripts/package_mod.sh dist
# → dist/SpidertronHunter_<version>.zip
```

Upload the zip to [Spidertron Hunter on the Mod Portal](https://mods.factorio.com/mod/SpidertronHunter).

GitHub Actions:
- `.github/workflows/test.yml` — runs pure Lua tests on push/PR
- `.github/workflows/release.yml` — on `v*` tags (or manual dispatch), builds `SpidertronHunter_0.x.x.zip` and attaches it to a GitHub Release

## Install (dev)

Symlink or copy this folder into your Factorio `mods` directory as `SpidertronHunter`.

Players: install from the [Mod Portal](https://mods.factorio.com/mod/SpidertronHunter).

## License

MIT — see [LICENSE](LICENSE).

Third-party attributions for adapted code (where applicable) are listed in [NOTICE](NOTICE).

## Notes

- Design and UPS decisions: [docs/notes.md](docs/notes.md)
- User-facing history: [CHANGELOG.md](CHANGELOG.md)
