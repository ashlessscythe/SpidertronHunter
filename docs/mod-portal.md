# Mod Portal description (copy-paste)

Paste everything **below the horizontal rule** into the Factorio Mod Portal **Description** field.

Images point at `raw.githubusercontent.com` on the `public` branch (`media/` is repo-only and omitted from the release ZIP). After adding gallery assets, push them to `public` before updating the Portal description.

### Quick gallery URLs

```
https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/activate.gif
https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/combat_style_gui.png
https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/scout_paths.png
https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/fleet_manager.png
```

---

Autonomous Spidertron AI for **Factorio 2.0**.

**Hunter** mode searches for enemies, paths around lakes, kites at range, retreats when damaged, then returns home to restock/repair.

**Scout** mode explores and charts fog without engaging — keeps standoff from biters, feeds the shared enemy cache, then hunters can clean up.

**Fleet manager** (`Ctrl+Shift+M`) groups spidertrons on your surface for follow, remote, home, and AI controls.

## Gallery

![Enable Hunter AI on multiple spidertrons](https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/activate.gif)

*Multi-select activation — toggle Hunter AI on several spidertrons at once.*

![Combat style dropdown in the spidertron GUI](https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/combat_style_gui.png)

*Per-spidertron combat style: Hold / Strafe / Circle / Flank.*

![Scout explore paths around lakes and fog](https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/scout_paths.png)

*Scout mode — lake-aware paths charting fog while keeping standoff from biters.*

![Fleet manager group cards](https://raw.githubusercontent.com/ashlessscythe/SpidertronHunter/public/media/fleet_manager.png)

*Fleet manager — groups on the current surface with follow, remote, home, and AI controls.*

## How to use

1. Unlock spidertrons (and the Hunter toolbar shortcut).
2. Select one or more spidertrons with the remote (or open a spidertron GUI).
3. Set **Mode** on the spidertron GUI: **Off** / **Hunter** / **Scout**.
4. Or toggle Hunter via toolbar **Toggle Spidertron Hunter** / `Ctrl+Shift+H` (enables Off spiders as Hunter; does not convert Scouts).
5. Open **Hunter fleet** / `Ctrl+Shift+M` to manage groups on the current surface.
6. Home is set to the spidertron's position when AI is enabled.
7. Per-hunter combat style via the Style dropdown (Hunter mode only).

### Scout controls

1. Set Mode → **Scout**.
2. **Vanilla spidertron remote** click → set explore **focus** (clears waypoints; runs the map-setting algorithm around that point).
3. **Scout remote** (toolbar / `Alt+Shift+A`) click → **append waypoint**. Waypoints are visited in order (algorithm ignored until the queue is empty).
4. Map settings choose the algorithm: `frontier` (nearest fog), `lawnmower`, or `spiral`.

### Fleet manager

Each group card (grouped by entity label, or prototype name if unlabeled):

| Control | Action |
|---------|--------|
| Follow | Group follows you (AI pauses in place; still enabled) |
| Remote | Puts a spidertron remote in the cursor with that group selected |
| Home | Go home. **Ctrl-click** = set each spider's home to its **current** position |
| Show group | Remote-view camera to the group |
| Settings | Opens one spidertron's GUI (Mode / Style / home) |
| AI toggle | Enable Off as Hunter if any are off; disable if all are on (does not convert active Scouts) |
| Pin | Keep the window open while using remotes or spider GUIs |

## Behavior

### Hunter

```
Patrol → Search → Move → Attack (kite) → linger / retreat → Return home → Restock → (optional re-engage) → Patrol
```

- **Search:** bounded radius scans + shared enemy cache
- **Move:** vanilla autopilot, lake-aware via `request_path` when needed
- **Attack:** preferred combat range; styles `hold` / `strafe` / `circle` / `flank`; acid puddle avoidance
- **Retreat:** configurable hull/shield % threshold forces a return home
- **Re-engage:** optional; after retreat + restock, return to the retreat origin and hunt again (default off)
- **Linger:** after a fight clears, keep scanning locally briefly (default 15s) before returning home
- **Restock:** waits on logistics/repairs with a hard timeout

### Scout

```
Explore → Move (lake-aware) → chart / standoff → (limits or done) → Return home → Restock → resume or wait
```

- Never enters combat; requires empty ammo (and no personal laser defense)
- Charts fog; records nearby enemies into the shared cache
- If a scout zig-zags or loops, it is standoff-dodging locals — send Hunters to clear them

## Compatibility

Optional soft dependencies: [Spidertron Patrols](https://mods.factorio.com/mod/SpidertronPatrols), [Spidertron Enhancements](https://mods.factorio.com/mod/SpidertronEnhancements), Space Age.

While Hunter AI is enabled, Patrols is switched to manual so the two mods do not fight over autopilot. Disabling Hunter restores automatic only when the schedule was auto before.

## Links

- [GitHub](https://github.com/ashlessscythe/SpidertronHunter)
- [Changelog](https://github.com/ashlessscythe/SpidertronHunter/blob/public/CHANGELOG.md)
