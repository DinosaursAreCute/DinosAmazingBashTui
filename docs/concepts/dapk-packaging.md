# Concept: `.dapk` packaging, signing, releases and dependencies

| | |
|---|---|
| Status | Draft: concept, not implemented |
| Scope | `bin/dabt` subcommands, the new `lib/dapk/` module (section 14), `share/ci/`, `share/release/` |
| Constraint | Pure bash + POSIX utils + awk. No new runtime dependencies |
| Related | `lib/apps/tui_sync.sh` (three-way sync), `lib/apps/tui_install.sh`, `lib/apps/tui_update.sh`, `install.sh`, `lib/markup/tui_cache.sh` (progress palette) |

## 1. Summary

Developers building a D.A.B.T application need a reproducible way to turn their project into one distributable, verifiable file, publish it, and let end users preview what an update brings before applying it.

This concept introduces:

- **`.dapk`**, the DABT application package: a deterministic gzip tar whose first member is a signed `MANIFEST` carrying per-entry checksums, the app descriptor and its dependencies.
- **`dabt build`** to produce it, plus `verify`, `info`, `install`, `news`, `release`, `notes`, `publish`, `dep`, `include` and `ci init`.
- **`dabt.pkg`**, a TOML build configuration, including `[[include]]` and `[[dependency]]` tables.
- **Changelog handling** (`## [Unreleased]` rewrite, `### News` extraction) and **release-note templates**.
- **Ed25519 signatures** via `ssh-keygen -Y`, embedded in the package.
- **GitHub release publishing** as draft, prerelease or full release.
- **CI templates** (GitHub Actions, GitLab CI) that a project can drop in.
- A **consistent CLI experience**: `install.sh`-style steps, the cache-spinner color palette, CI-aware output, and full logs.

## 2. Goals and non-goals

### Goals
- G1. One command produces a reproducible, signed, self-verifying package.
- G2. The manifest lists a checksum for every top-level file and directory of the package.
- G3. Versions and build numbers are derived, never hand-edited per build, in CI and locally.
- G4. Users can read "what's new" for an update without running or downloading it.
- G5. Publishing to GitHub is one command, safe by default (draft).
- G6. Dependencies on system packages are declared, checked, and installed only with user consent.
- G7. No new dependencies beyond tools already assumed by DABT, plus `ssh-keygen` for signing.

### Non-goals
- Auto-update daemons or background checking.
- Dependency resolution between `.dapk` packages (only system packages; see 11).
- Hosting or a package registry. Distribution is via GitHub releases or any HTTPS URL.
- Windows support beyond what bash provides.
- Sandboxing installed apps.

## 3. Terminology

| Term | Meaning |
|---|---|
| Package / `.dapk` | The distributable build artifact |
| `dabt.pkg` | Developer-authored build configuration (TOML) |
| Descriptor | The header section of `MANIFEST`. There is no separate descriptor file. |
| Top-level entry | A direct child of the package root (file or directory) |
| Full version | `<semver>[-<suffix>]-<build>`, e.g. `1.4.2-dev-57` |
| News | Bullets from a changelog's `### News` section |
| Signer | The Ed25519 key that signed `MANIFEST` |

## 4. Package format

### 4.1 Identity
- Extension: `.dapk`, held in one constant, `DABT_PKG_EXT`.
- Filename: `<name>-<version>-<build>.dapk`, e.g. `myapp-1.4.2-57.dapk`.
- Container: gzip-compressed POSIX tar with a single root directory `<name>-<version>-<build>/`.
- A file is a valid `.dapk` only if its first tar member is `<root>/MANIFEST` and begins with `# DABT-MANIFEST 1`. Plain tarballs are rejected.

### 4.2 Layout
```
myapp-1.4.2-57/
  MANIFEST        first member: descriptor + checksums
  MANIFEST.sig    ssh-keygen signature over MANIFEST
  NEWS            extracted News bullets (only if a changelog is configured)
  CHANGELOG.md    with the Unreleased header rewritten
  bin/ lib/ config/ ...   project content plus [[include]] targets
```
Because `MANIFEST` is first, `dabt info` reads it with `tar -xzOf pkg '*/MANIFEST'` and stops early, without unpacking the archive.

### 4.3 MANIFEST specification
Line-oriented UTF-8, `\n` line endings, parseable with bash and awk.

