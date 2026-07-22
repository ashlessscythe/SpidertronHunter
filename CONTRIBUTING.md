# Contributing

Thanks for contributing to Spidertron Hunter.

## Development setup

1. Clone this repository.
2. Symlink or copy the repo into your Factorio `mods` folder as `SpidertronHunter` (folder name must match `info.json` `name`).
3. Launch Factorio 2.1 with the mod enabled.

Optional soft dependencies: Spidertron Patrols, Spidertron Enhancements, Space Age.

## Running tests

Pure Lua tests (no Factorio required):

```bash
lua tests/run.lua
```

CI runs the same suite via `.github/workflows/test.yml` on push/PR to `dev`.

## Packaging

Build a Mod Portal–ready ZIP:

```bash
./scripts/package_mod.sh dist
# → dist/SpidertronHunter_<version>.zip
```

The archive must contain a single top-level folder `SpidertronHunter_<version>/`.

## Release process

Maintainers: see [docs/releasing.md](docs/releasing.md).

## Coding standards

- Match existing Lua style in `scripts/` and `control.lua`.
- Prefer small, focused changes; keep UPS and multiplayer determinism in mind (see [docs/notes.md](docs/notes.md)).
- Avoid drive-by refactors unrelated to the change.
- Update locale strings in `locale/en/` when adding user-visible text.
- Add or extend pure Lua tests in `tests/` when logic can be covered without the game.

## Pull requests

- Target `dev` unless maintainers ask otherwise.
- Describe the problem and the fix; link issues when applicable.
- Keep PRs focused; include test notes (or why tests were not added).
- Do not bump `info.json` version or cut release tags unless asked.
