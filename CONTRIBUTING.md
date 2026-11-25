# Contributing

Thanks for contributing to Spidertron Hunter.

## Development setup

1. Clone this repository.
2. Symlink or copy the repo into your Factorio `mods` folder as `SpidertronHunter` (folder name must match `info.json` `name`).
3. Launch Factorio **2.1** with the mod enabled.

Optional soft dependencies: Spidertron Patrols, Spidertron Enhancements, Space Age.

## Running tests

Pure Lua tests (no Factorio required):

```bash
lua tests/run.lua                    # everything
lua tests/run.lua --list             # print test names
lua tests/run.lua --run scanner      # only tests whose name contains "scanner" (repeatable, or bare args)
```

In-game tests ([factorio-test](https://github.com/GlassBricks/FactorioTest), headless Factorio 2.1 in Docker; needs Docker and a Factorio login, read from your local `player-data.json` or `FACTORIO_USERNAME` / `FACTORIO_TOKEN`):

```bash
scripts/run_factorio_tests.sh                                   # all non-visual tests
scripts/run_factorio_tests.sh run --mod-path . --tag-whitelist visual   # visual scenarios, fast
scripts/run_factorio_tests.sh --run "hunters, 10 nests" -v     # fleet stress tests (tag "stress"); -v shows the timing log
scripts/run_factorio_tests.sh --list                            # list test names (no Docker)
scripts/run_factorio_tests.sh --run "keeps away"                # only matching tests, visual ones too (Lua patterns, repeatable)
scripts/watch_factorio_tests.sh --run "falls back"              # watch just those in a real window
scripts/watch_factorio_tests.sh                                 # watch visual scenarios in a real window (local Factorio 2.1.24+)
```

Tests live in `tests/factorio/` and are registered in the `require("__factorio-test__/init")` call at the bottom of `control.lua`.

CI runs the pure Lua suite and the in-game tests (headless, needs repo secrets `FACTORIO_USERNAME` / `FACTORIO_TOKEN`) via `.github/workflows/test.yml` on push/PR to `dev`.

## Packaging

Build a Mod Portal–ready ZIP:

```bash
./scripts/package_mod.sh dist
# → dist/SpidertronHunter_<version>.zip
```

Packaging generates Factorio `changelog.txt` from `CHANGELOG.md` and includes it in the archive. The archive must contain a single top-level folder `SpidertronHunter_<version>/`.

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