```
# DABT-MANIFEST 1
name=myapp
version=1.4.2-dev
build=57
commit=abc1234
built=2026-09-21T12:00:00Z
entry=bin/myapp.sh
requires_dabt=>=0.9
homepage=https://github.com/me/myapp
news_url=https://github.com/me/myapp/releases/latest/download/myapp-news.txt
signer=SHA256:<fingerprint>
dep.1.name=ripgrep
dep.1.optional=false
dep.1.check=command -v rg
dep.1.apt=ripgrep
dep.1.pacman=ripgrep
---
d  <sha256>  -     -    bin
d  <sha256>  -     -    lib
f  <sha256>  1204  644  README.md
```

- Header: `key=value`, first `=` splits, no quoting. Unknown keys are preserved and ignored by older readers.
- `---` separates header from entries.
- Entry line: `<type> <sha256> <size> <mode> <path>`, whitespace-separated, `path` last. `type` is `f` or `d`. Directories carry `-` for size and mode.
- Entries are the **top-level** entries only, sorted with `LC_ALL=C`. `MANIFEST` and `MANIFEST.sig` are excluded because they cannot describe themselves.
- Modes are normalized: files `644`, or `755` if any exec bit is set. Directories are not recorded.

### 4.4 Checksum algorithm
- File hash: `sha256` of the content.
- Directory hash (Merkle): `sha256` of the concatenation, in `LC_ALL=C` name order, of one line per direct child: `<type> <hash> <mode> <name>\n`. A child directory contributes its own directory hash and `-` for mode.
- A change to any file at any depth changes the hash of its top-level ancestor.
- Hash tool: `sha256sum`, falling back to `shasum -a 256`. Hashing is a single pass; the file count is known up front for progress reporting.

### 4.5 Reproducibility
Building the same tree with the same inputs yields a byte-identical `.dapk`:
- Members are added from an explicit list: `MANIFEST`, `MANIFEST.sig`, then everything else in `LC_ALL=C` order.
- `--owner=0 --group=0 --numeric-owner`, mtime fixed to `SOURCE_DATE_EPOCH` (default: the commit date of `HEAD`, else the build date), `gzip -n`.
- `built=` in the header is the only non-deterministic field, and it derives from the same epoch.

### 4.6 Sidecars (in `dist/`)
| File | Purpose |
|---|---|
| `<pkg>.dapk.sha256` | Download integrity only |
| `<name>-news.txt` | Preview without downloading the package |
| `RELEASE_NOTES.md` | Rendered release notes |
| `build.log` | Full build log (section 12) |

## 5. Configuration: `dabt.pkg`

### 5.1 Format
A strict TOML subset, so every accepted file is valid TOML and works with editors and linters. `lib/dapk/toml.sh` (awk) supports: comments, bare and quoted keys, strings, booleans, integers, string arrays, `[table]` and `[[array-of-tables]]`. Anything else is an error with a line number. The parser emits flat lines (`key=value`, `include.N.field=value`, `dependency.N.field=value`), so the rest of the build code never handles TOML.

Alternatives were considered in section 15.

### 5.2 Example
```toml
name             = "myapp"
entry            = "bin/myapp.sh"
requires_dabt    = ">=0.9"
homepage         = "https://github.com/me/myapp"
changelog        = "CHANGELOG.md"
suffix           = ""                       # dev | prerelease | rc.N; CLI flag overrides
release_template = ".dabt/release.tpl"
sign_key         = "~/.ssh/dabt_ed25519"
publish_repo     = "me/myapp"               # default: derived from git remote

include_paths    = ["bin", "lib", "config", "share"]
exclude          = ["*.log", ".git", "tests"]

[[include]]
type   = "file"
source = "LICENSE"
target = "docs/LICENSE"

[[include]]
type      = "directory"
source    = "shared-assets"
target    = "share/assets"
recursive = true
exclude   = ["*.tmp"]
optional  = true

[[dependency]]
name        = "ripgrep"
check       = "command -v rg"
version_cmd = "rg --version"
min_version = "13.0"
apt         = "ripgrep"
pacman      = "ripgrep"
```

Defaults without a `dabt.pkg`: `name` = directory name, everything except dotfiles included.

