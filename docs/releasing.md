# Releasing Spidertron Hunter

Maintainer guide for publishing a new version.

## Steps

1. **Update `info.json` version** to the new semver (e.g. `0.2.0`).
2. **Update the changelog** in [`CHANGELOG.md`](../CHANGELOG.md) with user-facing notes for this version.
3. **Commit** the version bump and changelog (and any other release changes).
4. **Create a tag** matching the version: `git tag vX.Y.Z` (example: `git tag v0.2.0`).
5. **Push commits and the tag**:
   ```bash
   git push origin HEAD
   git push origin vX.Y.Z
   ```
6. **GitHub Actions** runs [`.github/workflows/release.yml`](../.github/workflows/release.yml): tests, builds the Mod Portal ZIP, and validates archive layout.
7. A **GitHub Release** is created automatically for the tag, with the ZIP attached and generated release notes.
8. **Upload the generated ZIP** to the [Factorio Mod Portal](https://mods.factorio.com) (Mod → Releases → Upload).

## Package rules (do not change casually)

- ZIP name: `SpidertronHunter_<version>.zip`
- Archive must contain exactly one top-level folder: `SpidertronHunter_<version>/`
- Tag must match `info.json` version (`v0.1.9` ↔ `0.1.9`)
- No executables or shell scripts in the ZIP (Mod Portal rejects them); packaging strips the execute bit and excludes `*.sh` / binary extensions

## Manual / dry-run

You can run the **Release** workflow via `workflow_dispatch`. Set **Create a GitHub Release** as needed; dispatch without a matching tag produces a draft release when enabled.
