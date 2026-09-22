# Changelog 📝

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.13] - 2026-09-22

### Fixed

* `dabt -h`'s `update` line didn't mention `--path`/`--trust-key`/`--allow-unsigned` (added in 0.0.12) and spelled out every flag instead of pointing at `dabt update --help` like the other subcommands do; now it's a short summary plus that pointer (`bin/dabt:_help`), so top-level help stays in sync as `dabt update --help` grows.

## [0.0.12] - 2026-09-22

### News

- `dabt update -h` / `--help` now shows help for the update command instead of silently ignoring the flag and running an update check.
- `dabt update --check` now shows what's new since your installed version, not just that an update exists.
- `dabt pkg news` accepts an installed app's name, not just a package/file/URL - it looks up where the app was installed from and, by default, shows news since the version you have.
- `dabt update --path PATH` updates from a local release folder, a `.dapk` package (verified: signature + checksums, same as an app install) or a `.tar.gz`, instead of downloading - for offline machines. It always prints what it's using and how it checked out before touching anything. `--check --path` reports whether it's newer and shows its News.
- `dabt app install --path PATH` and `dabt app update NAME --path PATH` install/update an app from a local folder or `.dapk` file, no connection needed.
- `dabt app run` can now run a plain folder (no `.dabt.metadata`) by pointing `--entry` at its start script, in addition to running a bare script path directly.

### Added

* `dabt pkg news APPNAME`: when `SRC` doesn't look like a `.dapk`/URL/`.md`/existing file, it's resolved via `_tui_apps.lookup` (`lib/tui_apps.sh`) against `apps.list`; `A_SOURCE` becomes the news source and `--since` defaults to `A_VERSION` when not given (`lib/dapk/cmd/verify.sh:dapk.cmd.news`). Errors when the app isn't installed or has no recorded source (e.g. installed with `--force`).
* `tui.update.local PATH DIR` (`lib/tui_update.sh`): populates `DIR/src` from a local release folder (symlinked), a `.dapk` package, or a `.tar.gz`/`.tgz` (extracted); sets `TUI_UPDATE_SRC_KIND` (`folder`|`dapk`|`archive`) so the caller can report what it used. A `.dapk` goes through the real `dapk.verify.run` (`lib/dapk/dapk.sh`, sourced standalone) - structure, signature/trust, checksums, fail closed - not a bare `tar` extraction; new `dabt update --trust-key SHA256:..` / `--allow-unsigned` map to `DAPK_VERIFY_TRUST_KEY` / `DAPK_VERIFY_ALLOW_UNSIGNED` for that step, and its temp verify dir (`TUI_UPDATE_LOCAL_WORK`) is cleaned up alongside the update's own temp dir. Every source is still checked with `tui.sync.valid_source` and security-scanned (`--no-scan` skips it) before anything is applied, same as a download. `tui.update.cli --path PATH` uses this instead of `tui.update.check`/`tui.update.download`, reads `VERSION` from the local copy for the "newer?" comparison, prints which kind of source it used and (for a `.dapk`) the verified signer before showing what would change, and otherwise joins the normal plan/confirm/apply flow. `_tui_update.news_since` split into `_tui_update.news_since_file FILE SINCE` (shared by the network and local paths) plus the existing network fetch wrapper.
* `tui.apps.install` (`lib/tui_apps.sh`): `--path PATH` is normalized to a bare positional `SOURCE` before any other parsing (including the `.dapk`/`.zip` sniff), so it goes through the exact same local-folder/`.dapk` handling as a positional source - no new install path to maintain, just an explicit, connection-free spelling.
* `tui.apps.update` (`lib/tui_apps.sh`): now parses its own options; `--path PATH` requires exactly one app name, looks it up, and reinstalls from `PATH` instead of the recorded `A_SOURCE` (still passing `--force --name --entry` for apps installed without metadata, same as a normal update). Refuses `--path` on the builtin demo app (updated by `dabt update`).
* `tui.apps.run` (`lib/tui_apps.sh`): the folder branch now accepts `--entry REL` as an alternative to requiring `.dabt.metadata` in that folder, so an arbitrary script inside an uninstalled app folder can be named explicitly instead of only being runnable via its bare path.

### Changed

* `tui.update.cli --check` (`lib/tui_update.sh`) now fetches `CHANGELOG.md` from the same ref used for the update (release tag or branch), extracts News with the existing `dapk.changelog.news`/`dapk.news.*` helpers (`lib/dapk/changelog.sh`, `lib/dapk/news.sh`, `lib/dapk/version.sh`, sourced standalone - no dependency on the rest of the `dapk` module), and prints bullets newer than `$TUI_VERSION` before returning. New `_tui_update.changelog_url` / `_tui_update.news_since`.

### Fixed

* `tui.update.cli` (`dabt update`) treated `-h`/`--help` as an unknown flag and fell through to checking for an update; it now prints usage (`_tui_update.cli_help`, `lib/tui_update.sh`) and returns before touching the network.

## [0.0.11] - 2026-09-21

### News: 

- Changed Version Header to be centered

### Changed 

- Changed Release Template to center the header


## [0.0.10] - 2026-09-21

### News

- Release notes now come with the block-font header images, a centered logo, and a version header generated for every release (`dabt pkg release` writes it), in the layout of the 0.0.8 notes.

### Added