### 5.3 `[[include]]`
| Field | Required | Meaning |
|---|---|---|
| `type` | yes | `file` or `directory` (aliases `f`, `d`) |
| `source` | yes | Path relative to the project root |
| `target` | yes | Path inside the package. A file target ending in `/` keeps the source basename. |
| `recursive` | no (directory) | `false` (default): top-level files only. `true`: descend. |
| `exclude` | no | Glob list for this entry |
| `optional` | no | `true`: skip a missing source. Default `false`: error. |
| `overwrite` | no | Permit replacing a target produced earlier. Default `false`: collision is an error. |
| `follow_symlinks` | no | Default `false` |

Rules:
- `source` must resolve inside the project root. `..` and absolute paths are rejected unless `--allow-external`, and `optional` does not bypass this.
- `target` must be relative and contain no `..`.
- Symlinks are rejected (build error) unless `follow_symlinks = true`, in which case they are dereferenced.
- A directory include matching no files runs `mkdir -p` on the target and emits a warning (`include '<src>' matched no files`). `--strict` promotes it to an error.
- Resolution order: base tree, then `[[include]]` entries in file order, then CLI entries.

CLI equivalents (entry-scoped flags apply to the most recent `-f`/`-d`):
```
dabt build -f -s LICENSE -t docs/LICENSE -d -s shared-assets -t share/assets -r
dabt include add|list|rm       # edits [[include]] tables in dabt.pkg
dabt build --plan              # print resolved source -> target list; write nothing
```

### 5.4 `[[dependency]]`
| Field | Meaning |
|---|---|
| `name` | Label, and default `check` target |
| `check` | Shell test; exit 0 = present. Default `command -v <name>` |
| `version_cmd`, `min_version` | Optional version gate, compared with `sort -V` |
| `optional` | Reported only; never blocks or fails |
| `apt` `pacman` `dnf` `zypper` `apk` `brew` | Package name per package manager |
| `install` | Fallback command when no mapping matches (discouraged, see 10.4) |

`dabt build` validates the schema and warns for a dependency with neither a mapping nor `install`. Dependencies are copied into the `MANIFEST` header as `dep.N.*` and are therefore covered by the signature. `dabt dep add|list|rm` manages the tables.

## 6. Versioning

- Version source: `VERSION` (semver). In CI, a tag `vX.Y.Z[-suffix]` overrides it.
- Suffix: `--suffix dev|prerelease|rc.N` or `suffix=` in `dabt.pkg`, yielding `1.4.2-dev`. Ordering follows semver prerelease rules.
- Build number, first match wins: `DABT_BUILD_NUMBER`, `GITHUB_RUN_NUMBER`, `CI_PIPELINE_IID`, `git rev-list --count HEAD`, else `0`.
- Full version: `1.4.2-dev-57`. Per semver, build metadata does not affect precedence.
- `dabt version` prints the resolved version. `dabt version bump patch|minor|major` edits `VERSION`.

## 7. Changelog and News

### 7.1 Format
Keep-a-Changelog conventions:
```markdown
## [Unreleased]
### News
- New file explorer pane
- Mouse drag now works in tabs
  (indented continuation lines extend the previous bullet)
### Fixed
- ...

## [1.4.1] - 2026-08-30
### News
- ...
```
- A `### News` section runs until the next heading of level 1-3.
- A **bullet** is a line starting with `- `. Indented lines that follow continue it. Other lines are ignored.

### 7.2 Build behavior (never mutates the working tree)
In the packaged copy of the changelog, `## [Unreleased]` becomes `## [<version>] - <date>` and a fresh empty `## [Unreleased]` is inserted above it. For suffixed builds the header is `## [<version>-<build>] - <date>`.

The section for the built version yields:
- `NEWS` inside the package, one `version<TAB>text` line per bullet.
- `<name>-news.txt` in `dist/`, with the same content.

### 7.3 `dabt release [patch|minor|major]` (mutates the working tree)
Preconditions: clean tree, non-empty Unreleased section. Steps: bump `VERSION`, apply the header rewrite on disk, commit `Release v<ver>`, tag `v<ver>`. It never pushes unless `--push` is given. Suffixed builds never consume Unreleased on disk.

