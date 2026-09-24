# Apps: install, update & scan

`lib/apps/` - the machinery behind the `dabt` command: installing and running DABT applications (`dabt app`), installing and updating DABT itself (`install.sh`, `dabt update`), the three-way file sync both use, and the security scanner (`dabt scan`). Guide: [../guide/install-and-update.md](../guide/install-and-update.md). ← [API index](README.md) for the full module list and a task-oriented tour with examples.

Apps rarely call these directly. `tui_sync.sh`, `tui_install.sh` and `tui_update.sh` are loaded by `tui.sh`; `tui_apps.sh` is loaded by `bin/dabt` only, and `tui_scan.sh` on demand (`tui.require tui_scan`). None of them needs a running TUI except the functions marked "inside the app". Functions return `0` unless their entry says otherwise.

## Applications

An application is a folder with a `.dabt.metadata` file (`name`, `entry`, and optionally `version`, `title`, `description`, `author`, `own_dir`, `install_hook`, `uninstall_hook`, `min_dabt`, `max_dabt`).

<!-- api: tui.apps.install tui.apps.update tui.apps.remove tui.apps.list tui.apps.info tui.apps.run tui.apps.meta_load tui.apps.compat tui.apps.cli -->
| Function | Summary |
|---|---|
| [`tui.apps.install`](apps/tui.apps.install.md) | Installs a DABT application from a folder or a git URL (`URL#ref` for a branch or tag). `dabt app install` calls it. |
| [`tui.apps.update`](apps/tui.apps.update.md) | Reinstalls apps from their recorded source (all when no `NAME` is given), keeping each app's settings files. |
| [`tui.apps.remove`](apps/tui.apps.remove.md) | Uninstalls an app after running its `uninstall_hook`. Its settings folder is kept unless `--purge` is given; `--yes` skips the confirmation. |
| [`tui.apps.list`](apps/tui.apps.list.md) | Prints a table of installed apps: name, version, entry and location. |
| [`tui.apps.info`](apps/tui.apps.info.md) | Prints the details of an installed app, including its metadata. Returns `1` when it is not installed. |
| [`tui.apps.run`](apps/tui.apps.run.md) | Starts an installed app by name, or an app folder or script directly, passing `ARGS` on. `dabt app run` calls it. |
| [`tui.apps.meta_load`](apps/tui.apps.meta_load.md) | Parses and validates `DIR/.dabt.metadata` into the associative array `TUI_APP_META`. Returns `1` with the reason in `TUI_APPS_ERROR`. |
| [`tui.apps.compat`](apps/tui.apps.compat.md) | Checks the loaded `TUI_APP_META` against this DABT version (`min_dabt`, `max_dabt`, both inclusive). Returns `1` with the reason in `TUI_APPS_ERROR`. |
| [`tui.apps.cli`](apps/tui.apps.cli.md) | The `dabt app` command line: `install`, `update`, `remove`, `list`, `info`, `run`, `help`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative apps/tui.apps.install.md %}

{% include_relative apps/tui.apps.update.md %}

{% include_relative apps/tui.apps.remove.md %}

{% include_relative apps/tui.apps.list.md %}

{% include_relative apps/tui.apps.info.md %}

{% include_relative apps/tui.apps.run.md %}

{% include_relative apps/tui.apps.meta_load.md %}

{% include_relative apps/tui.apps.compat.md %}

{% include_relative apps/tui.apps.cli.md %}

</div>
<!-- /api -->

## Installing DABT

<!-- api: tui.install.defaults tui.install.detect tui.install.check_dir tui.install.run -->
| Function | Summary |
|---|---|
| [`tui.install.defaults`](apps/tui.install.defaults.md) | Sets the default install locations: `TUI_INSTALL_PREFIX` (`~/.local/share/dabt`), `TUI_INSTALL_CONFIG` (`~/.config/DABT`), `TUI_INSTALL_BINDIR` (`~/.local/bin`). XDG variables are respected. |
| [`tui.install.detect`](apps/tui.install.detect.md) | Prints an existing DABT config home: `~/.config/DABT` if it exists, else `$DABT_HOME` if it is a folder. Returns `1` when there is none. |
| [`tui.install.check_dir`](apps/tui.install.check_dir.md) | Returns `0` when `DIR` is absolute and is a writable folder or can be created. Otherwise returns `1` with the reason in `TUI_INSTALL_ERROR`. |
| [`tui.install.run`](apps/tui.install.run.md) | Installs DABT from a release folder: copies the program to `PREFIX`, the defaults and plugins into `CONFIG`, and links `dabt` into the bin folder. `install.sh` calls it. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative apps/tui.install.defaults.md %}

{% include_relative apps/tui.install.detect.md %}

{% include_relative apps/tui.install.check_dir.md %}

{% include_relative apps/tui.install.run.md %}

</div>
<!-- /api -->

## File sync

Program files (`lib/ bin/ share/ docs/ examples/ VERSION ...`) are always replaced by the release. Config files (`share/defaults/**` → `CONFIG/defaults/`, `share/plugins/*` → `CONFIG/plugins/`) are compared three ways: the checksum DABT recorded when it last wrote the file, the file now, and the release. Files you changed are never overwritten silently.