* Release notes: the default template uses the header images (`release-new`, `release-added`, `-changed`, `-deprecated`, `-removed`, `-fixed`, `-security` in `assets/headers/`), `logo`, `heading` and `summary`. New `dabt.pkg` keys `release_title`, `release_logo`, `release_header_base`; new template variables `title summary heading logo header_base`.
* `dabt pkg release` generates `assets/headers/v<X-Y-Z>.svg` (block font, `lib/dapk/header.sh`) and commits it with the release; `tools/gen_header.sh` uses the same generator.

### Fixed

* `dabt pkg publish` parses the pretty-printed JSON that api.github.com returns (it failed with "could not read the release id" and could not update an existing release).

## [0.0.9] - 2026-09-21

### News

- `dabt uninstall` now removes everything DABT put on your machine, including every app you installed with `dabt app install` (and their settings), so a reinstall starts clean. Your signing keys are moved to `~/.dabt-keys-backup`, not deleted.

### Changed

* `dabt uninstall` removes all apps installed with `dabt` (through `dabt app remove --purge`, so their `uninstall_hook` runs), the shared `dabt-apps` folder when it is empty, and the launcher recorded at install time (`bindir=` in `install.meta`). `--keep-apps` leaves the apps, `--keep-config` leaves the config home.
* Signing keys in the config home (`keys/`) are copied to `~/.dabt-keys-backup` before the config is removed; `--purge-keys` deletes them instead.

## [0.0.8] - 2026-09-21

DABT can now build, sign, verify and publish `.dapk` application packages, and packages itself with the same tooling.

### News

- New `dabt build` packages an app into one signed, reproducible `.dapk`; `dabt app install` accepts a `.dapk` (file or URL) or a `.zip` holding one, and verifies signature and checksums first.
- The first install of an app asks whether to trust its signer (pin it with `--trust-key SHA256:...`); a changed signer later is refused.
- Packages declare system dependencies; `dabt app install` lists what is missing and only installs them with your consent.
- The tutorial now covers packaging and releasing your own app (`dabt build`, signing, `dabt pkg ci init github`).
- `dabt install` warns when the `dabt` command is not on your `PATH` and shows the line to add for your shell.

### Added

* `.dapk` packaging (`lib/dapk/`, `docs/guide/packaging.md`, `docs/concepts/dapk-packaging.md`): `dabt build [DIR]` turns an app folder into `<name>-<version>-<build>.dapk`, a reproducible gzip tar whose first member is a `MANIFEST` with the checksums of every top-level entry. Configured by `dabt.pkg` (strict TOML subset: `include_paths`, `exclude`, `[[include]]`, `[[dependency]]`, `changelog`, `publish_repo`, `sign_key`, `build_offset`, `requires_dabt`). Writes `<name>-<version>-<build>.dapk.sha256`, `<name>-news.txt`, `RELEASE_NOTES.md` and `dist/build.log`. Exit codes: 0 ok, 1 failure, 2 usage, 3 refused.
* Signing: Ed25519 via `ssh-keygen -Y` (namespace `dabt-pkg`); the signature covers `MANIFEST`, which pins every checksum. Key priority `--key` > `DABT_SIGN_KEY` (private key text, for CI) > `sign_key` in `dabt.pkg` > `~/.config/DABT/keys/dabt_ed25519`; `--auto-sign` creates the default key, `--no-sign` builds unsigned. `dabt pkg key [--generate]` prints the fingerprint.
* Versions and build numbers: the version comes from a CI tag (`v1.2.3`), `VERSION`, or `.dabt.metadata`; `--suffix dev|rc.N` adds a pre-release suffix. The build number is appended after a dash (`1.2.3-57`, `1.2.3-dev-57`) and comes from `DABT_BUILD_NUMBER`, the CI run counter (`GITHUB_RUN_NUMBER`, `CI_PIPELINE_IID`, `BUILDKITE_BUILD_NUMBER`, `CIRCLE_BUILD_NUM`, `BUILD_NUMBER`, `BUILD_BUILDID`) plus `build_offset`, or the git commit count (with a warning on a shallow clone).
* `dabt pkg`: `verify`, `info` (descriptor and News without extracting), `news [--since VER]`, `version [show|bump]`, `release major|minor|patch` (closes the changelog, bumps `VERSION`, commits, tags), `publish [--draft|--prerelease|--release]` (GitHub release with the package, checksum and News as assets), `deps`, `include`, `dep`, `ci init github|gitlab` (workflows in `share/ci/`).
* Changelog and News: `dabt build` closes `## [Unreleased]` in the package only and writes every version's `### News` bullets to `NEWS` and `<name>-news.txt`; release notes come from `share/release/default.tpl`. `dabt app install` shows the News newer than the installed version.
* `dabt app install` for packages: verifies structure, signature and checksums (fail closed) before anything is written; `.zip` sources (for example a downloaded workflow artifact) are unpacked first; `--trust-key`, `--allow-unsigned`, `--plan`, `--install-path DIR`; trusted signers live in `~/.config/DABT/trusted_signers`.
* Package dependencies: `[[dependency]]` tables are checked at install, missing ones listed; `--install-dependencies`, `--yes`, `--no-deps`, `--require-deps`, `--allow-custom-install`, `--pm NAME`. Installed apps carry a `deps unmet` marker until `dabt pkg deps APP` clears it.
* CI: `.github/workflows/build.yml` runs the bats suite in parallel, builds and signs a DABT package (checked against the pinned `DABT_SIGNER_FINGERPRINT`), installs and updates DABT from that package, and publishes a GitHub release on `v*` tags (a pre-release for suffixed tags such as `v1.2.3-rc.1`). `tools/ci_setup.sh` sets the repository secret and variable, `tools/ci_integration.sh` is the install/update check.
* `dabt.pkg` packages the framework itself (`docs/concepts/dabt-framework-package.md`); a `LICENSE` file (MIT).
* Tutorial "Writing Your First App" gains steps 9 and 10: package the app with `dabt build` and release it from GitHub Actions.
* Documentation site (Jekyll, GitHub Pages) built from `docs/`; README badges (build status, license), an "Apps built with D.A.B.T" section linking the DABT File Explorer, and tutorial links.
* bats tests for packaging (`tests/dapk/`: build, verify, install, publish, toml, ui).