### 7.4 Loader (`lib/dapk/news.sh`)
- `dapk.news.load <file|url>` fills `DAPK_NEWS_VERSIONS[]` and `DAPK_NEWS_ITEMS[]`.
- `dapk.news.since <installed-version>` filters to newer versions.
- `dabt news <pkg|file|url>` prints the bullets.
- The update path fetches only `news_url` first, so users see the changes before anything is downloaded or applied.
- A `<news src=... since=.../>` markup tag renders the list into a pane.

## 8. Release notes templates

- Location: `release_template` in `dabt.pkg`, default `.dabt/release.tpl`. `share/release/default.tpl` ships as the fallback.
- Engine: awk, three constructs only:
  - `{{var}}` substitution
  - `{{#if var}} ... {{/if}}`
  - `{{section:Name}}` (any changelog section of the built version)
- Variables: `name`, `version`, `build`, `date`, `commit`, `news`, `compare_url`, `checksums` (top-level manifest entries).
- Unknown variables are a build error (typos must not silently produce empty notes). Output goes to `dist/RELEASE_NOTES.md`; `dabt notes` renders it without building.

```
# {{name}} {{version}}
{{#if news}}
## What's new
{{news}}
{{/if}}
{{section:Fixed}}

**Full changelog:** {{compare_url}}
```

## 9. Publishing to GitHub

`dabt publish [--draft | --prerelease | --release]`

- Transport: `curl` against the GitHub REST API with `GITHUB_TOKEN`. If `gh` is present it may be used instead. No hard dependency on `gh`.
- Mode:
  - Default is `--draft`.
  - A suffixed version forces `--prerelease`, and `--release` is refused for it.
  - `dabt publish --release` on an existing draft promotes it (`PATCH draft=false`).
- Steps:
  1. Locate an existing release for `v<version>`. Draft releases are not returned by `GET /releases/tags/{tag}`, so list releases and match `tag_name`. This makes reruns idempotent.
  2. Create or update it with the rendered `RELEASE_NOTES.md` as body.
  3. Upload the `.dapk`, `.dapk.sha256` and `-news.txt`. Existing assets of the same name are replaced.
- The repository is `publish_repo`, else derived from the `git remote`.
- The token is read from the environment only, is never logged, and is masked in any logged command or header.

## 10. Signing, trust and verification

### 10.1 Choice
Ed25519 via `ssh-keygen -Y sign|verify`, namespace `dabt-pkg`.

Rationale: OpenSSH is near-universal, needs no GPG keyring or web of trust, has a stable signature format, and verifies against a plain `allowed_signers` file. It adds no dependency beyond OpenSSH.

### 10.2 What is signed
`MANIFEST` only, producing `MANIFEST.sig` inside the package. The manifest pins every top-level hash, so a valid signature covers the whole package, and a `.dapk` verifies with no external files. The `.sha256` sidecar is transport integrity only and is not trusted for authenticity.

### 10.3 Verification (`dabt verify`, and the first step of `dabt install`)
1. Structure check: first member is `MANIFEST` with the expected magic.
2. Signature check of `MANIFEST` against `$TUI_HOME/trusted_signers`.
3. Recompute every top-level hash and compare with the manifest, and reject members not listed.
4. Any failure is fatal. There is no "install anyway".

### 10.4 Trust and privilege model
- Trust store: `$TUI_HOME/trusted_signers` (`allowed_signers` format), pinned per app name.
- First install of an unknown signer: explicit prompt showing the fingerprint, accepted only with an interactive yes or `--trust-key`. `--yes` never trusts a key.
- A signer change for an already-installed app fails hard.
- CI signing keys come from a secret, are written to a mode-600 temp file, and are removed after the build.
- `sudo` is used only for dependency installation, only when not already root, and is always shown in the plan. dabt never handles a password.
- Custom `install` commands are the most dangerous surface: printed verbatim, flagged `custom command`, never batched, and always confirmed individually unless `--allow-custom-install` is passed. `--yes` does not cover them.

## 11. Installation and dependencies

### 11.1 `dabt install <pkg.dapk|url>`
Order of operations (nothing is written before step 5):
1. Fetch, if a URL. Check `.sha256` if present.
2. `verify` (section 10.3).
3. Show descriptor and News.
4. Dependency step (11.2).
5. Extract to `$TUI_HOME/apps/<name>/` (override with `--install-path`) and copy `MANIFEST` alongside.
6. Register the app, and write a log (section 12.3).

