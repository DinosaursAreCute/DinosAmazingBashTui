# Installing and updating DABT

## Layout: what ships, what you edit

```
<release / checkout>                     PROGRAM (installed to a prefix, replaced by updates)
  install.sh  VERSION  README.md  CHANGELOG.md
  bin/      dabt (the command), DABT_demo.sh
  lib/      the framework: tui.sh and its modules, terminal_*.sh, colors.sh
  share/    defaults/   default keybinds, commands, theme, default pages   -> copied to the config home
            plugins/    plugins that ship with DABT                        -> copied to the config home
            demo/ installer/ test_demo/ tui.xsd
  docs/  examples/
  (tools/ and tests/ stay in the repository: they are for developing DABT)

~/.config/DABT/                          CONFIG HOME (yours: edit freely)
  defaults/   keybinds.xml  commands.xml  theme.css  pages/          TUI_DEFAULTS_DIR
  plugins/    the shipped plugins and yours                            TUI_PLUGINS_DIR
  apps/<app>/ dabt.conf  keybinds.xml  settings.conf  app.meta
  install.meta   manifest   backups/
```

DABT finds its config home in this order: `$TUI_HOME` (override), `~/.config/DABT` if it exists, `$DABT_HOME` if it points at a folder, the location the installer recorded in `<program>/etc/dabt.env`, otherwise the default path (not installed yet: the defaults then come from the program's own `share/defaults`, so a checkout works without installing). `dabt doctor` prints what it found.

## Installing

```bash
git clone https://github.com/DinosaursAreCute/DinosAmazingBashTui.git && cd DinosAmazingBashTui
./install.sh            # shows the locations, asks to continue
./install.sh --yes      # no questions
```

Options: `--prefix DIR` (program, default `~/.local/share/dabt`), `--config DIR` (default `~/.config/DABT`), `--bindir DIR` (where `dabt` is linked, default `~/.local/bin`), `--no-link`, `--policy override|skip|new`, `--dry-run`. With a config home somewhere else, the installer records it in `<prefix>/etc/dabt.env` so `dabt` finds it again; export `DABT_HOME` for other tools. Running the installer on a machine that already has DABT is an update (see below).

## Updating

In the app: command bar (`ctrl+p`) -> **DABT: Check for updates**, then **DABT: Update DABT ...**. From a terminal: `dabt update` (`--check`, `--yes`, `--policy override|skip|new`).

1. The latest release tag is read from the GitHub releases API (`TUI_UPDATE_REPO`; needs curl or wget). With `--dev` (or `TUI_UPDATE_CHANNEL=dev`) the current `TUI_UPDATE_BRANCH` (default main) is used instead, even at the same version.
2. The release is downloaded to a temporary folder and compared with what you have. You are shown **every file that would change**, by category (program files added/changed/removed; config files added/updated/removed; **conflicts**).
3. For each **conflict** you choose: **override** (use the new version), **skip** (keep yours) or **create FILE.new** next to yours so you can merge by hand; "show the differences" runs `diff -u`, and there are "same for all remaining" shortcuts.
4. Only after you confirm are files written. Replaced files are copied to `~/.config/DABT/backups/<timestamp>/`.

How a config file is judged (three-way, using the checksum DABT recorded when it last wrote the file):

| Your file | Release | Result |
|---|---|---|
| missing | has it | **added** |
| untouched | changed | **updated** |
| changed by you | unchanged | **kept** (yours) |
| changed by you | changed | **conflict** (you decide) |
| identical to the release | | nothing to do |
| untouched | file dropped | **removed** |
| changed by you | file dropped | left in place, listed |

A skipped or `.new` conflict stays a conflict on the next update until you resolve it. Program files (the code) are simply replaced. If the program folder is a **git checkout**, program files are not touched (use `git pull`); the config files are still updated the same way.

## Tests

`bats tests/` (bats-core): `home.bats` (where the config home is found), `installer.bats` (install.sh and the library), `updater.bats` (check, download, three-way compare, all conflict answers, the CLI). The network is a mock `curl`, and every folder, `HOME` and `XDG_*` is a temporary directory: the tests never touch your real config or the source tree.