### Changed

* `dabt install`: when the `dabt` command's folder is not on `PATH` it prints a warning and the `fish`/`zsh`/`bash` line to add it.
* `dabt` ends its command dispatch with `esac; exit $?` on one line, so `dabt update` can replace `bin/dabt` while it runs.

### Fixed

* Widgets outside their pane's content area are clipped instead of drawing over the border and neighbouring panes (charts and long content).
* The `tui.exec` status line no longer overflows a narrow pane: the command is shortened and, when there is no room for both, only the status is shown.
* `tui.reset_ui` dismisses running `tui.exec` instances with their page, so leaving a page no longer breaks the control pane of the next one.

## [0.0.7] - 2026-09-20

DABT is now also an application manager: install, update and uninstall apps, with a security scan in front of every install.

### Added
* Docs: tutorials `docs/tutorials/writing-your-first-app.md` and `writing-your-first-plugin.md` (colored block-font headers, runnable examples `examples/first-app/` and `examples/plugins/stretch.plugin.sh`), technical guide `docs/guide/writing-an-app.md`. Header generators: `tools/gen_header.sh "TEXT"`, `tools/gen_headers.sh`, `tools/gen_tutorial_headers.sh`.
* Settings > Plugins: **[ Scan ]** button and menu entry scan the selected plugin and show the result in a modal. `dabt update` and the installer scan the incoming files (spinner, `--force`, `--no-scan`).
* Logo and README section-header SVGs in the block5 font (`assets/`).
* `dabt scan PATH... [--deep] [--strict]` (`lib/tui_scan.sh`): security scan for shell scripts. Built-in grep rules (HIGH / WARN: pipe-to-shell, reverse shells, `rm -rf /`, setuid, secrets, persistence ...) need no dependencies; ShellCheck is used when on PATH, Semgrep with `--deep`. `dabt scan --tools`, `dabt scan --install shellcheck|semgrep` (shows the command, asks first).
* `dabt app install|list|info|run|update|remove` (`lib/tui_apps.sh`): apps are folders with a `.dabt.metadata` file, installed from a folder or git URL, tracked in `apps.list`, settings kept on remove unless `--purge`. Installs are scanned first (`--strict` refuses on HIGH findings, `--no-scan` skips).
* App hooks: `install_hook` / `uninstall_hook` in `.dabt.metadata`, run after install / update and before remove (`DABT_HOOK`, `DABT_APP_NAME`, `DABT_APP_DIR`, `DABT_APP_CONF`, `DABT_APP_VERSION`).
* `tui.plugin.install` scans the plugin (`--strict`, `--no-scan`); a summary lands in `TUI_PLUGIN_WARNING`.
* The demo is listed as a built-in app (`dabt_demo`); it cannot be removed and is updated by `dabt update`.
* `docs/guide/install-and-update.md`; bats tests for the updater (`tests/updater.bats`).
* `dabt`: no args = help; `-d/--details` kv-rendered install info; `--demo` runs the demo. Installer TUI wizard removed.
* Installer: `install.sh` shows the locations and asks (plain prompt, no TUI) (`--yes`, `--prefix`, `--config`, `--bindir`, `--policy`, `--dry-run`). Detects an existing install (`~/.config/DABT`, else `$DABT_HOME`).
* Updater: "DABT: Check for updates" / "DABT: Update DABT ..." in the command bar and `dabt update`. Downloads the release from GitHub, lists every changed file, asks per conflict (override / skip / write `.new` / show differences), backs up what it replaces.
* `bin/dabt` command: `dabt`, `dabt update`, `dabt doctor`, `dabt version`, `dabt install`.
* `lib/tui_sync.sh`: three-way file sync (checksum manifest) used by the installer and updater.
* bats tests (`tests/`): 73 tests for config-home detection, installer and updater; network mocked, everything in tmp dirs.
* Defaults and shipped plugins are installed into `~/.config/DABT/defaults` and `~/.config/DABT/plugins`; the config home is found via `$TUI_HOME`, `~/.config/DABT`, `$DABT_HOME`, or `<program>/etc/dabt.env`.
* Paths shown in the plugin UI are resolved (no `..`).
* Plugin system (`bin/tui_plugin.sh`): drop-in `*.plugin.sh` files or folders; enable, disable, reload, install and remove at runtime; automatic cleanup of everything a plugin registered; `requires`; saved state; hooks (`init ready page resize key quit exit`). `tui.plugin.*`, `tui.hook.*`, `docs/guide/plugins.md`, example in `examples/plugins/`.
* Built-in `terminal_shortcuts` plugin: detects the terminal, lists the keys it keeps (kitty: its real effective keymap; GNOME Terminal via gsettings; tmux root table), a guided key test for any terminal, frees them while DABT runs (kitty include + reload, gsettings, tmux) and restores them on exit or after a crash; config snippets for alacritty, wezterm, ghostty, Windows Terminal and others. Setting on the default Settings page.
* Settings > Plugins tab: all detected plugins, details (state, source, location, file count, size, lines, functions, what it registered), a file tree and a viewer for its files.
* Files live in `~/.config/DABT/`: `plugins/` and `apps/<app>/` (`dabt.conf`, `keybinds.xml`, `settings.conf`, `app.meta` with name, title, description, versions, first/last run, run count). Old `~/.config/<app>/` files are moved automatically. `tui.app.meta_get/set`.
* The command bar shows `plugin: NAME` next to commands a plugin registered.
* `alt+shift+arrows` as an alias of `ctrl+shift+arrows` (word / empty-line selection); rxvt-style arrow sequences; `bin/debug/keys.sh` shows the raw bytes and key name of any key.
* Textarea: `ctrl+up` / `ctrl+down` jump to the previous / next empty line, `ctrl+shift+up/down` select up to it; `ctrl+shift+left/right` select by word.
* `alt+arrows` scroll a scrollable pane (else move pane focus); the wheel falls through to the pane when a text box, list or table cannot scroll; wheel scroll no longer snaps back to the cursor.
* `tui.view TITLE TEXT` scrollable text viewer; `tui.action.text_keys` (`f1`, and "Help: text editing keybinds" in the command bar) lists every text-editing key.
* The prompt dialog now uses the text engine (selection, word jumps, undo, clipboard).
* The app owns every key: the tty runs with `-isig -ixon -iexten -echo -icanon`, so ctrl+c / ctrl+z / ctrl+y reach DABT as keys; ctrl+c copies, ctrl+z / ctrl+y undo / redo. Unread input is drained on exit so nothing leaks to the shell. ctrl+c no longer interrupts the app (quit: q / ctrl+q).
* Text editing engine (`bin/tui_text.sh`) for input, password and textarea: selection (shift+keys, drag, double/triple-click, ctrl+a), word jumps (ctrl+arrows), cut / copy / paste, undo / redo, click to place the cursor, kill-line keys.
* `<textarea>` / `tui.textarea`: multi-line editor that fills or spans rows, scrolls, shows a scroll indicator.
* `<password>` / `tui.password`: masked input that never copies.
* `<list>`, `<table>`, `<select>`, `<progress>` widgets (`bin/tui_widgets.sh`) with selection, wheel, click and double-click.
* `tui.text.*` API (selection, cursor, insert, undo) and `tui.on_change`.
* Widgets page in the demo; `docs/guide/widgets.md` with a Markdown roadmap; `bin/debug/widget_tests.sh` (39 headless checks).
* Toast position (`tui.notify.position`, six spots) and default lifetime (`tui.notify.seconds`), both persisted and set from buttons on the default Settings page.
* Dialogs (`bin/tui_dialog.sh`): `tui.confirm`, `tui.message`, `tui.prompt` (validation, editing, paste), `tui.choose`; callback style, keyboard and mouse.
* Toasts: `tui.notify MESSAGE [info|success|warn|error] [SECONDS]`, stacked above the footer, survive page changes; `tui.notify.clear`.
* Dialog and toast theme classes (`.dialog*`, `.toast*`) in the default and demo stylesheets.
* `confirm.quit` setting: `tui.action.quit` asks first (`tui.action.quit_now` never does); checkbox on the default Settings page.
* Demo: Feature lab "Dialogs & toasts" column; Settings reset and Keybinds discard/drop ask first; saves and setting changes toast.
* `bin/debug/dialog_shots.sh` / `.py`: headless frames and PNGs of every dialog state (doubles as a smoke test).
* `config/tui.xsd` brought up to date (`split="fixed"`, `size_w`/`size_h`/`span`/`newline`, `<footer>`, `<bind>` scope, `defaults`).
* `:checked` / `:unchecked` theme states for checkboxes, with a `.check` class in every shipped theme and used by the demo and default pages.

