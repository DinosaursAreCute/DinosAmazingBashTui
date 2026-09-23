# Concept: a minimal `.dapk` of the DABT framework itself

| | |
|---|---|
| Status | Draft: concept, not implemented |
| Builds on | [dapk-packaging.md](dapk-packaging.md) (`lib/dapk/`), `lib/apps/tui_sync.sh`, `lib/apps/tui_install.sh`, `lib/apps/tui_update.sh`, `install.sh` |
| Constraint | Reuse the dapk logic as-is wherever possible; no new runtime dependencies |

## 1. Summary

Today DABT is installed and updated from a GitHub **source archive**: the whole repository (screenshots, tools, tests, assets, docs, about 40 MB) is downloaded, then `tui_sync.sh` copies the subset it wants (`lib bin share docs examples VERSION README.md CHANGELOG.md LICENSE`). Nothing is signed, and the user cannot see what an update brings before downloading it.

This concept builds the framework with the same `dabt build` that builds apps, producing `dabt-<version>-<build>.dapk` that contains **only what the framework needs to run**. The package is signed, carries a manifest of checksums, and ships News beside it. Installing and updating consume the verified package instead of the source archive. Almost everything is reuse; the new parts are small and listed in section 5.

## 2. Goals and non-goals

Goals
- G1. A `dapk` of the framework with the smallest file set that still runs every documented feature (runtime profile).
- G2. Built by the existing `dabt build`, using `dabt.pkg` in the repository root. No second build system.
- G3. Signed and verified with the existing sign/verify code. Updates fail closed.
- G4. `dabt update` shows the News of a new version before downloading it (`-news.txt`), and downloads only the small package.
- G5. The extracted package has the same shape `tui_sync.sh` already expects (a folder with `VERSION`, `lib/`, `share/`), so the three-way config sync, conflict handling and backups stay untouched.
- G6. A guard that proves the package is complete: nothing in it references a file that was left out.

Non-goals
- Replacing `tui_sync.sh` (its conflict handling for user-edited configs is still needed).
- Packaging apps that depend on the framework (that is [dapk-packaging.md](dapk-packaging.md)).
- Automatic background updates.

## 3. What "necessary" means

The runtime profile is an **allowlist**, so a new dev-only folder can never leak into the package by accident.

| Path | Ships | Why |
|---|---|---|
| `bin/dabt`, `bin/DABT_demo.sh` | yes | the command and `dabt --demo` (`bin/test.sh` is a stub: no) |
| `lib/` (incl. `lib/dapk/`) | yes | the framework, installer, updater, packaging |
| `share/defaults/`, `share/plugins/` | yes | copied to the config home by the installer |
| `share/demo/`, `share/tui.xsd` | yes | demo pages, markup schema |
| `share/ci/`, `share/release/` | yes | templates used by `dabt pkg ci init` and `dabt build` |
| `share/test_demo/` | no | test fixtures (verify against `tests/`; see 9) |
| `install.sh` | yes | entry point when installing from an extracted package |
| `VERSION`, `LICENSE` | yes | required by the sync (`valid_source`) and licensing |
| `docs/`, `examples/`, `README.md`, `CHANGELOG.md` | second package | see below |
| `tests/`, `tools/`, `assets/`, `screenshots/`, `.gitignore` | no | development only (`tools/` is most of the 40 MB) |

Sizes today: `lib` 804 KB, `share` 368 KB, `bin` 20 KB, against `docs` 632 KB, `examples` 64 KB.

**Docs and examples** ship as a separate optional package, `dabt-docs`, built from the same tree with a second config (`dabt build --config dabt-docs.pkg`). The runtime package stays small; users who want offline docs run `dabt app install`-style install of that package. (`CHANGELOG.md` is not shipped in the runtime package; its News bullets travel in `NEWS`.)

## 4. Reuse map

| Need | Reused from `lib/dapk/` | Change |
|---|---|---|
| Choose files | `collect.sh`: `include_paths` allowlist, `exclude`, `[[include]]` | none |
| Version and build number | `version.sh` (`VERSION`, CI tag, run number) | none |
| Checksums, Merkle dir hashes | `manifest.sh` | none |
| Deterministic tar.gz | `pack.sh` | none |
| Signing, trust store, verification | `sign.sh`, `verify.sh` | principal name `dabt` (already reserved: apps cannot use it) |
| Changelog closing, News, release notes | `changelog.sh`, `news.sh`, `notes.sh` | none |
| GitHub release | `publish.sh` | none |
| CI workflow | `ci.sh` and `share/ci/` | one extra job (section 7) |
| Dependencies (bash 5, tar, gzip, awk) | `deps.sh`, `[[dependency]]` | none: declared, checked, never auto-installed |
| Output, logging, progress bar | `ui.sh` | none |
| Config loading | `config.sh` (`dapk.config.load DIR FILE` already takes a file) | expose as `--config FILE` |

## 5. What is new (deliberately small)

1. **`dabt.pkg` in the repository root** (section 6).
2. **`kind` header** in `MANIFEST` (`kind=app` default, `kind=framework`). The build skips `.dabt.metadata` generation for `framework`, and `dabt app install` refuses a `kind=framework` package with a pointer to `dabt update`.
3. **`--config FILE`** for `dabt build`, so one tree yields `dabt` and `dabt-docs`.
4. **Updater source** in `tui_update.sh`: a `.dapk` channel next to `release` and `dev` (section 8). It verifies the package, then hands the extracted folder to the existing `tui.update.plan/apply`. `tui.sync.valid_source` accepts it unchanged.
5. **Bootstrap** in `install.sh` (section 8).
6. **Closure check** (`tools/check_closure.sh`, section 9) and the CI job that runs it.

