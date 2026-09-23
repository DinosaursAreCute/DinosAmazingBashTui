# Keyboard & mouse bindings

Raw bytes, escape sequences and SGR mouse reports are decoded **once**
(`lib/input/tui_input.sh`) into readable names. Everything the framework does in
response is an ordinary binding to a named action you can rebind.

```bash
tui.bind ctrl+e  on_export --desc "Export"          # global
tui.bind q       tui.action.quit                    # replaces nothing, adds q
tui.bind j       "log_key; tui.action.scroll down"  # chain with ;
tui.bind mouse:right on_context_menu --pane output  # only over/focused in that pane
tui.bind k       on_extra --pass                    # run, THEN the default (scroll up)
tui.bind ctrl+s  on_save --always                   # also fires while typing in an input
tui.unbind j                                        # default comes back
tui.bind.list                                       # everything, defaults included
```

In markup (page-scoped, dropped on page change):
`<bind key="q" action="tui.action.quit" desc="Quit"/>`

## Names
`a` `Q` `1` `/` `space` `enter` `tab` `esc` `backspace` `delete` `insert`
`up down left right` `home end pgup pgdn` `f1`..`f12`.
Modifiers: `ctrl+c`, `alt+x`, `shift+tab`, `ctrl+alt+up` (`shift+q` == `Q`).
Mouse: `mouse:left|middle|right`, `drag:left`, `release`, `wheel:up|down|left|right`,
each optionally `ctrl+`/`alt+`/`shift+` prefixed.

## Inside a handler
`TUI_EVENT_TYPE` (key|mouse), `TUI_EVENT_KEY`, `TUI_EVENT_X/Y`, `TUI_EVENT_PANE`,
`TUI_EVENT_WIDGET`, `TUI_EVENT_BUTTON` - or `tui.get.event`.

## Lookup order
pane-scoped binding -> global binding -> built-in default. A binding stops the
chain unless it has `--pass`. While a text input has focus, *typing keys*
(printable chars, space, backspace, delete, left/right/home/end) skip bindings
and defaults unless bound with `--always`; unbound keys go to the input.

## Built-in actions
`tui.action.quit focus_next focus_prev activate unfocus click`,
`tui.action.scroll up|down|left|right [N]`, `tui.action.page up|down`,
`tui.action.scroll_top`, `tui.action.scroll_bottom`.
Defaults: Tab/Shift+Tab/Up/Down focus, Enter activate, Esc unfocus,
Shift+arrows and h/j/k/l scroll, PgUp/PgDn/Home/End, wheel, left click/drag.

The **Keys** page in the demo shows the live table and lets you bind at runtime.

## Keybind kill-switch (keyboard only)
`ctrl+alt+k` (change with `tui.keys.suspend_key SPEC`) suspends **every** keyboard
binding, user and default, app-wide - it survives page changes. Mouse input is
untouched. A focused text input keeps working (typing, cursor keys, Enter). A red
box in the bottom-right, always drawn on top, shows that the mode is on and which
chord turns it back on. API: `tui.keys.suspend [on|off|toggle]`, `tui.keys.suspended`.
Use it when your own bindings would fire on keys you need to press for something else.

## Repeat coalescing
A wheel spin or a held scroll key sends dozens of identical events. Back-to-back
identical ones that are already buffered are merged into a single dispatch with
`TUI_EVENT_COUNT=n`; `tui.action.scroll`/`page` multiply their step by it, so the
distance is the same but it is one redraw. Only events bound to `tui.action.scroll`
or `tui.action.page` merge - clicks, releases, Enter and typing are never touched.
Tunables: `TUI_INPUT_COALESCE` (0 disables), `TUI_INPUT_COALESCE_MAX`, and the peek
window `TUI_MOUSE_DRAIN_PEEK_TIMEOUT` (must stay > 0).