### Changed
* README: DABT is described as a TUI framework and an application manager (install, update, uninstall, security scan).
* Demo header clock shows `%H:%M:%S` only.
* Repository layout: framework moved from `bin/` to `lib/`, `config/default` -> `share/defaults`, shipped plugins -> `share/plugins`, `config/DABT_demo` -> `share/demo`, `bin/debug` and `scripts/` -> `tools/`, tests in `tests/`. The page cache and other runtime files live in the config home, not the program folder.
* Demo Components toolbar is one `tui.fixed` grid of equal 15x1 button cells (was three weighted rows); adds the missing `.sc_purple` class to every theme.


## [0.0.6] - 2026-09-19

### Added
* Docs reorganised: `docs/README.md` (architecture + map), `docs/guide/`, `docs/api/`, `docs/design/`.
* API reference: `docs/api/reference.md` (every public function and parameter), task tour in `docs/api/README.md`, `docs/api/renderers.md`, generated `docs/api/terminal-controls.md` (`scripts/gen_terminal_controls_doc.sh`).
* Design paper: `docs/design/rebindable-input-and-developer-ergonomics.md` (why the UX and DevX changes were made).
* Docs page tabs follow the new layout (README, docs index, guides, API reference, design write-ups).
* Input bindings (`bin/tui_input.sh`): `tui.bind` / `tui.unbind` / `tui.bind.list`, markup `<bind>`, pane-scoped and chained bindings. See `docs/guide/input-bindings.md`.
* Keys and mouse are decoded into readable names (`ctrl+c`, `shift+up`, `mouse:right`, `wheel:down`, ...), including F-keys and CSI-u terminals.
* Built-in actions (`tui.action.*`) that every default key and click now goes through, so all of them are rebindable.
* Default keybinds live in `config/default/keybinds.xml`, grouped and opt-out (`tui.defaults.off GROUP`, `<tui defaults="-quit">`).
* `<bind scope="global">` for binds that survive page changes.
* User keybinds (`tui.bind --user`): kept as a draft, saved with `tui.bind.save`, restored with `tui.bind.discard`, loaded on the next start.
* Keys page: Save / Discard buttons and an "unsaved changes" marker for your keybinds.
* `q` / `ctrl+q` quit is now a default instead of a per-page bind.
* Keyboard pane focus: `f6` / `shift+f6` / `alt+arrows` with a highlighted border; scroll keys follow it.
* `tui.action.focus_pane`, `tui.action.goto` and a page registry (`tui.get.pages`) for jump binds.
* Spatial arrow-key navigation between widgets (`tui.action.focus_dir`): same row for Left/Right, same column beam for Up/Down.
* `ctrl+wheel` scrolls exactly 1 line, `ctrl+shift+wheel` exactly 1 char.
* Bracketed paste: pastes arrive as one `paste` event (bindable), inserted into the focused input by default.
* `tui.clipboard.copy` (OSC 52) and `tui.clipboard.paste`.
* Command palette (`ctrl+p` / `:`): fuzzy search, Enter to run, mouse support.
* Command registry API: `tui.cmd.add`, `tui.cmd.load`, `tui.cmd.provider`, `tui.cmd.run`; DABT's own commands use it (`config/default/commands.xml`).
* Palette providers for pages, themes, panes and default-key groups; keybind hints come from the live bindings.
* Overlay and modal layer (`tui.overlay.*`, `tui.modal.*`): overlays are redrawn over every repaint, a modal owns keyboard and mouse.
* Default Settings and Keybinds pages ship with DABT (`config/default/pages/`), opened from the palette; an app can replace them by re-registering `dabt.settings` / `dabt.keybinds`.
* `tui.config.get/set/unset`: persistent framework settings (theme overlay, default-key groups, input behaviour), applied at startup.
* Page history: `tui.action.back` and `alt+backspace`.
* `tui.overlay.box`: a helper for drawing framed boxes from overlays and modals.
* Demo: Debug > Feature lab page with a button for every palette, modal, overlay, mode, focus and clipboard feature, a live state readout and an event log.
* `bin/debug/` profiling scripts (`profile_page_switch`, `profile_replay`, `profile_calls`, `profile_callbacks_source`), `count_forks` with a README.
* `<footer/>` component: a key-hint bar (quit, command bar, back ...) on the last terminal row wherever it is declared; keys are looked up live from the bindings. API: `tui.footer.show/add/hide`.
* Every demo page now has the shared header (title banner and live clock, built on `tui.clock`) inside a framed root pane, with the footer bar below it.
* `tui.bind.table`, `tui.require`, and fork-free style getters (`tui.class.style`, `tui.class.sgr`, `tui.style.sgr`, `tui.class.names`).
* Event context in handlers: `TUI_EVENT_KEY`, `_X/_Y`, `_PANE`, `_WIDGET`, `_BUTTON`.
* Repeat coalescing: fast wheel spins and held scroll keys merge into one redraw (`TUI_EVENT_COUNT`).
* Keybind kill-switch (`ctrl+alt+k`) with an always-on-top warning box.
* Pass-through mode (`ctrl+alt+p`): hands mouse and keyboard back to the terminal for native selection and copy.
* `retain_input_on_submit` and `sticky` on `<input>`; Enter keeps focus by default, and a same-page reload restores it.
* `hpad` / `vpad` on panes and widgets; padding shrinks the usable output area.
* Parent panes can draw their own border (layered borders); borders drop automatically when space runs out.
* `split="fixed"` / `tui.fixed`: fixed-size grid with `size_w`, `size_h`, `span` and `newline`.
* `bin/tui_api.sh` live helpers: `tui.every`, `tui.after`, `tui.clock`, `tui.watch`, `tui.monitor`, `tui.set_text`.
* Fork-free `/proc` samplers (`tui.sys.cpu/mem/load/uptime`) and rolling history (`tui.hist.*`).
* `tui.get.*` getters for dimensions, position, border, pad, style, widgets, focus and more.
* `tui.pane_size`, `tui.relayout [PANE]`, `tui.set_label`, `tui.pad`, `tui.pane_pad`.
* App-wide theme overlays: `tui.theme.set/clear/current` with Ocean, Forest, Sunset and Light palettes.
* `TR_WIDTH` lets the box-style renderers fit a pane instead of the terminal.
* `_TUI_ON_RESIZE_FN` and `_TUI_ON_KEY_EVENT` hooks.
* Stylesheet memoization in `tui_cache.sh`: each stylesheet is parsed once, then re-applied from memory.
* Demo: functional Settings page (themes, borders, padding, fonts, saved to disk).
* Demo: Components split into Renderers, Theme colors, Fit to size and Live pages, plus gauge, sparkline, vbar, linechart and CSV views.
* Demo: Keys page (live binding table, runtime rebinding) and a Debug Keyboard & mouse view that lights each key and button.