`dabt install --plan` prints the verify result, dependency plan and commands, executing nothing.

### 11.2 Dependency flags

| Flag | Effect |
|---|---|
| *(none)* | Check; if required dependencies are missing, show the plan and ask `Install missing dependencies? [y/N]` |
| `--install-dependencies` | Same plan; prompt defaults to yes (`[Y/n]`); without a TTY requires `--yes` or fails |
| `--yes` | Answers the dependency prompt with yes only |
| `--no-deps` | Run checks and warn; no prompt, no install; app is installed and marked `deps=unmet` |
| `--require-deps` | Missing required dependencies abort the install (exit 1, nothing written) |

| Invocation | Condition | Result |
|---|---|---|
| default, TTY | answer yes | dependencies installed, then app |
| default, TTY | answer no | warn; app installed; `deps=unmet` |
| default, no TTY | n/a | behaves as `--no-deps` |
| `--require-deps` | yes and install succeeds | dependencies installed, then app |
| `--require-deps` | no, or an install fails | exit 1, nothing installed |
| `--require-deps`, no TTY, no `--yes` | n/a | exit 1 (prompt cannot be answered) |
| `--no-deps` | n/a | warn; app installed; `deps=unmet` |
| `--yes` alone | n/a | default flow with the prompt auto-answered yes |

Rules:
- `--no-deps` combined with `--install-dependencies` or `--require-deps` is a usage error (exit 2).
- Optional dependencies appear in the plan and prompt but never cause failure, even under `--require-deps`.
- One batched command per package manager is shown and run, for example `sudo pacman -S --needed ripgrep fzf`.
- Package manager detection: first of `pacman`, `apt-get`, `dnf`, `zypper`, `apk`, `brew` found with `command -v`, tie-broken by `/etc/os-release`. `--pm <name>` overrides.
- After installation every `check` is re-run. Failures are summarized and the exit code is non-zero.
- `deps=unmet` is written into the installed copy of `MANIFEST`, cleared by `dabt deps <app>` when all checks pass, and reported when an app with unmet dependencies is launched.

## 12. CLI reference and user experience

### 12.1 Commands
| Command | Purpose |
|---|---|
| `dabt build [dir]` | Build `dist/<pkg>.dapk` and sidecars |
| `dabt verify <pkg>` | Signature and hash verification |
| `dabt info <pkg>` | Descriptor, dependencies, News, signer |
| `dabt install <pkg\|url>` | Install (section 11) |
| `dabt deps [app\|pkg]` | Check dependencies |
| `dabt news <pkg\|file\|url>` | Print News bullets |
| `dabt version [bump ...]` | Show or bump version |
| `dabt release [bump]` | Cut a release commit and tag |
| `dabt notes` | Render release notes |
| `dabt publish [mode]` | GitHub release |
| `dabt include ...`, `dabt dep ...` | Edit `dabt.pkg` tables |
| `dabt ci init github\|gitlab` | Copy a CI template into the project |

### 12.2 Presentation
- Layout, colors and helpers match `install.sh`: `[n/N]` step headers (bold blue), `✓` (green), `!` (yellow), `✗` (red), dim key-value lines. They are implemented in `lib/dapk/ui.sh` (`dapk.ui.step`, `ok`, `warn`, `err`, `kv`), which has no dependency on `tui.sh` state. `install.sh` adopts it later (14.3).
- Human output goes to stderr. Machine-readable results (artifact path from `build`, data from `info` and `news`) go to stdout, so `path=$(dabt build)` works. `install.sh` keeps its current stream behavior.
- Exit codes: `0` success, `1` failure, `2` usage error, `3` refused action (as in `install.sh`).
- Warnings are collected and repeated as a count and list at the end. `--strict` makes any warning exit 1.

### 12.3 Progress bar
Shown only when stdout is a TTY and no CI environment is detected:
```
DABT: (Hashing files)  ▕██████████████░░░░░░░░░░░░░░░░▏  47%
```
- Identical look to the cache spinner bar: 30 cells, `█` filled, `░` empty, `▕`/`▏` end caps. If the locale is not UTF-8 it falls back to `#`, `-`, `[`, `]`.
- One line redrawn with `\r\e[K`, repainted only when the integer percent changes, no forks per redraw.
- Colors reuse the cache spinner palette from `lib/markup/tui_cache.sh` (`tui.cache.warm_with_spinner`):