## Terminal-control mode (pass-through)
`ctrl+alt+p` (change with `tui.passthrough.key SPEC`; `tui.passthrough on|off|toggle`,
`tui.passthrough.active`) hands the mouse and keyboard back to the terminal:
- mouse reporting is switched **off**, so the terminal does native selection, right-click
  menus, URL clicking and its own wheel scrolling (copy with the terminal's own shortcut);
- the screen is **frozen** - no timers, pane redraws or resize relayout, because a repaint
  would drop your selection. Background jobs keep running; their output lands when you leave;
- every key except the chord is ignored, so the terminal's own shortcuts work;
- a small box (drawn once) shows the chord to return. Leaving does one full repaint.
Independent of the keybind kill-switch (`ctrl+alt+k`); both can be on at once.

## Default keybinds live in `share/defaults/keybinds.xml`
Every built-in binding is one `<bind key= action= group=/>` line in that file - edit it to change the
defaults, or point `TUI_DEFAULTS_DIR` at another directory. Each belongs to a **group**, and groups are
opt-out: `tui.defaults.off quit scroll` (app-wide), `tui.defaults.off --page quit`, or
`<tui defaults="-quit,-scroll">` for one page. `tui.defaults.list` shows groups and their keys;
`tui.bind.list` shows each default with its group. Your own `tui.bind` always beats a default.
Groups: `focus`, `pane`, `scroll`, `click`, `wheel`, `paste`, `quit`.

Markup binds are per page; add `scope="global"` to make one survive page changes.

## Keyboard pane focus and jumping
- `f6` / `shift+f6` move the **keyboard pane** (highlighted border, target of `j/k/pgup/...`). `alt+arrows` scroll the pane when it can scroll that way and otherwise move the keyboard pane (`tui.action.scroll_or_pane`).
  Panes with 2+ widgets or a scrollbar take part; single-widget cells are reached with Tab / arrows.
- `tui.action.focus_pane NAME` focuses a pane (its last widget, or scroll focus): `<bind key="alt+n" action="tui.action.focus_pane nav"/>`.
- `tui.action.goto page.xml`: `<bind key="alt+2" action="tui.action.goto components.xml"/>`. `tui.get.pages` lists pages seen by nav buttons.
- Arrow keys move focus **spatially** (`tui.action.focus_dir`), by beam: Left/Right stay on the same screen row (nearest first); Up/Down follow the column beam straight above/below (overlapping columns, nearest row, closest centre). Nothing in that direction = stay put; Tab / shift+tab still walk the whole list.

## Wheel
plain: 3 lines | `shift`: 5 chars sideways | `ctrl`: exactly 1 line | `ctrl+shift`: exactly 1 char.
(Some terminals keep ctrl+wheel for their own zoom and never send it.)

## Paste and clipboard
Bracketed paste is on: a paste arrives as one `paste` event (text in `TUI_EVENT_PASTE`), so newlines can't submit
and letters can't fire bindings. Default: inserted into the focused input (newlines become spaces). Bind your own
with `tui.bind paste fn`. `tui.clipboard.copy TEXT` writes via OSC 52; `tui.clipboard.paste` returns the last paste.

## Your own keybinds: save, load, discard
`tui.bind KEY CMD --user` makes a binding that belongs to the person using the app (code binds and markup
`<bind>` never persist). User binds are global, beat code binds on the same key, and are a **draft** until saved:

```
tui.bind.save       write them to ${XDG_CONFIG_HOME:-~/.config}/${TUI_APP_NAME:-dabt}/keybinds.xml
tui.bind.discard    throw away unsaved changes (reload the saved file)
tui.bind.load [F]   replace the user binds with a file's       tui.bind.dirty   rc 0 while unsaved
tui.unbind KEY --user     tui.bind.reset --user     tui.bind.saved_file
```
The file is loaded automatically on the next start, in the same `<bind .../>` format as `share/defaults/keybinds.xml`
(hand-editable). Set `TUI_APP_NAME` before sourcing `tui.sh` to give your app its own directory. A saved bind whose
command isn't defined right now (its page isn't loaded) is skipped silently (`TUI_LAST_BIND_ERROR`). The **Keys**
page has the Save and Discard buttons and an "unsaved changes" marker.

## Command palette (the command bar)
`ctrl+p` (works while typing) or `:` opens a fuzzy command list; Enter runs the selection, Esc closes, the wheel and
clicks work. It is built on the **command registry**, and DABT's own commands use the same API you do:

