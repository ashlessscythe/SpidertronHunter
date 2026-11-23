# Releasing Spidertron Hunter

Maintainer guide for publishing a new version.

## Before releasing: run the tests locally

CI only runs the pure Lua suite, so run the in-game tests yourself before tagging (requires Docker running; the Factorio login is read from your local `player-data.json`, or set `FACTORIO_USERNAME` / `FACTORIO_TOKEN`):

```bash
lua tests/run.lua                                                       # pure Lua
scripts/run_factorio_tests.sh                                           # in-game smoke tests (headless, Docker)
scripts/run_factorio_tests.sh run --mod-path . --tag-whitelist visual   # hunter scenarios incl. lake detour (headless, fast)
```

All three must pass. Optionally watch the scenarios in a real window with `scripts/watch_factorio_tests.sh` (local Factorio 2.1.24+). If a scenario fails, rerun it there with the window to see what the hunter did. See [CONTRIBUTING.md](../CONTRIBUTING.md#running-tests) for details.

## Steps

1. **Run the local tests** (section above).
2. **Update `info.json` version** to the new semver (e.g. `0.2.0`).
3. **Update the changelog** in [`CHANGELOG.md`](../CHANGELOG.md) with user-facing notes for this version. Packaging generates Factorio `changelog.txt` from this file and includes it in the ZIP.
4. **Commit** the version bump and changelog (and any other release changes).
5. **Create a tag** matching the version: `git tag vX.Y.Z` (example: `git tag v0.2.0`).
6. **Push commits and the tag**:
   ```bash
   git push origin HEAD
   git push origin vX.Y.Z
   ```
7. **GitHub Actions** runs [`.github/workflows/release.yml`](../.github/workflows/release.yml): tests, builds the Mod Portal ZIP, and validates archive layout.
8. A **GitHub Release** is created automatically for the tag, with the ZIP attached and generated release notes.
9. The **publish** job uploads the ZIP to the [Factorio Mod Portal](https://mods.factorio.com) automatically on tag pushes, using the `FACTORIO_MOD_API_KEY` repo secret (API key needs the *ModPortal: Upload Mods* usage). Manual fallback: Mod → Releases → Upload.
10. The **sync-public** job force-updates the `public` branch to the released commit (replaces `sync_public.sh`), then **portal-description** pushes [mod-portal.md](mod-portal.md) to the portal (gallery images load from `public` via `raw.githubusercontent.com`).

## Package rules (do not change casually)

- ZIP name: `SpidertronHunter_<version>.zip`
- Archive must contain exactly one top-level folder: `SpidertronHunter_<version>/`
- Tag must match `info.json` version (`v0.1.9` ↔ `0.1.9`)
- No executables or scripts in the ZIP (Mod Portal rejects them); packaging strips the execute bit and excludes `*.sh` / `*.ps1` / `*.py` / `*.exe` / `*.bat` and similar
- Gallery assets under `media/` are repo-only (README / Mod Portal description) and are omitted from the ZIP

## Manual / dry-run

You can run the **Release** workflow via `workflow_dispatch`. Set **Create a GitHub Release** as needed; dispatch without a matching tag produces a draft release when enabled.
