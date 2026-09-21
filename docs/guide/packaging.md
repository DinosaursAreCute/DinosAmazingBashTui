---
title: Packaging and releasing apps
---

# Packaging and releasing apps (`.dapk`)

`dabt build` turns an app folder into one signed, reproducible **`.dapk`** package: a gzip tar whose first member is a `MANIFEST` with the checksums of every top-level file and directory. Design and rationale: [docs/concepts/dapk-packaging.md](../concepts/dapk-packaging.md).

```bash
export DABT_SIGN_KEY="$(cat ~/.ssh/dabt_ed25519)"     # or sign_key in dabt.pkg, or --key FILE; --no-sign for local tests
dabt build                                            # -> dist/<name>-<version>+<build>.dapk (+ .sha256, -news.txt, RELEASE_NOTES.md, build.log)
dabt pkg verify dist/myapp-1.2.3+7.dapk --trust-key SHA256:...
dabt app install dist/myapp-1.2.3+7.dapk --trust-key SHA256:...
```

**Automatic signing:** `dabt build --auto-sign` creates a passphrase-less Ed25519 key at `~/.config/DABT/keys/dabt_ed25519` (mode 600) if none exists and signs with it; later plain `dabt build` reuses it. Key priority: `--key` > `DABT_SIGN_KEY` > `sign_key` in `dabt.pkg` > that default key. `dabt pkg key` prints its fingerprint (`--generate` creates it). Or create your own once: `ssh-keygen -t ed25519 -f ~/.ssh/dabt_ed25519`. The fingerprint (`ssh-keygen -lf ~/.ssh/dabt_ed25519`) is what users pin with `--trust-key`.

## `dabt.pkg` (TOML)

```toml
name             = "myapp"                 # default: .dabt.metadata name, else the folder name
entry            = "bin/myapp.sh"          # default: .dabt.metadata entry
requires_dabt    = ">=0.0.7"
homepage         = "https://github.com/me/myapp"
changelog        = "CHANGELOG.md"          # default: CHANGELOG.md when present
suffix           = ""                      # dev | prerelease | rc.N   (--suffix overrides)
release_template = ".dabt/release.tpl"     # default: share/release/default.tpl
sign_key         = "~/.ssh/dabt_ed25519"
publish_repo     = "me/myapp"              # default: the github.com origin remote

include_paths    = ["bin", "lib", "config", "share"]     # default: everything except dotfiles, dist/, dabt.pkg
exclude          = ["*.log", "tests"]

[[include]]                                # extra files: type file|directory
type   = "file"
source = "LICENSE"                         # inside the project (or use --allow-external)
target = "docs/"                           # in the package; a trailing / keeps the file name
# directories: recursive = true, exclude = ["*.tmp"]; any entry: optional, overwrite, follow_symlinks

[[dependency]]                             # system packages the app needs (never installed without consent)
name   = "ripgrep"
check  = "command -v rg"                   # default: command -v <name>
apt = "ripgrep"  pacman = "ripgrep"  dnf = "ripgrep"  brew = "ripgrep"       # also zypper, apk
# min_version + version_cmd gate a version; optional = true only reports; install = "..." is a last-resort custom command
```

`.dabt.metadata` stays the file `dabt app install` reads; `dabt build` keeps it in sync (version, name) or generates one. `dabt.pkg` accepts a strict TOML subset (strings, booleans, integers, arrays, `[table]`, `[[array of tables]]`); anything else is an error with its line number.

The same include entries work on the command line: `dabt build -f -s LICENSE -t docs/ -d -s assets -t share/assets -r`, and `dabt pkg include add|list|rm`, `dabt pkg dep add|list|rm` edit `dabt.pkg`. `dabt build --plan` prints the resolved `source -> target` list and writes nothing.

## Versions

Version: a CI tag (`v1.2.3`) > `VERSION` > `.dabt.metadata` > `0.0.0`. `--suffix dev` gives `1.2.3-dev`. Build number: `DABT_BUILD_NUMBER`, `GITHUB_RUN_NUMBER`, `CI_PIPELINE_IID`, the git commit count, else 0. Full version `1.2.3-dev+57`.

## Changelog and News

```markdown
## [Unreleased]
### News
- Something users should hear about before updating
  (indented lines continue the bullet)
### Fixed
- ...
```

`dabt build` closes `## [Unreleased]` **in the package only** (`## [1.2.3] - date`; the working tree is untouched) and writes every version's News bullets to `NEWS` inside the package and to `<name>-news.txt` next to it. `dabt pkg release minor` does the same on disk, bumps `VERSION`, commits and tags. Users can read what an update brings without installing it: `dabt pkg news URL-or-file [--since VER]`, `dabt pkg info PKG`, and `dabt app install` shows the News newer than the installed version.

## Release notes

`RELEASE_NOTES.md` is rendered from `release_template`: `{{name}} {{version}} {{build}} {{date}} {{commit}} {{news}} {{compare_url}} {{checksums}}`, `{{section:Fixed}}` (a changelog section of the built version) and `{{#if var}}...{{/if}}`. Unknown variables are errors. `dabt pkg notes` renders without building.

## Publishing to GitHub

`dabt pkg publish [--draft|--prerelease|--release]` (needs `GITHUB_TOKEN` and `publish_repo`). A plain version defaults to a **draft**, a suffixed one to a **pre-release** (a full release is refused for it). Re-running updates the release; `--release` promotes a draft. `dabt pkg ci init github|gitlab` copies a workflow that builds, signs and publishes (`share/ci/`).

## Installing and dependencies

`dabt app install PKG.dapk|URL` verifies structure, signature and every checksum first (fail closed), shows News, then hands the tree to the normal app installer. The first install of an app asks whether to trust the signer (or pass `--trust-key SHA256:...`); a changed signer later is a hard error. Trusted keys live in `~/.config/DABT/trusted_signers`. Unsigned packages need `--allow-unsigned`; `--install-path DIR` picks the app folder.

| flag | dependencies |
|---|---|
| *(none)* | missing ones are listed; on a terminal you are asked `Install missing dependencies? [y/N]`; without a terminal they are only reported and the app is installed marked `deps unmet` |
| `--install-dependencies` | same, default answer yes; without a terminal it needs `--yes` |
| `--yes` | answers that prompt with yes (never trusts a signer, never runs custom commands) |
| `--no-deps` | warn and continue, no prompt, no install |
| `--require-deps` | missing required dependencies abort the install (nothing is written) |

Custom `install` commands are shown verbatim and always confirmed one by one (`--allow-custom-install` skips that). `dabt pkg deps APP` re-checks an installed app and clears the unmet marker.

## Output

Steps look like the installer's (`[n/N]`, `✓`, `!`, `✗`), the bar like the page-cache spinner's. On a terminal a progress bar shows; in CI (`CI`, `GITHUB_ACTIONS`, `GITLAB_CI`, ...) or without a terminal you get plain lines (plus `::group::` / `::warning::` annotations on GitHub Actions). `-v`, `-q`, `--log FILE`, `--progress`, `--no-progress`, `--strict` (warnings fail); `NO_COLOR` is honoured. Results (paths, data) go to stdout, everything else to stderr; a full log is written to `dist/build.log`. Exit codes: 0 ok, 1 failure, 2 usage, 3 refused.