### Changed

* Border ring, title tag and scrollbar now use the pane background, which removes the seam around panes.
* Pane text now uses the pane's colours, so themes apply to content as well as chrome.
* Terminal resize is coalesced and drawn as one synchronized frame; `tui.goto` and `tui.relayout` are too.
* Theme loading no longer forks; a first parse dropped from about 250 ms to about 27 ms, and a page visit to about 1 ms.
* Page switches are faster: `tui.output` and its bounds calculation no longer fork, small plain panes render without awk, and paths and nav-button handlers no longer fork.
* The Keys page, the theme view and the keyboard view load 2-4x faster after those changes (for example about 1050 ms to 280 ms for the keyboard view).
* Hover, focus, click and render no longer fork per widget: a mouse move went from 38 processes to 0, a full render from 136 to 4.
* The renderer builders (box, alert, table, hbar, linechart ...) are fork-free (alert 30 to 0, linechart 54 to 1) with byte-identical output.
* The Monitor page refresh went from about 650 processes to about 40.
* `tui.init` also sets `-ixon -iexten` so `ctrl+s`, `ctrl+q` and `ctrl+v` reach the app.
* A bound command that isn't defined right now is skipped instead of raising an error.
* The demo's `clock.sh` (single-slot tick hook) is gone; the header uses `tui.clock` and `tui.every` instead.
* Nav reorganised: Forms is now Settings, Features is now Layout, and the Clock page was removed (the Live page replaces it).

