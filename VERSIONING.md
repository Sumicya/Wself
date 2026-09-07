# Versioning

WCX does not use semantic versioning. The module is distributed as CI-built artifacts.

## Current (explicit baseline)

The current checkout uses an **explicit baseline** because the repository was
snapshot-flattened (single/historical commit), so a git-derived auto version
would regress on such checkouts.

| Field         | Source                                                                        | Example |
|---------------|-------------------------------------------------------------------------------|---------|
| `versionCode` | Hardcoded in `app/build.gradle.kts` (`defaultConfig.versionCode`)             | `247`   |
| `versionName` | Hardcoded in `app/build.gradle.kts` (`defaultConfig.versionName`)             | `v247`  |
| `COMMIT_HASH` | Computed at build time (`git rev-parse --short HEAD`)                         | `a123bff` |
| `TAG`         | Always `"WCX"`                                                               | `WCX`   |
| `BUILD_TIMESTAMP` | `System.currentTimeMillis()` at build time                                 | (epoch) |

These values are embedded in `BuildConfig` and must be manually bumped alongside
a release. `app/build.gradle.kts` intentionally removed the old
`getCommitCount()` / `versionBaseOffset` logic because it was unused and
inconsistent with the actual `versionCode`.

## Planned (auto version)

Once the repository is a normal, full-history git repo (or CI is configured to
inject the version), migrate to a deterministic git-derived scheme:

- `versionCode` = `(git rev-list --count HEAD) + baseOffset`
- `versionName` = `"v" + versionCode`

Do this in the same commit that restores full history or adds an explicit CI
`--versionCode` override.

## Release Model

- Rolling "CI" prerelease on GitHub Releases, overwritten per build.
- `stable-ci-N` tags are occasional manual checkpoints.
- `update.json` generated in CI mirrors the installed `versionCode` / `versionName`.
