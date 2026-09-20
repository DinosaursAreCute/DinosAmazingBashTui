# Plugins

A plugin is a bash file that adds commands, keys, hooks, timers or overlays to any DABT application, and can be listed, enabled, disabled, reloaded, installed and removed while the app runs (Settings > Plugins, the command bar, or `tui.plugin.*`). API table: [../api/reference.md](../api/reference.md#plugins-and-hooks). Source: [../../lib/tui_plugin.sh](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/lib/tui_plugin.sh).

## Where things live

```
~/.config/DABT/                     TUI_HOME
    plugins/                        TUI_PLUGINS_DIR    plugins you installed, shared by every DABT app
    apps/<TUI_APP_NAME>/            TUI_APP_CONF       one folder per application
        dabt.conf                     framework settings (theme, notifications, plugin on/off ...)
        keybinds.xml                  your saved keybinds
        settings.conf                 the application's own settings
        app.meta                      metadata: name, title, description, dabt_version, app_dir, entry, first_run, last_run, runs
        terminal_shortcuts.*          state the terminal_shortcuts plugin needs to restore your terminal
```

Set `TUI_APP_NAME` (and optionally `TUI_APP_TITLE`, `TUI_APP_DESC`, `TUI_APP_ENTRY`) **before** sourcing `tui.sh`. `app.meta` is rewritten by `tui.init` and holds any key you add with `tui.app.meta_set`. Files from the older layout (`~/.config/<app>/dabt.conf`, `keybinds.xml`, `settings.conf`) are moved into the new folder the first time.

Plugins are discovered in: `share/plugins/` (built in), `<app dir>/plugins/` (the application's own), `~/.config/DABT/plugins/` (yours) and any folder in `TUI_PLUGIN_DIRS` (colon separated).

## Writing one

One file `NAME.plugin.sh`, or a folder `NAME/plugin.sh` with assets (find them with `tui.plugin.dir NAME`). Metadata sits in comments at the top:

```bash
# plugin: hello
# title: Hello
# version: 1.0
# description: Says hello.
# author: you
# requires: other_plugin         (enabled first, disabled last)
# default: on                    (state the first time; the user's choice is saved afterwards)

plugin.hello.on_enable() {
    tui.cmd.add hello.say "Hello: say hello" hello_say --group Hello
    tui.bind alt+h hello_say
    tui.hook.on page hello_on_page
    tui.every 30 hello_tick hello_timer
}
plugin.hello.on_disable() { tui.notify "bye" info 2; }     # optional
hello_say() { tui.notify "Hello!" success; }
```

The file is only **sourced** when the plugin is enabled, so a disabled plugin costs nothing. Whatever `on_enable` registers with `tui.cmd.add`, `tui.cmd.provider`, `tui.bind`, `tui.hook.on`, `tui.every` / `tui.after`, `tui.tick.add` and `tui.overlay.add` is remembered and **undone automatically** when the plugin is disabled; for anything else use `tui.plugin.own run 'command to undo it'`. A plugin's commands show `plugin: NAME` in the command bar. Save a plugin's own settings with `tui.plugin.config NAME KEY VALUE` (stored as `plugin.NAME.KEY` in `dabt.conf`). Plugins are trusted code: they run in the app's shell.

An example is in [../../examples/plugins/hello.plugin.sh](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/examples/plugins/hello.plugin.sh); a real one is [../../share/plugins/terminal_shortcuts.plugin.sh](https://github.com/DinosaursAreCute/DinosAmazingBashTui/blob/main/share/plugins/terminal_shortcuts.plugin.sh).

## Hooks

`tui.hook.on EVENT FN` / `tui.hook.off` / `tui.hook.fire EVENT ARGS`. Events: `init` (tui.init done), `ready` (before the first frame), `page FILE` (after each page switch), `resize ROWS COLS`, `key NAME` (before bindings; `FN` returns 0 to **consume** the key), `quit`, `exit` (the terminal is being restored: give things back), `plugin_enabled NAME`, `plugin_disabled NAME`.

## Managing plugins

- **Settings > Plugins** (command bar: "DABT: Plugins"): every detected plugin with state and version. Select one to see its details (state, source, location, file count, folders, size, lines, functions, and what it registered: commands, keybinds, hooks, timers), a **file tree** and, when you pick a file, its **content** (with line numbers). Enter / double-click on a plugin moves into its files; Enter on a folder collapses it. Buttons: enable / disable, reload, install (from a file or folder), remove.
- **Command bar**: "Plugin: enable X" / "Plugin: disable X" for each plugin.
- **Code**: `tui.plugin.list|info|enable|disable|toggle|reload|install|remove|files|stats|root`.

Removing a plugin you installed deletes it from `~/.config/DABT/plugins/`; a built-in or application plugin is only unregistered.

## The terminal_shortcuts plugin

A terminal emulator sees every key before the app, and no escape sequence can override that on purpose (`ctrl+shift+left` is "previous tab" in kitty, `alt+1..9` switch tabs in GNOME Terminal, `page_up` may scroll the scrollback...). The built-in **Terminal shortcuts** plugin (on by default) works on the terminal's own configuration instead:

| Command bar | Does |
|---|---|
| Terminal: what am I running in? | Detects the terminal (env vars, XTVERSION), version, tmux/screen, and what can be freed |
| Terminal: shortcuts the terminal takes | The keys DABT uses that the terminal keeps. kitty: its **real effective keymap** (defaults + your `kitty.conf`); GNOME Terminal: gsettings; tmux: root key table |
| Terminal: check shortcuts (press keys) | A guided test that works in every terminal: press each key; the ones that never arrive are taken |
| Terminal: free shortcuts while DABT runs | kitty: an include file `dabt-shortcuts.conf` with `map KEY no_op` lines + a config reload (needs one `include` line in `kitty.conf`, added after asking and backing it up); GNOME Terminal: `gsettings set ... disabled`; tmux: `unbind-key -T root`. Restored on exit, on disable, and after a crash |
| Terminal: give the shortcuts back | Undo it now |
| Terminal: show config to free shortcuts | The lines for alacritty, wezterm, ghostty, kitty, Windows Terminal ... (copied to the clipboard) |

Settings > Settings has a checkbox **Free terminal shortcuts while DABT runs** (`tui.plugin.config terminal_shortcuts auto_free 1`). kitty, GNOME Terminal (gsettings) and tmux are only used when present. Tests: `tools/debug/terminal_plugin_tests.sh`.
