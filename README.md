<div align="center">

# 🦕 D.A.B.T

### DinosAmazingBashTui

**A declarative, file-based terminal UI framework.**
Pure bash + POSIX utilities. No Python, no Node, no ncurses.

[![Release](https://img.shields.io/github/v/release/DinosaursAreCute/DinosAmazingBashTui?include_prereleases&style=for-the-badge&color=2ea043&label=release)](https://github.com/DinosaursAreCute/DinosAmazingBashTui/releases)
[![Bash 5+](https://img.shields.io/badge/bash-5.0%2B-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](#requirements)
[![Dependencies](https://img.shields.io/badge/dependencies-none-blue?style=for-the-badge)](#requirements)
[![Tests](https://img.shields.io/badge/tests-bats-orange?style=for-the-badge)](tests/)

[![Last commit](https://img.shields.io/github/last-commit/DinosaursAreCute/DinosAmazingBashTui?style=flat-square)](https://github.com/DinosaursAreCute/DinosAmazingBashTui/commits/main)
[![Stars](https://img.shields.io/github/stars/DinosaursAreCute/DinosAmazingBashTui?style=flat-square)](https://github.com/DinosaursAreCute/DinosAmazingBashTui/stargazers)
[![Issues](https://img.shields.io/github/issues/DinosaursAreCute/DinosAmazingBashTui?style=flat-square)](https://github.com/DinosaursAreCute/DinosAmazingBashTui/issues)
[![Repo size](https://img.shields.io/github/repo-size/DinosaursAreCute/DinosAmazingBashTui?style=flat-square)](https://github.com/DinosaursAreCute/DinosAmazingBashTui)
[![Made with bash](https://img.shields.io/badge/made%20with-bash-1f425f?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

[**Quick start**](#-quick-start) · [**Features**](#-features) · [**The `dabt` command**](#-the-dabt-command) · [**Plugins**](#-plugins) · [**Docs**](#-documentation) · [**Changelog**](CHANGELOG.md)

![Home](screenshots/default/home.png)

</div>

---

## What is this?

D.A.B.T lets you build multi-page terminal interfaces the way you build a website: write markup, point at a stylesheet, wire up callbacks. The framework handles layout, rendering, focus, mouse support and live background processes, all in bash.

```xml
<tui>
  <script src="callbacks.sh"/>
  <theme src="theme.css"/>

  <pane id="root" split="h">
    <pane id="sidebar" weight="25" title="Menu" border="single" class="sidebar"/>
    <pane id="main"    weight="75" title="Welcome"/>
  </pane>

  <label  id="greeting" pane="main" row="0" text="Hello from DABT!" align="center"/>
  <button id="btn_quit" pane="sidebar" row="5" text="Quit" action="tui.stop" class="danger_button"/>
</tui>
```

```css
.sidebar              { fg: #88c0d0; bg: #2e3440; }
.sidebar:border       { fg: #4c566a; }
.danger_button        { fg: white; bg: #b00020; mods: bold; }
.danger_button:focus  { fg: white; bg: #ff3333; mods: bold; }
```

```bash
#!/usr/bin/env bash
source lib/tui.sh
tui.start "share/demo/home.xml"
```

## 🚀 Quick start

```bash
git clone https://github.com/DinosaursAreCute/DinosAmazingBashTui.git
cd DinosAmazingBashTui

bin/dabt demo        # run the demo straight from the checkout, no install needed
./install.sh         # optional: install the program and config home (asks first)
```

After installing, everything goes through the `dabt` command:

```bash
dabt update          # update to the latest release
dabt update --dev    # update to the current state of main
dabt doctor          # where everything lives, what version is installed
```

No package manager, no build step. Installing copies the program to `~/.local/share/dabt`, the defaults and plugins to `~/.config/DABT` (yours to edit) and links `~/.local/bin/dabt`. Details: [docs/guide/install-and-update.md](docs/guide/install-and-update.md).

## 🧰 The `dabt` command

| Command | What it does |
|---|---|
| `dabt` / `dabt --help` | show help |
| `dabt --demo` | run the demo application |
| `dabt -d` / `doctor` | installed version, locations, install metadata |
| `dabt -v` | print the version |
| `dabt install [opts]` | install this copy (`--prefix`, `--config`, `--bindir`, `--policy`, `--dry-run`, `--yes`) |
| `dabt update` | update to the **latest release** |
| `dabt update --dev` | update to the **current `main`**, even at the same version |
| `dabt update --check` | only check; exit code 10 when an update is available |
| `dabt update --yes --policy override\|skip\|new` | non-interactive; settle conflicts by policy |
| `dabt clear-cache` | delete the page cache in `~/.config/DABT/cache` |
| `dabt reinstall [--yes]` | reinstall from the install source, overriding local changes |
| `dabt uninstall [--yes] [--keep-config]` | remove the program, config home and the `dabt` link |

**Safe updates.** The updater and installer use a three-way file sync (checksum manifest). Before anything is written you see every added, changed and removed file. Files you edited are never overwritten silently: for each conflict choose *override*, *skip*, *write a `.new` file* or *show the differences*. Replaced files are backed up in `~/.config/DABT/backups/`. The same flow is available in the app's command bar (`ctrl+p` → "DABT: Update DABT").

## ✨ Features

| | |
|---|---|
| **Declarative XML markup** | Panes, buttons, inputs and labels in config files, not imperative code |
| **Multi-page navigation** | Link pages like HTML anchors with `page="other.xml"`; pages are cached for instant switching |
| **CSS-like theming** | Reusable `.class` styles with `fg`, `bg`, `mods` and `:focus` / `:border` / `:title` pseudo-states; five built-in themes |
| **Rich widgets** | label, button, checkbox, input, password, multi-line textarea, list, table, select, progress |
| **Text editing engine** | Selection, word jumps, cut / copy / paste, undo / redo, click and drag, double / triple-click |
| **Dialogs & toasts** | `tui.confirm`, `tui.message`, `tui.prompt`, `tui.choose`, `tui.view`, `tui.notify` with six toast positions |
| **Command bar & keybinds** | Searchable command palette, rebindable keys saved per app, footer key bar |
| **Plugin system** | Drop-in `*.plugin.sh` files with hooks, enable / disable / reload at runtime |
| **High-performance scrolling** | Batched AWK-shader viewports: jump-to-click scrollbars, wheel, Vim keys |
| **Live terminal execution** | Stream a real PTY process into a pane with stdin piping, cancel, save, retry |
| **Layout engine** | hsplit / vsplit / grid / tabs, alignment, min / max sizing, `${command}` runtime templates |
| **Terminal renderers** | Standalone `box`, `table`, `gauge`, `hbar`, `tree`, `banner`, CSV charts and more, usable without the TUI |
| **Mouse + keyboard** | Click routing, hover feedback, Tab focus cycling, the app owns every key (ctrl+c copies) |
| **Installer & updater** | Release / dev channels, conflict resolution, backups, reinstall and clean uninstall |

## 🔌 Plugins

A plugin is one bash file that adds commands, keys, hooks, timers or overlays to any DABT app. Plugins live in `~/.config/DABT/plugins/`, are shared by every app, and can be enabled, disabled, reloaded, installed and removed while the app runs (Settings → Plugins, the command bar, or `tui.plugin.*`). Everything a plugin registered is cleaned up automatically when it is removed.

Ships with **`terminal_shortcuts`**: detects your terminal (kitty, GNOME Terminal, tmux, alacritty, wezterm, ghostty, Windows Terminal ...), lists the keys it swallows, temporarily frees them while DABT runs and restores them on exit or after a crash.

See [docs/guide/plugins.md](docs/guide/plugins.md) and [examples/plugins/](examples/plugins/).

## 🖼️ Screenshots

Default theme, generated with `tools/debug/screenshot_all.sh`.

<details open>
<summary><b>Components: every terminal renderer, with fit-to-pane and live tabs</b></summary>

![Components](screenshots/default/components.png)

</details>

<details>
<summary><b>Case Study: real-world layout stress test</b></summary>

![Case Study](screenshots/default/case_study.png)

</details>

<details>
<summary><b>Documentation: one tab per markdown file</b></summary>

![Docs](screenshots/default/docu__doc_tab_3.png)

</details>

<details>
<summary><b>Scrolling: high-performance AWK shader viewports</b></summary>

![Scrolling](screenshots/default/scrolling.png)

</details>

<details>
<summary><b>Monitor: live CPU, memory, load and disk straight from /proc</b></summary>

![Monitor](screenshots/default/monitor.png)

</details>

<details>
<summary><b>Debug: every key and mouse event lights up as you press it</b></summary>

![Keyboard and mouse](screenshots/default/debug_input.png)

</details>

### Themes

Switch the whole app from Settings; themes live in `share/demo/themes/*.css`.

| Default | Ocean | Forest |
|:---:|:---:|:---:|
| ![default](screenshots/default/styles.png) | ![ocean](screenshots/ocean/styles.png) | ![forest](screenshots/forest/styles.png) |

| Sunset | Light |
|:---:|:---:|
| ![sunset](screenshots/sunset/styles.png) | ![light](screenshots/light/styles.png) |

## 📚 Documentation

Start at **[docs/README.md](docs/README.md)** for the architecture overview and a map of everything below.

| | |
|---|---|
| [API reference](docs/api/reference.md) | every function and parameter in one table |
| [API tour](docs/api/README.md) | by task, with examples |
| [Markup](docs/guide/markup.md) | XML page format: panes, grids, tabs, includes, themes |
| [Widgets](docs/guide/widgets.md) | text editing, lists, tables, select, progress |
| [Plugins](docs/guide/plugins.md) | writing and managing plugins, hooks |
| [Input bindings](docs/guide/input-bindings.md) | keyboard / mouse bindings, command bar, footer |
| [Install & update](docs/guide/install-and-update.md) | installer, config home, updates, conflicts |
| [Callbacks & viewports](docs/guide/callbacks-and-viewports.md) | callbacks, hover / focus feedback, scrolling |
| [Design notes](docs/design/) | scrolling shader, pointer tracking, page cache, grid geometry |

## 🏗️ Project structure

```
install.sh  VERSION                    installer entry point, current version
bin/
├── dabt                               the command (see above)
└── DABT_demo.sh                       starts the demo application
lib/                                   the framework
├── tui.sh                             core: layout, widgets, event loop        ├── tui_input.sh  keys and mouse
├── tui_markup.sh / tui_style.sh       XML pages, CSS-like themes               ├── tui_cmd.sh    command bar
├── tui_text.sh / tui_widgets.sh       text editing, list/table/select/...      ├── tui_dialog.sh dialogs, toasts
├── tui_plugin.sh                      plugins and hooks                        ├── tui_home.sh   where files live
├── tui_cache.sh                       page cache
├── tui_sync.sh / tui_install.sh / tui_update.sh   installer + updater (three-way file sync)
└── terminal_controls.sh / terminal_renderer.sh / colors.sh   escape sequences, renderers, colours
share/
├── defaults/                          default keybinds, commands, theme, pages  -> ~/.config/DABT/defaults
├── plugins/                           plugins that ship with DABT               -> ~/.config/DABT/plugins
├── demo/  test_demo/                  the demo app
└── tui.xsd                            editor schema for the markup
docs/  examples/                       documentation, examples
tools/                                 repo only: profiling, screenshots, generators
tests/                                 repo only: bats tests (bats tests/)
```

## Requirements

- **Bash 5.0+** (associative arrays, namerefs, `EPOCHREALTIME`, fractional `read -t`)
- A terminal emulator with mouse support (virtually all modern ones)
- `curl` or `wget` and `tar` for `dabt update` only
- [`bats`](https://github.com/bats-core/bats-core) to run the tests (optional)

That's the whole list.

## Going beyond the demo

Write your own pages (see `share/demo/` for a complete app) and link to them with `page="yourpage.xml"` on a button. Callbacks are plain bash functions: source them with `<script>` and reference them by name in `action="…"` or `submit="…"`.

For a real embedded terminal, point `tui.exec` at any command:

```xml
<script src="my_init.sh"/>
<!-- my_init.sh just contains: tui.exec "htop" "output_pane" "controls_pane" -->
```

The process runs in a real PTY. Pipe stdin to it, cancel it, save its output, or retry it, all from the TUI.

## Contributing

Issues and pull requests are welcome. Run `bats tests/` before submitting; tests mock the network and only write to tmp dirs. Release notes are in the [changelog](CHANGELOG.md).

---

<div align="center">
<sub>Just bash, doing things bash was never meant to do. · <i>I use arch btw :D</i></sub>
</div>