| Segment | Color | RGB | 256-color |
|---|---|---|---|
| 1 | pink | `255;140;191` | 212 |
| 2 | blue | `168;216;255` | 153 |
| 3 | yellow | `255;243;168` | 229 |
| 4 | red | `255;158;158` | 217 |

  Filled cells are colored by position along the bar. Empty cells are 238, brackets 245, label and percent 250. Truecolor when `COLORTERM` contains `truecolor` or `24bit`, else the 256-color values.
- The four letters of `DABT:` take the logo pastels. For steps with no measurable progress (upload, package-manager install, signing) the letters rotate every 400 ms and the bar is omitted.
- Work runs in the background with output to the log. The foreground polls with `read -t 0.2` on a fifo (the pattern used by the cache spinner), with no `sleep` forks. A step ends with `✓ <step>`.
- Below roughly 60 columns the bar degrades to the percent only.
- Progress units: files hashed / total, `tar` members written or read / counted beforehand, packages installed / total, assets uploaded / total.
- The palette and the bar renderer live in `lib/dapk/ui.sh` (`dapk.ui.bar PCT WIDTH`). `tui_cache.sh` keeps its own copy (refactor out of scope, D10).

### 12.4 CI behavior
- CI is detected when any of `CI`, `GITHUB_ACTIONS`, `GITLAB_CI`, `JENKINS_URL`, `BUILDKITE`, `TF_BUILD` is set, or stdout is not a TTY.
- In CI the bar is replaced by plain line steps (`[3/6] Hashing`, then `✓ 42 files`) with no `\r`. `--progress` and `--no-progress` override.
- On GitHub Actions, warnings and errors are also emitted as `::warning::` and `::error::` annotations and steps are wrapped in `::group::`.
- Colors: on for a TTY or `FORCE_COLOR`, off with `NO_COLOR`.

### 12.5 Logging
- A full plain-text log is always written, with timestamps and levels (`INFO`, `WARN`, `ERROR`, `DEBUG`): `dist/build.log` for builds, `$TUI_HOME/logs/install-<timestamp>.log` for installs, overridable with `--log FILE`.
- Console verbosity: `-v` adds debug detail (resolved source/target pairs, exact commands), `-q` prints only warnings and errors. The log is unaffected by `-q`.
- Secrets (signing keys, `GITHUB_TOKEN`, passwords) are never logged; commands are logged with tokens masked.

## 13. CI templates

Shipped in `share/ci/` (`github-actions.yml`, `gitlab-ci.yml`) and copied by `dabt ci init`.

| Trigger | Behavior |
|---|---|
| Push to main | `dabt build --suffix dev`; upload as CI artifact only; no publish |
| Tag `v*-*` | build, sign, verify, `dabt publish --prerelease` |
| Tag `v*` | build, sign, verify, `dabt publish --draft` |

The version comes from the tag or `VERSION`, and the build number from the CI run. The signing key comes from a CI secret (10.4).

## 14. Module structure and implementation plan

All packaging logic lives in its own module directory, `lib/dapk/`, separate from the existing flat `lib/tui_*.sh` files. Migrating the rest of `lib/` to this structure is a later, separate effort and is out of scope here. This module is built with that end state in mind, so its conventions can be reused as-is.

### 14.1 Layout
```
lib/dapk/
  dapk.sh         loader: sources the modules below in dependency order, defines DABT_PKG_EXT, guards double-sourcing
  ui.sh           steps, colors, progress bar, logging, CI detection (12.2 - 12.5)
  toml.sh         strict TOML subset parser (5.1)
  config.sh       loads dabt.pkg, applies defaults, validates
  version.sh      version and build-number resolution (6)
  changelog.sh    Unreleased rewrite, News extraction (7.1 - 7.3)
  news.sh         News loading and filtering (7.4)
  collect.sh      base tree and [[include]] resolution, plan output (5.3)
  manifest.sh     hashing, Merkle directory hashes, MANIFEST read and write (4.3, 4.4)
  pack.sh         deterministic tar and gzip, member counting (4.5)
  sign.sh         ssh-keygen sign, trust store (10)
  verify.sh       structure, signature and hash verification (10.3)
  deps.sh         dependency check, plan, install (5.4, 11.2)
  install.sh      install orchestration (11.1)
  notes.sh        release-note template engine (8)
  publish.sh      GitHub release client (9)
  ci.sh           CI template installation (13)
  cmd/            one file per subcommand: build, verify, info, install, deps, news, version, release, notes, publish, include, dep, ci
bin/dabt          thin dispatcher: sources lib/dapk/dapk.sh, maps `dabt <cmd>` to `dapk.cmd.<cmd>`
tests/dapk/       one bats file per module
```