### Fixed
- Overlays/footer redraw only after a frame flush (was every tick); footer no longer wraps/scrolls the last row

* Pane content vanished on resize because `_TUI_PANE_CONTENT` was never declared associative.
* `tui.exec` panes weren't repainted on resize.
* A failed `stty size` during resize made the whole UI lay out at 24x80.
* `tui.goto` broke on absolute paths.
* `tui.start` aborted on any page without `on_visit`.
* Monitor page pointed at a missing `on_visit` function.
* Cached pages lost `hpad`/`vpad` and the post-border relayout.
* Split mouse reports could leak into a focused input as typed text.
* Undecodable keys crashed the binding lookup with `bad array subscript`.
* Pasting with nothing focused could throw `bad array subscript`.
* Single-line CSS rules (`.a { fg: x; }`) were silently ignored.
* XML entities such as `&amp;` in attributes weren't decoded.
* `tui.reset_ui` now clears leftover pane content and the input hooks.
* Debug Keyboard tab loaded the Events page's script and drew stray text at the top-left.

## [0.0.5] - 2026-09-16

### Added

* `bin/bench_page_switch.sh`  measures `tui.goto`'s reset/load/render timing across page switches (a given page list, or every page in a directory). Runs in an isolated background worker with a live progress bar and stall watchdog, so it's always killable from the terminal even if the worker itself hangs. Reports a `terminal_renderer.sh` table (mean/min/max/cold ms, load%) plus a sparkline timeline and run summary, and persists `report.txt`/`results.txt` under `logs/<run>/` (gitignored) for later inspection.
* `bin/tui_cache.sh`  page-load caching. Records the sequence of `tui.*` builder calls a normal `tui.load` makes once, then replays them later via `eval`, skipping markup re-parsing entirely on a cache hit; `<script src>` sourcing and `on_visit` are themselves recorded/replayed as single calls, so dynamic per-visit content (e.g. `monitor_callbacks.sh`'s live refresh) still runs fresh every time, never from a cache. `tui.goto` now goes through this automatically (`tui.load_cached`) for any app built on the framework, with a cache miss or a since-edited page/include transparently falling back to a normal load  never a behavior difference, purely speed. `tui.start_cached` additionally pre-warms every sibling page in a directory behind a background worker and a centered D.A.B.T banner + "caching sites" progress bar, and persists the cache to `.cache/tui_pages/` (gitignored, keyed by each page's and its `<include>`s' mtimes) so an unchanged relaunch skips warming entirely and only a page that actually changed gets re-recorded.

### Changed

* `bin/DABT_demo.sh` now launches via `tui.start_cached` instead of `tui.start`.

### Fixed

* `config/monitor_callbacks.sh`'s `_mon_output_fit` could crash with `substring expression < 0` when `tui.content_area` returned a negative height (e.g. before layout settles)  height is now clamped to 0.
* `<button page="…">`'s per-page navigation handler is now itself recorded/replayed by the caching system (`_tui_cache_define_goto`) it used to be defined via a raw `eval` outside any cacheable call site, so on a cache-hit replay it silently never got (re)defined, breaking that button's click handler.

### Removed
* 

### Security
* 


## [0.0.4] - 2026-09-15

### Added

* 

### Changed 
* 

### Fixed 
* `style.sh` Fixed colliding colors in  css themeing for sudo states causing ansi codes spilling into the frame. 

### Removed 
* 

### Security
* 


## [0.0.3] - 2026-09-14

### Added

* Mouse hover tracking: `tui.init` now enables xterm any-motion tracking (`\e[?1003h`), and widgets react live via `.class:hover` theme rules  see `docs/ui_markup.md` and the new architecture writeup, `docs/Bending-The-Planet-To-Your-Will_...md`.
* Pane borders react to `.class:focus` while any widget inside that pane has keyboard focus (`_tui._draw_pane_border`), reusing the same style mechanism instead of a second one for hover.
* Mouse-motion coalescing (`_tui._coalesce_mouse_motion`): a fast pointer sweep resolves and redraws hover state once, against the newest position, instead of once per crossed cell  droppable motion reports are distinguished from clicks/releases/wheel notches via the SGR protocol's own motion bit, and anything not dropped is rewound byte-for-byte (`_TUI_PENDING_INPUT`) so it's replayed in order.
* Configurable input timing knobs: `TUI_INPUT_POLL_TIMEOUT`, `TUI_INPUT_IDLE_TIMEOUT`, `TUI_ESCSEQ_BYTE_TIMEOUT`, `TUI_MOUSE_DRAIN_PEEK_TIMEOUT`, `TUI_MOUSE_DRAIN_MAX`.
* `split="grid"` pane layout: an R×C grid of cells sugar over `tui.hsplit`/`tui.vsplit`, with explicit (`grid_row`/`grid_col`) and loose (document-order) child placement, mixable on one grid; `rows`/`cols` may be omitted and are computed from item count; `fit="pack"`/`"stretch"` controls whether a short row leaves blank trailing cells or its cells expand to fill the row; `row_weights`/`col_weights` weight lists. Imperative form: `tui.grid`.
* `<checkbox>` widget  persistent boolean state, toggled by click or Enter, `action` called with the new value ("0"/"1"). `tui.checkbox`, `tui.checkbox.toggle`.
* `<tabs>`/`<tab>` container  a row of header buttons that swap a content pane, built on `split="grid"`; "active" reuses existing focus styling rather than a new style state. `style="compact"` (or `tui.tabs.compact`) switches to a borderless, background-color-indicated header for panes that can't spare the ~3 rows a bordered header needs. Imperative form: `tui.tabs.add`/`tui.tabs.build`/`tui.tabs.activate`.
* `tui.factory.*`  namespace-scoped dynamic construction/teardown (`label`/`button`/`input`/`checkbox`/`grid`/`clear`) for layouts whose shape isn't known until runtime, generalizing the `tui.exec` widget-group pattern beyond a hardcoded prefix.
* Automatic content-fit checking: a leaf pane's actual content (furthest widget row/longest widget text, or `tui.output`'s tracked line/width) is compared against its real size on every full render and resize, showing the existing `min space = …` warning without an explicit `min_width`/`min_height`. Scrollable panes are exempt; `strict_fit="false"` opts a specific pane out.
* `<tui on_visit="fn">`  a callback run once a page's panes/widgets are fully built (on every load, including a `tui.goto` revisit), for pages whose content isn't fully known from static markup (e.g. scanning a directory to build tabs).
* Opt-in render-time tracking: `_TUI_PERF_TRACKING=1` plus `tui.perf.mean_render_ms SECONDS`, timestamped via bash 5's `$EPOCHREALTIME` (fork-free) with a `date`-based fallback on older bash.
* `config/debug.xml` / `debug_callbacks.sh`  an observability page: a dynamically-sized interactive grid (rebuildable with a random item count), a capped input-event tape, live hover/focus status, and the render-time readout.
* `config/tabs_demo.xml` / `tabs_demo_callbacks.sh`  a fully declarative `<tabs>` usage example.
* `config/docu.xml` now discovers every `.md` file under `docs/` plus the README at load time (via `on_visit`) and builds one tab per file automatically, instead of a hand-maintained tab list.
* Checkboxes added to `settings.xml`'s forms demo (notifications, dark mode), read back in `on_theme_apply`.

