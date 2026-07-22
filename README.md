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
   - Toolbar shortcut **Toggle Spidertron Hunter** (highlights when the whole selection is active)
   - Hotkey `Ctrl+Shift+H`
   - **Hunter AI** button on the right side of the spidertron GUI
4. Home is set to the spidertron's position when AI is enabled.
5. Multi-select toggle: if any selected hunter is off → enable all; if all are on → disable all.
6. Per-spidertron combat style via the dropdown next to the enable button.

## Behavior

```
Patrol → Search → Move → Attack (kite) → linger / retreat → Return home → Restock → Patrol
```

- **Search:** bounded radius scans + shared enemy cache (not the whole map)
- **Move:** vanilla autopilot, lake-aware via `request_path` when needed
- **Attack:** preferred combat range; styles `hold` / `strafe` / `circle` / `flank`; acid puddle avoidance
- **Retreat:** configurable hull/shield % threshold forces a return home
- **Linger:** after a fight clears, keep scanning locally briefly (default 15s) before returning home
- **Restock:** waits on logistics/repairs with a hard timeout (never stuck forever)
- **Persistence:** Hunter AI stays enabled through combat, return home, and restock — only an explicit disable turns it off
- **Debug:** `sh-debug-mode` shows short flying text over the spidertron for major state changes

## Settings

All important options are **runtime-global** (Map settings → Mod settings):

| Setting | Purpose |
|---------|---------|
| Search radius / max pursuit | How far to look / how far from home to chase |
| Scan interval / budget | UPS-facing scan throttles |
| Return home + post-combat linger | Clear an area before heading home (default linger 15s) |
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

Spidertron Hunter is an independent project. It is not a fork of, and is not intended as a replacement for, [Spidertron Patrols](https://mods.factorio.com/mod/SpidertronPatrols) or [Spidertron Enhancements](https://mods.factorio.com/mod/SpidertronEnhancements).

Those mods are listed as optional dependencies. When they are installed, Spidertron Hunter enables optional compatibility features where appropriate (for example, avoiding control conflicts with active patrols, and remapping AI state if a spidertron entity is replaced).

Hunter AI and manual patrol schedules are separate control modes; do not run both on the same spidertron.

## Development

This project is developed with AI-assisted tooling. All architecture, testing, and release decisions are reviewed before publication.

### Tests

```bash
lua tests/run.lua
```

### Packaging for Mod Portal

```bash
./scripts/package_mod.sh dist
# → dist/SpidertronHunter_<version>.zip
```

GitHub Actions:
- `.github/workflows/test.yml` — runs pure Lua tests on push/PR
- `.github/workflows/release.yml` — on `v*` tags (or manual dispatch), builds `SpidertronHunter_0.x.x.zip` and attaches it to a GitHub Release ready for Mod Portal upload

Tag example: bump `info.json` version, commit, then `git tag v0.1.9 && git push origin v0.1.9`.

## Install (dev)

Symlink or copy this folder into your Factorio `mods` directory as `SpidertronHunter`.

## License

MIT — see [LICENSE](LICENSE).

Third-party attributions for adapted code (where applicable) are listed in [NOTICE](NOTICE).

## Notes

Design and UPS decisions live in [docs/notes.md](docs/notes.md).