## 6. `dabt.pkg` for the framework

```toml
name          = "dabt"
kind          = "framework"
entry         = "bin/dabt"
homepage      = "https://github.com/DinosaursAreCute/DinosAmazingBashTui"
changelog     = "CHANGELOG.md"
publish_repo  = "DinosaursAreCute/DinosAmazingBashTui"

# allowlist: only what runs
include_paths = ["bin", "lib", "share", "install.sh", "VERSION", "LICENSE"]
exclude       = ["test_demo", "test.sh", "*.log", ".tui_exec.log"]

[[dependency]]
name = "bash"
check = "test ${BASH_VERSINFO[0]:-0} -ge 5"
```
(`docs` build uses `dabt-docs.pkg` with `name = "dabt-docs"`, `include_paths = ["docs", "examples", "README.md", "CHANGELOG.md"]`.)

## 7. Release pipeline

Same as apps ([dapk-packaging.md](dapk-packaging.md), 13), plus one job:

| Trigger | Result |
|---|---|
| push to main | `dabt build --suffix dev`; closure check; artifact only |
| tag `v*` | build both packages, sign, closure check, `dabt pkg publish` (draft) |
| tag `v*-*` | same, pre-release |

The framework's own `dabt pkg release` bumps `VERSION` and closes the changelog section, exactly as for apps.

## 8. Install, update and bootstrap

**Update (`dabt update`):**
1. `tui.update.check` reads the latest release (already does) and finds the `.dapk` and `dabt-news.txt` assets.
2. News newer than the installed version is shown **before** any download (G4).
3. Download the `.dapk` and its `.sha256`; `dapk.verify.run` checks structure, signature (principal `dabt`, pinned in `trusted_signers`) and every checksum.
4. The extracted folder is passed to `tui.update.plan` / `apply` as today: three-way sync of config files, backups, conflict prompts, `install.meta`.
5. The old source-archive path stays as a fallback channel (`--dev`, or no `.dapk` asset on a release).

**Bootstrap (`curl | bash`):** `install.sh` downloads the latest `.dapk`, verifies it, and installs from the extracted folder. There is no earlier trust to lean on, so the signer fingerprint is **pinned in `install.sh` and printed in the README**; the user can compare it. After the first install it lives in `trusted_signers`, and every later update is checked against it.

**Key rotation:** a release may carry a new signer only when the package is signed by the current pinned key (a `signers` file inside the signed manifest tree lists the next key; the updater adds it after verification). A compromised key needs a manual step: the user re-pins from the README.

## 9. Completeness guard (G6)

A package that is too small is worse than one that is too big. Two checks run in CI and locally (`tools/check_closure.sh`):

1. **Static:** every `source`, `$TUI_ROOT/...` and `$TUI_DEFAULTS_DIR/...` reference in the packaged `lib/`, `bin/`, `share/` resolves to a file inside the package (or to a path created at runtime).
2. **Dynamic:** extract the package into a temp dir with an isolated `HOME`, then run `bin/dabt --version`, `dabt doctor`, an install into temp prefix/config, `dabt build` on a fixture app, and the demo's headless start. Any missing file fails the run.

The allowlist in `dabt.pkg` and the closure check are the two halves: the first says what should be there, the second proves nothing else is needed.

## 10. Compatibility and migration

- Existing installs keep working: the sync manifest logic is unchanged, so the first `.dapk` update is an ordinary update from the user's point of view.
- Files a release used to ship and no longer does (the docs move to `dabt-docs`) are handled by `tui_sync.sh`'s existing removed-file logic (`TUI_SYNC_REMOVE`), which only deletes files the user did not edit.
- Git checkouts: `dabt update` still refuses to overwrite the program folder of a checkout (`TUI_UPDATE_GIT`).

## 11. Testing

- Build test: the runtime package contains exactly the allowlist (list compared with a golden file), is reproducible, and is far smaller than the source archive.
- Closure tests: static and dynamic (section 9), plus a negative test that removing a needed file is caught.
- Updater tests (mocked network, as `tests/updater.bats` does): `.dapk` channel verifies and applies; a tampered package, unknown signer and a signer change are refused; News is shown before download; fallback to the archive channel works.
- Bootstrap test: pinned fingerprint mismatch aborts before anything is written.

## 12. Risks

| Risk | Mitigation |
|---|---|
| Allowlist misses a file a rarely used feature needs | dynamic closure test exercising every documented `dabt` command; new top-level paths must be added deliberately |
| Bootstrap trust rests on one pinned fingerprint | printed in README and `install.sh`, checked into git history; rotation rules in section 8 |
| Two release channels to maintain | the archive channel is fallback only and covered by the existing updater tests |
| `docs` leaving the runtime package surprises users | `dabt doctor` mentions `dabt-docs`; README explains it |

## 13. Alternatives considered

| Option | Rejected because |
|---|---|
| Keep the source archive, just filter files client-side | still downloads about 40 MB, still unsigned, no News preview |
| A separate build script for the framework | duplicates dapk logic that already does this |
| Denylist (`exclude` everything dev-only) | a new dev folder would leak into every release |
| Replace `tui_sync.sh` with the manifest | loses the three-way merge of user-edited configs |

## 14. Open questions

1. Ship `bin/DABT_demo.sh` and `share/demo/` in the runtime package (about 20 KB plus demo pages), or move them to `dabt-docs`? Recommendation: ship them; `dabt --demo` is a documented command.
2. Keep the source-archive updater channel permanently, or remove it after two releases? Recommendation: keep it as the fallback (`--dev` needs it anyway).
3. Key rotation as described in section 8, or a simpler "re-pin from README" only? Recommendation: start with re-pin only, add signed rotation when there is a second maintainer.