### 14.2 Module rules
- **Single responsibility.** A module owns one concern from the list above. Cross-cutting behavior (output, logging) goes through `ui.sh`, not reimplemented per module.
- **Namespacing.** Public functions are `dapk.<module>.<name>` (for example `dapk.manifest.write`). Private helpers are `_dapk.<module>.<name>`. Public globals are `DAPK_<MODULE>_*`. This follows the existing `tui.*` / `_tui.*` convention, and the private-function invariant in CLAUDE.md applies unchanged: nothing outside a module calls its underscore functions or reads its private state.
- **Explicit interface.** Each module starts with a header comment listing its public functions, the globals it reads and writes, and the modules it depends on.
- **Acyclic dependencies.** The loader order in `dapk.sh` is the dependency order. `ui`, `toml` and `version` depend on no other module. `cmd/*` may depend on anything. No module depends on `cmd/*`.
- **No process control inside modules.** Modules `return` status codes and never call `exit`. Only the `cmd/` layer and `bin/dabt` translate results into exit codes (12.2).
- **Values out, chatter elsewhere.** A function that produces a value returns it through a named variable (nameref) or stdout. Human-facing messages go through `ui.sh` to stderr. Nothing mixes the two.
- **Standalone.** A module can be sourced by itself for tests, with no dependency on `tui.sh` state, matching the standalone rule for `terminal_renderer.sh`.
- **Thin commands.** `cmd/*` files only parse arguments, call module APIs and report results. Logic that a second command needs moves into a module.
- **Testable seams.** External effects (network, package manager, `ssh-keygen`, `sudo`) are isolated behind small functions in `publish.sh`, `deps.sh` and `sign.sh`, so tests replace them by mock executables on `PATH` or by overriding a function.

### 14.3 Touch points outside the module
- `install.sh` and `lib/apps/tui_update.sh` are unchanged in this effort. `ui.sh` exposes a stable interface (`dapk.ui.step`-style output, `dapk.ui.bar`) so `install.sh` can adopt it when the wider migration happens. Until then the two share the visual design, not code.
- App-facing wrappers (`tui.news.*` for apps, a `<news>` markup tag) are thin delegates to `dapk.news` and are added on the `tui` side only when needed.
- New non-code assets: `share/ci/*`, `share/release/default.tpl`, `docs/guide/packaging.md`.

### 14.4 Implementation order
Each step is shippable and has its own tests in `tests/dapk/`:
1. `dapk.sh`, `ui.sh`, `toml.sh`, `config.sh`
2. `manifest.sh`, `pack.sh`, `cmd/build`, then `sign.sh`, `verify.sh`
3. `collect.sh` (`[[include]]`), `version.sh`
4. `changelog.sh`, `news.sh`, `cmd/release`
5. `deps.sh`, `install.sh`
6. `notes.sh`, `publish.sh`
7. `ci.sh`, CI templates, docs

## 15. Alternatives considered

| Decision | Chosen | Rejected and why |
|---|---|---|
| Config format | TOML subset | YAML: indentation and anchors cannot be parsed safely in awk. JSON: no comments, awkward in awk. Key=value: no repeatable structured entries, not a recognized standard. |
| Signing | `ssh-keygen -Y` | GPG: keyring and trust-model complexity. minisign: extra dependency. Raw `openssl` Ed25519: no standard container or trust file. |
| Descriptor | Header of `MANIFEST` | Separate descriptor file: second source of truth to keep in sync and to sign. |
| Signature placement | Embedded `MANIFEST.sig` | Detached tarball signature: package no longer verifies on its own. |
| GitHub transport | `curl` REST | `gh` only: hard dependency. |
| Directory checksum | Merkle over children | Hash of a `tar` stream: not stable across tar implementations. |

## 16. Risks