### Changed

* `_tui._pane_at` no longer returns its result via `printf` captured through a subshell  it writes to a global (`_HIT_PANE`), matching the fork-free convention `_tui._hit_test` already used. `_tui._locate_pane` additionally short-circuits the full pane scan to 4 comparisons as long as the pointer stays inside the previously hovered pane.
* Consolidated five near-identical `mode.sync_start`/`printf`/`mode.sync_end` blocks into one `_tui._flush` helper (also the render-time tracking's single instrumentation point).
* `case_study.xml` and `docu.xml` migrated from hand-rolled tab-button wiring to `<tabs style="compact">`  neither page's header pane has the ~3 rows a framed header cell needs; `tabs_demo.xml`'s header pane was given more weight instead, to keep it a working example of the default framed style.
* `tui.tabs.activate` now passes the tab id to its `action` callback (backward compatible  existing zero-arg callbacks simply ignore it).
* `tui.tabs.build` now exempts every header cell it creates from the content-fit checker (`strict_fit="false"`)  a tab label clipping when there isn't room is expected UI behavior, the same as a nav sidebar button, not a real "this pane is broken" condition worth a warning.

### Fixed

* **`tui.render` was losing the content-fit cache it had just computed.** `_tui._refresh_content_fit`'s writes happened inside `tui.render`'s `buf="$( … )"` command substitution  a subshell  so `_TUI_P_EFFECTIVE_MINW`/`_MINH` never actually reached the running shell; every later hover/focus/click-triggered redraw (which runs outside that subshell) read an empty cache and silently treated it as "no minimum." In practice this showed as a pane's size warning and widget text flip-flopping depending on which code path happened to touch it last (visible on `<tabs>` header cells: the label was blank until hovered, a border appeared on click, and it went blank again the moment a different tab was clicked). Fixed by computing the cache for every leaf pane in the parent shell before entering the subshell.
* Scrollbar jump-to-click no longer fires on bare hover motion (`btn` values without a button actually held)  previously any-motion tracking made hovering a scrollbar track snap the viewport as if it had been clicked.
* `tui.factory.*` constructors no longer `printf` the id they generate  in a TUI, stdout is the screen, and calling one in a loop without capturing it (an easy mistake, not just a hypothetical) wrote raw id text straight onto the terminal outside any pane. The id is still available via `_TUI_FACTORY_LAST_ID`.
* Render-time tracking (`_tui._now_us`) no longer crashes under a locale where `$EPOCHREALTIME`'s decimal separator isn't `.` (e.g. `de_DE.UTF-8` uses `,`)  splits on the first/last non-digit character instead of a literal period.
* Fixed `tui.focus`/`_tui._unfocus` throwing `bad array subscript` the first time focus moved and there was no previously-focused widget (bash treats an empty-string subscript on an associative array as invalid, not merely absent)  added `_tui._widget_pane`, which returns empty for an empty id instead of indexing.
* `case_study.xml`'s "Technical Document" tab pointed at a doc path that no longer existed after a file rename; corrected, and made path-resolution independent of the current working directory (`${SCRIPT_DIR}` instead of a relative `../docs`).
* `home.xml`: the footer pane's `border="heavy"` needed 3 rows it never had (weight gave it ~2), and one feature-list label didn't fit the page's own content pane at 80-column terminals  both silently clipped before the content-fit checker existed to report it, now fixed.
* `_nav.xml`: the "Documentation" label didn't fit the nav sidebar at 80 columns, shortened to "Docs".

## [0.0.2] - 2026-09-13

### Added

* High-performance scrolling viewports enabled via the `scroll="v"`, `scroll="h"`, or `scroll="both"` pane attributes.
* Single-pass AWK "Shader" architecture for rendering: handles ANSI-safe horizontal slicing, padding, and absolute cursor positioning in a single compiled execution block to bypass Bash subshell bottlenecks.
* "Jump-to-Click" scrollbars: clicking horizontal or vertical pane borders instantly calculates relative percentages and snaps the viewport offset.
* Mouse wheel support for vertical scrolling (buttons 64/65).
* Shift + Mouse wheel support for horizontal scrolling (buttons 68/69).
* Keyboard scrolling navigation utilizing Vim bindings (`hjkl`) and Shift+Arrow keys (intelligently gated so they type normally when focusing a text input field).
* Render debouncing / batching system (`_TUI_PENDING_RENDER` and `_TUI_RENDER_TIMEOUT`) to prevent UI lag during rapid input events like continuous mouse-wheel spins.
* Lazy pre-computation caching (`_TUI_P_LINES` and `_TUI_P_MAX_W`) that evaluates string dimensions instantly upon injection to speed up scroll math.
* `tui.output`, `tui.output_append`, `tui.output_clear`  render arbitrary multi-line content into a pane with ANSI color passthrough, auto-scroll, and visible-width truncation, without requiring `tui.exec` or a PTY.
* Shared ANSI-aware text helpers: `_tui._clean_ansi` (strip control sequences, preserve SGR colors) and `_tui._visible_truncate` (truncate to N visible characters without breaking escape sequences).
* Pane output content survives `tui.render` / resize  stored in `_TUI_PANE_CONTENT` and re-rendered automatically.
* Renderer showcase page (`components.xml`, `showcase_callbacks.sh`) demonstrating all twelve `terminal_renderer.sh` commands via `tui.output`.
* `scrolling.xml` demo page to showcase independent vertical, horizontal, and multi-axis scrolling capabilities.
* `case_study.xml` page providing a real-world layout stress test, rendering a live Markdown document alongside a complex system metrics table.
* `show_all` callback composing every renderer into a single scrollable output.
* `.sc_purple` theme class.

### Changed

* Completely rewrote `_tui._render_output` to eliminate slow Bash subshell `for` loops, replacing them with a highly optimized `awk` backend.
* Redesigned the `tui.run` main event loop to intercept scroll actions and defer rendering until the input stream pauses.
* `_exec_render_output` now bypasses the widget system entirely, routing the execution buffer directly through the new AWK shader for correct ANSI passthrough and high FPS.
* `_exec_tick` updated to enforce a 2500-line rolling ring-buffer cap on `_EXEC_BUF` to prevent memory blowouts during infinite streaming processes.
* `_exec_strip_ansi` replaced by `_exec_clean_line`  preserves SGR color/style sequences instead of stripping all ANSI codes.
* `_exec_setup_output_pane` no longer creates per-row `_xo_N` label widgets.
* `_exec_tick` keeps blank lines in the output buffer to preserve intentional newline spacing.
* Line truncation in exec output uses `_tui._visible_truncate` instead of byte-position `${text:0:N}`, which could split escape sequences mid-byte.
* Re-mapped UI hit testing in `_tui._handle_mouse` to support dynamic hover tracking (`_TUI_HOVERED_PANE`) to know where to route scroll wheel events.

### Fixed

* Fixed a severe formatting break and vertical scroll-locking bug by forcing `tui.output` to split multiline strings via `mapfile` instead of injecting massive blocks into index `0`.
* Fixed a scope-loss crash (`arithmetic syntax error`) when sourcing the renderer script by assigning the `_BANNER_FONT` associative array to global scope (`declare -gA`).
* Fixed a typo inside `_tui._layout` where `$pc0` was incorrectly evaluated instead of `$pc`, displacing vertically split panes to the left screen edge.
* Fixed recursive layout bug in `_tui._layout` where the `for` loop variable `i` was not declared `local`, causing child calls to clobber the parent's loop counter and skip all sibling panes after the first container child in a nested split.

### Deprecated

* `_exec_strip_ansi`  replaced by `_tui._clean_ansi` / `_exec_clean_line`.

### Removed

* Removed inefficient continuous mouse dragging logic (and `wc -l` subshell checks) from `_tui._handle_mouse` in favor of Jump-to-Click tracking.
* Removed arbitrary math multipliers for scroll speeds, syncing offsets exactly to pre-computed text length ratios.

### Security

* (No relevant security changes in this release)