```bash
tui.cmd.add deploy "Deploy: staging" "run_deploy staging" --group Deploy --desc "Push the staging build" --key ctrl+d
tui.cmd.load my_commands.xml                # <cmd id= title= action= [group=] [desc=] [when=] [key=]/> per line
tui.cmd.provider my_provider                # function that calls tui.cmd.add for state-dependent commands;
                                            # re-run every time the palette opens
tui.cmd.add save "Save file" "save_it" --when file_is_dirty     # listed only while file_is_dirty succeeds
tui.cmd.run deploy   tui.cmd.list   tui.cmd.remove deploy
```
Defaults live in `share/defaults/commands.xml` (quit, reload, redraw, focus, scroll, save/discard keybinds, kill-switch,
terminal mode) plus providers for **Go to: page**, **Theme: name** (every `themes/*.css`), **Focus pane: name** and
**Default keys: turn 'group' on/off**. The key shown beside a command is looked up from the live bindings.
Turn the palette's own keys off with `tui.defaults.off palette`.

While it is open it owns the keyboard and mouse. The mechanism is public, for your own dialogs: `tui.modal.open NAME
KEYFN DRAWFN [MOUSEFN]`, `tui.modal.close`, and `tui.overlay.add/remove FN` (overlays are redrawn after every render
and once per loop, so a repaint underneath never leaves one half covered). See `lib/chrome/tui_modal.sh`.

## Pages that ship with DABT (Settings and Keybinds)
Every app gets two ready-made pages through the palette: **DABT: Settings** and **DABT: Keybinds** (files in
`share/defaults/pages/`). Settings switches the theme overlay (every `*.css` in `TUI_THEMES_DIR`, which `tui.start` sets
to `<app dir>/themes` when it exists), turns default keybind groups on/off, and sets input behaviour; all of it applies
at once and is saved with `tui.config` (`~/.config/<TUI_APP_NAME>/dabt.conf`, applied by `tui.init`). Keybinds lists every
binding and edits/saves your own. Both have a Back button (`tui.action.back`, key `alt+backspace`).

To use your own pages instead, re-register the command id - nothing else changes:
`tui.cmd.add dabt.settings "Settings" "tui.action.goto my_settings.xml" --group App` (same for `dabt.keybinds`).
`tui.config.get/set/unset` is available to apps for their own saved settings.

## Footer bar (`<footer/>`)
A one-row key-hint strip on the **last terminal row**, like Textual's footer. It is a page-level component, not a pane:
put `<footer/>` anywhere in a page (a shared include is a good place) and it is drawn on the bottom row, and the
outermost pane is made one row shorter to leave room for it.

```xml
<footer/>                                              <!-- Quit, Command bar, and Back when there is a page to go back to -->
<footer items="@tui.action.quit|Quit;ctrl+s|Save;@save_it|Save all|file_dirty"/>
```
Items are `KEY|LABEL[|WHEN_FN]` separated by `;`. `KEY` is shown as written, or `@COMMAND` shows the key currently
bound to that command, looked up live (your own binds, then code binds, then defaults; a chord beats a bare key), so it
follows rebinding; an unbound command is skipped. `WHEN_FN` is an optional predicate. Runtime API:
`tui.footer.show [ITEMS]`, `tui.footer.add KEY LABEL [WHEN]`, `tui.footer.hide`. Style it with the theme classes `.footer`,
`.footer_key` and `.footer_label`. It is an overlay (`tui_modal.sh`), so it is redrawn over every repaint and rebuilt when
bindings, terminal width or page history change.

## Dialogs, prompts and toasts

Confirmations, one-line prompts, list pickers and toast notifications are built on the modal layer (`tui.confirm`, `tui.message`, `tui.prompt`, `tui.choose`, `tui.notify`). While a dialog is open it owns the keyboard and mouse like the palette does. "Ask before quitting" is a setting (`tui.config.set confirm.quit 1`, also a checkbox on the default Settings page). API and flags: [../api/chrome.md](../api/chrome.md#dialogs-and-notifications).