| Risk | Mitigation |
|---|---|
| Non-GNU `tar` lacks `--sort`, `--mtime` | Explicit member list and fixed ordering; document `bsdtar` flags; detect and fail with a clear message if reproducibility cannot be guaranteed |
| Custom `install` commands execute arbitrary code | Signed manifest, verbatim display, never batched, individual confirmation (10.4) |
| `sudo` prompts inside a progress step | Run dependency installs in the foreground without the bar; the bar resumes afterwards |
| TOML subset diverges from real TOML | Reject unsupported syntax with line numbers, and test fixtures are validated against a real TOML parser during development |
| Signing key exposure in CI | Secret only, mode 600 temp file, removed after use, never logged |

## 17. Test strategy (`bats`, tmp dirs only, network mocked)

- Manifest: determinism (same input, same bytes), Merkle hash changes on deep edits, sorting, mode normalization.
- Tamper detection: modified file, added member, removed member, altered `MANIFEST`, wrong or unknown signer, missing signature.
- TOML parser: accepted subset, error messages with line numbers.
- Includes: path escape (`..`, absolute), collisions, recursive vs non-recursive, symlinks, empty-directory `mkdir -p` and warning, `--strict`.
- Changelog: Unreleased rewrite, suffixed header, bullet continuation, missing News, empty Unreleased for `release`.
- Templates: substitution, conditionals, section blocks, unknown variable error.
- Dependencies: the full matrix in 11.2 using a mock package manager on `PATH`; conflict flags; non-TTY; custom-command gating; `min_version`; `deps=unmet` written and cleared; nothing written when `--require-deps` aborts.
- Publish: mocked `curl`; draft lookup, idempotent rerun, promotion, suffix forcing prerelease.
- UI: bar formatter at fixed percents with escapes stripped; `CI=1` yields no `\r` or escapes; `NO_COLOR`; `-q` versus log contents; redraw only on percent change.
- Signing uses a throwaway keypair generated per test run.

## 17a. As implemented: deviations from this concept

- Commands: `dabt build` is top-level; the rest live under `dabt pkg <cmd>` (`dabt version`, `dabt info`, ... already mean other things). Installing a package is `dabt app install PKG.dapk|URL`, because `dabt install` installs DABT itself. `.dapk` support was added to the existing `dabt app` installer (`lib/apps/tui_apps.sh`), which keeps using `.dabt.metadata`; `dabt build` keeps that file in sync or generates it.
- `--trust-key` takes the signer fingerprint (`--trust-key SHA256:...`), so a key is never trusted blindly. Unsigned packages: `dabt build --no-sign` and `dabt app install --allow-unsigned`.
- Signing key priority: `--key` > `$DABT_SIGN_KEY` (private key text, for CI) > `sign_key` in `dabt.pkg`.
- The unmet-dependency marker is `$TUI_HOME/apps.deps/<name>` (the signed manifest copy is not edited); `dabt app run` warns about it, `dabt pkg deps APP` clears it.
- `--install-path DIR` is the exact app folder. Dependency `check`/`version_cmd` strings run through `bash -c`, only after the package verified.
- Build numbers: CI counters (GitHub, GitLab, Buildkite, CircleCI, Jenkins, Azure) are used first; `build_offset` in `dabt.pkg` shifts them (and the git commit count); a shallow clone warns. See docs/guide/packaging.md.
- `dabt pkg publish --suffix S` selects a suffixed build; CI tags with a suffix resolve it from the tag.

## 18. Decision log and open questions

Decided:
- D1. Package extension is `.dapk` (confirmed; single constant).
- D2. `dabt.pkg` is a separate TOML file.
- D3. `MANIFEST` header is the descriptor; no separate descriptor file.
- D4. Signing via `ssh-keygen -Y`, signature embedded.
- D5. Empty directory include: `mkdir -p` and warn.
- D6. Publish defaults to draft; suffix forces prerelease.
- D7. Default dependency behavior is to prompt; `--no-deps` warns and continues; `--require-deps` fails.
- D8. The progress bar matches the cache spinner's look exactly (`▕█░▏`, 30 cells), with an ASCII fallback for non-UTF-8 locales.
- D9. Default install location is `$TUI_HOME/apps/<name>/`, overridden with `--install-path`.
- D10. Refactoring `tui_cache.sh` to use the shared bar renderer is out of scope.

Open: none.
