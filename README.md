# Spidertron Hunter

Autonomous Spidertron AI for **Factorio 2.1**.

Enable Hunter AI on a spidertron and it will search for enemies, path around lakes, kite at range (with optional strafe/circle/flank), retreat when damaged, then return home to restock/repair before hunting again.

No manual patrol routes required.

## Requirements

- Factorio **2.1**
- Optional: [Spidertron Patrols](https://mods.factorio.com/mod/SpidertronPatrols), [Spidertron Enhancements](https://mods.factorio.com/mod/SpidertronEnhancements), Space Age

## How to use

1. Unlock spidertrons (and the Hunter toolbar shortcut).
2. Select one or more spidertrons with the remote (or open a spidertron GUI).
3. Toggle Hunter AI via:
   - Toolbar shortcut **Toggle Spidertron Hunter** (highlights when active)
   - Hotkey `Ctrl+Shift+H`
   - **Hunter AI** button on the right side of the spidertron GUI
4. Home is set to the spidertron's position when AI is enabled.

## Behavior

```
Patrol → Search → Move → Attack (kite) → linger / retreat → Return home → Restock → Patrol
```

- **Search:** bounded radius scans + shared enemy cache (not the whole map)
- **Move:** vanilla autopilot, lake-aware via `request_path` when needed
- **Attack:** preferred combat range; styles `hold` / `strafe` / `circle` / `flank`; acid puddle avoidance
- **Retreat:** configurable hull/shield % threshold forces a return home
- **Restock:** waits on logistics/repairs with a hard timeout (never stuck forever)

## Settings

All important options are **runtime-global** (Map settings → Mod settings):

| Setting | Purpose |
|---------|---------|
| Search radius / max pursuit | How far to look / how far from home to chase |
| Scan interval / budget | UPS-facing scan throttles |
| Return home + post-combat linger | Clear an area before heading home |
| Tactical retreat health % + shields | Bail out before dying |
| Combat range / style / acid avoid | Kiting behavior |
| Restock / repair / max wait | Home logistics |

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

- Soft-compatible with Spidertron Patrols (refuses enable while a spider is on patrol when that data is available)
- Listens for Spidertron Enhancements `on_spidertron_replaced`
- Ignores Constructron / docked Space Spidertron names

## Install (dev)

Symlink or copy this folder into your Factorio `mods` directory as `SpidertronHunter`.

## License

MIT — see [LICENSE](LICENSE).

## Notes

Design and UPS decisions live in [docs/notes.md](docs/notes.md).