<!-- api: tui.sync.plan tui.sync.apply tui.sync.program_plan tui.sync.program_apply tui.sync.valid_source tui.sync.report tui.sync.resolve_ui -->
| Function | Summary |
|---|---|
| [`tui.sync.plan`](apps/tui.sync.plan.md) | Compares the config files of a release (`share/defaults/**`, `share/plugins/*`) with the installed ones, using the checksums in `CONFIG/manifest` as the common base. |
| [`tui.sync.apply`](apps/tui.sync.apply.md) | Applies the plan from [`tui.sync.plan`](/api/apps/tui.sync.plan.html) and rewrites `CONFIG/manifest`. |
| [`tui.sync.program_plan`](apps/tui.sync.program_plan.md) | Compares the program files of a release with `PREFIX`. Sets `TUI_SYNC_P_ADD`, `TUI_SYNC_P_UPDATE`, `TUI_SYNC_P_SAME`, `TUI_SYNC_P_REMOVE`. |
| [`tui.sync.program_apply`](apps/tui.sync.program_apply.md) | Applies the program plan: program files are always replaced by the release's, with the old ones copied to `BACKUP_DIR`. |
| [`tui.sync.valid_source`](apps/tui.sync.valid_source.md) | Returns `0` when `SRC` looks like a DABT release (`VERSION`, `lib/tui.sh`, `share/defaults`). |
| [`tui.sync.report`](apps/tui.sync.report.md) | Prints the last plans as a readable list: files added, changed, removed and in conflict. |
| [`tui.sync.resolve_ui`](apps/tui.sync.resolve_ui.md) | Inside the app: asks about each conflict of the current plan in a dialog (override, skip, `.new`, show the differences, same for the rest), then calls `DONE_FN`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative apps/tui.sync.plan.md %}

{% include_relative apps/tui.sync.apply.md %}

{% include_relative apps/tui.sync.program_plan.md %}

{% include_relative apps/tui.sync.program_apply.md %}

{% include_relative apps/tui.sync.valid_source.md %}

{% include_relative apps/tui.sync.report.md %}

{% include_relative apps/tui.sync.resolve_ui.md %}

</div>
<!-- /api -->

## Updating DABT

<!-- api: tui.update.check tui.update.download tui.update.local tui.update.plan tui.update.apply tui.update.cli tui.version.newer tui.action.update_check tui.action.update -->
| Function | Summary |
|---|---|
| [`tui.update.check`](apps/tui.update.check.md) | Asks GitHub for the latest DABT version. |
| [`tui.update.download`](apps/tui.update.download.md) | Downloads and unpacks the latest release into `DIR/src`. Returns `1` with the reason in `TUI_UPDATE_ERROR`. |
| [`tui.update.local`](apps/tui.update.local.md) | Prepares a local update source in `DIR/src` from a release folder, a `.tar.gz`, or a `.dapk` package (verified first). Sets `TUI_UPDATE_SRC_KIND` (`folder`, `archive`, `dapk`). |
| [`tui.update.plan`](apps/tui.update.plan.md) | Compares `SRC` with the installed DABT and fills the plan arrays of `tui.sync.*`. Sets `TUI_UPDATE_GIT=1` when the installed program is a git checkout. |
| [`tui.update.apply`](apps/tui.update.apply.md) | Applies an update: program files (skipped for a git checkout), config files with conflict handling, and `install.meta`. Sets `TUI_UPDATE_RESULT` (lines). |
| [`tui.update.cli`](apps/tui.update.cli.md) | The `dabt update` command line, without a TUI. |
| [`tui.version.newer`](apps/tui.version.newer.md) | Returns `0` when version `A` is newer than `B`, comparing dotted numbers (`0.10.0` is newer than `0.9.2`). |
| [`tui.action.update_check`](apps/tui.action.update_check.md) | Inside the app: checks for an update and offers to download it, or shows a toast that DABT is up to date. In the palette as "DABT: Check for updates". |
| [`tui.action.update`](apps/tui.action.update.md) | Inside the app: downloads the latest release, shows what would change, asks about conflicts, then applies the update. Returns `1` when the download fails. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative apps/tui.update.check.md %}

{% include_relative apps/tui.update.download.md %}

{% include_relative apps/tui.update.local.md %}

{% include_relative apps/tui.update.plan.md %}

{% include_relative apps/tui.update.apply.md %}

{% include_relative apps/tui.update.cli.md %}

{% include_relative apps/tui.version.newer.md %}

{% include_relative apps/tui.action.update_check.md %}

{% include_relative apps/tui.action.update.md %}

</div>
<!-- /api -->

## Security scan

<!-- api: tui.scan.run tui.scan.run_spin tui.scan.print tui.scan.tools tui.scan.install tui.scan.cli -->
| Function | Summary |
|---|---|
| [`tui.scan.run`](apps/tui.scan.run.md) | Security-scans a script or folder for obvious red flags: pipe-to-shell, reverse shells, `rm -rf /`, setuid, secrets, persistence. |
| [`tui.scan.run_spin`](apps/tui.scan.run_spin.md) | Runs [`tui.scan.run`](/api/apps/tui.scan.run.html) behind a spinner (a plain message when stdout is not a terminal). Sets the same variables. |
| [`tui.scan.print`](apps/tui.scan.print.md) | Prints `TUI_SCAN_REPORT` and a summary line. |
| [`tui.scan.tools`](apps/tui.scan.tools.md) | Prints whether ShellCheck and Semgrep are installed, and which package manager was found. |
| [`tui.scan.install`](apps/tui.scan.install.md) | Installs an optional scanner with the system package manager. |
| [`tui.scan.cli`](apps/tui.scan.cli.md) | The `dabt scan` command line: `PATH... [--deep] [--strict]`, `--tools`, `--install TOOL`. |

<div class="api-entries" data-pagefind-ignore="all" markdown="1">

{% include_relative apps/tui.scan.run.md %}

{% include_relative apps/tui.scan.run_spin.md %}

{% include_relative apps/tui.scan.print.md %}

{% include_relative apps/tui.scan.tools.md %}

{% include_relative apps/tui.scan.install.md %}

{% include_relative apps/tui.scan.cli.md %}

</div>
<!-- /api -->
