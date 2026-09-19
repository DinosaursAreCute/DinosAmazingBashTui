# Terminal controls reference

Generated from `bin/terminal_controls.sh` by `scripts/gen_terminal_controls_doc.sh` - do not edit by hand.

Stateless helpers that print escape sequences (`echo -ne`). They are usable on their own (`source bin/terminal_controls.sh`) and are what the TUI core is built on. Arguments are positional; `[N]` = optional (defaults to 1 where relevant). Functions whose Description is empty are queries or wrappers: read the source next to the function.


## cur.*

| Function | Args | Description |
|---|---|---|
| `cur.home` |  | Move to (1,1) |
| `cur.goto` | $1 $2 | Move to (line, col) |
| `cur.up` | $1 | Up N lines |
| `cur.down` | $1 | Down N lines |
| `cur.right` | $1 | Right N columns |
| `cur.left` | $1 | Left N columns |
| `cur.next_line` | $1 | Beginning of Nth next line |
| `cur.prev_line` | $1 | Beginning of Nth prev line |
| `cur.col` | $1 | Move to column N |
| `cur.scroll_up` |  | Scroll up one line |
| `cur.save` |  | Save position (DEC) |
| `cur.restore` |  | Restore position (DEC) |
| `cur.save_sco` |  | Save position (SCO) |
| `cur.restore_sco` |  | Restore position (SCO) |
| `cur.request_pos` |  |  |
| `cur.get_pos` |  |  |
| `cur.hide` |  | Hide cursor |
| `cur.show` |  | Show cursor |
| `cur.block` |  | Steady block |
| `cur.block_blink` |  | Blinking block |
| `cur.underline` |  | Steady underline |
| `cur.underline_blink` |  | Blinking underline |
| `cur.bar` |  | Steady bar (I-beam) |
| `cur.bar_blink` |  | Blinking bar |
| `cur.shape_default` |  | Terminal default |
| `cur.wrap` |  |  |
| `cur.gotof` | $1 $2 | Move to (line, col) - HVP variant |
| `cur.vpa` | $1 | Move to line N (absolute vertical) |
| `cur.index` |  | Index - scroll down one line |
| `cur.newline` |  | Next line (CR+LF) |
| `cur.cr` |  | Carriage return |
| `cur.lf` |  | Line feed |
| `cur.bs` |  | Backspace |

## erase.*

| Function | Args | Description |
|---|---|---|
| `erase.screen` |  | Entire screen |
| `erase.screen_down` |  | Cursor to end of screen |
| `erase.screen_up` |  | Start of screen to cursor |
| `erase.saved` |  | Erase saved/scrollback lines |
| `erase.line` |  | Entire current line |
| `erase.line_right` |  | Cursor to end of line |
| `erase.line_left` |  | Start of line to cursor |
| `erase.chars` | $1 | Erase N chars from cursor |
| `erase.all` |  |  |

## line.*

| Function | Args | Description |
|---|---|---|
| `line.insert` | $1 | Insert N blank lines |
| `line.delete` | $1 | Delete N lines |

## char.*

| Function | Args | Description |
|---|---|---|
| `char.insert` | $1 | Insert N blank chars |
| `char.delete` | $1 | Delete N chars |
| `char.repeat` | $1 | Repeat last printed char N times (REP) |

## scroll.*

| Function | Args | Description |
|---|---|---|
| `scroll.set` | $1 $2 | Set scroll region (top, bottom) |
| `scroll.reset` |  | Reset scroll region to full screen |
| `scroll.up` | $1 | Scroll content up N lines |
| `scroll.down` | $1 | Scroll content down N lines |
| `scroll.set_lr` | $1 $2 | Set left/right margins (needs mode.lr_margin_on) |

## style.*

| Function | Args | Description |
|---|---|---|
| `style.reset` |  |  |
| `style.bold` |  |  |
| `style.dim` |  |  |
| `style.italic` |  |  |
| `style.underline` |  |  |
| `style.blink` |  |  |
| `style.blink_fast` |  |  |
| `style.reverse` |  |  |
| `style.hidden` |  |  |
| `style.strike` |  |  |
| `style.double_under` |  |  |
| `style.overline` |  |  |
| `style.no_bold` |  |  |
| `style.no_dim` |  |  |
| `style.no_italic` |  |  |
| `style.no_underline` |  |  |
| `style.no_blink` |  |  |
| `style.no_reverse` |  |  |
| `style.no_hidden` |  |  |
| `style.no_strike` |  |  |
| `style.fraktur` |  | Fraktur (rarely supported) |
| `style.superscript` |  | Superscript (mintty) |
| `style.subscript` |  | Subscript (mintty) |
| `style.no_overline` |  |  |
| `style.no_superscript` |  |  |
| `style.no_subscript` |  |  |
| `style.underline_double` |  | Double underline |
| `style.underline_curly` |  | Curly underline |
| `style.underline_dotted` |  | Dotted underline |
| `style.underline_dashed` |  | Dashed underline |
| `style.underline_rgb` | $1 $2 $3 |  |
| `style.underline_256` | $1 |  |
| `style.underline_default` |  | Reset underline color |

## fg.*

| Function | Args | Description |
|---|---|---|
| `fg.black` |  |  |
| `fg.red` |  |  |
| `fg.green` |  |  |
| `fg.yellow` |  |  |
| `fg.blue` |  |  |
| `fg.magenta` |  |  |
| `fg.cyan` |  |  |
| `fg.white` |  |  |
| `fg.default` |  |  |
| `fg.br_black` |  |  |
| `fg.br_red` |  |  |
| `fg.br_green` |  |  |
| `fg.br_yellow` |  |  |
| `fg.br_blue` |  |  |
| `fg.br_magenta` |  |  |
| `fg.br_cyan` |  |  |
| `fg.br_white` |  |  |
| `fg.256` | $1 |  |
| `fg.rgb` | $1 $2 $3 |  |
| `fg.hex` |  |  |

## bg.*

| Function | Args | Description |
|---|---|---|
| `bg.black` |  |  |
| `bg.red` |  |  |
| `bg.green` |  |  |
| `bg.yellow` |  |  |
| `bg.blue` |  |  |
| `bg.magenta` |  |  |
| `bg.cyan` |  |  |
| `bg.white` |  |  |
| `bg.default` |  |  |
| `bg.br_black` |  |  |
| `bg.br_red` |  |  |
| `bg.br_green` |  |  |
| `bg.br_yellow` |  |  |
| `bg.br_blue` |  |  |
| `bg.br_magenta` |  |  |
| `bg.br_cyan` |  |  |
| `bg.br_white` |  |  |
| `bg.256` | $1 |  |
| `bg.rgb` | $1 $2 $3 |  |
| `bg.hex` |  |  |

## term.*

| Function | Args | Description |
|---|---|---|
| `term.alt_screen` |  | Switch to alt screen buffer |
| `term.main_screen` |  | Switch back to main screen |
| `term.wrap_on` |  | Enable line wrapping |
| `term.wrap_off` |  | Disable line wrapping |
| `term.bracketed_on` |  | Enable bracketed paste |
| `term.bracketed_off` |  | Disable bracketed paste |
| `term.title` | $1 | Set window title |
| `term.icon` | $1 | Set icon name |
| `term.tab_title` | $1 | Set tab title (some terms) |
| `term.bell` |  | Audible bell |
| `term.flash` |  | Visual bell (flash) |
| `term.push_title` |  | Push title to stack |
| `term.pop_title` |  | Pop title from stack |
| `term.soft_reset` |  | Soft reset (DECSTR) |
| `term.full_reset` |  | Full reset (RIS) |
| `term.notify` | $1 | OSC 9 (iterm2 / conemu) |
| `term.notify_urxvt` | $1 $2 | OSC 777 (urxvt) |
| `term.size` |  |  |
| `term.size_px` |  |  |
| `term.cell_size` |  |  |
| `term.screen_size` |  |  |
| `term.screen_size_px` |  |  |
| `term.cursor_pos` |  |  |
| `term.get_title` |  |  |
| `term.is_ok` |  |  |
| `term.color_level` |  | Detect color depth → TERM_COLORS |
| `term.has_truecolor` |  |  |
| `term.is_tmux` |  |  |
| `term.is_screen` |  |  |
| `term.is_ssh` |  |  |
| `term.is_tty` |  |  |
| `term.is_interactive` |  |  |
| `term.identify` |  |  |
| `term.stty_dump` |  |  |
| `term.save_state` |  |  |
| `term.restore_state` |  |  |
| `term.raw` |  |  |
| `term.cbreak` |  |  |
| `term.cooked` |  |  |
| `term.echo_off` |  |  |
| `term.echo_on` |  |  |
| `term.read_key` |  |  |
| `term.read_key_timeout` |  |  |
| `term.detect_bg` |  |  |
| `term.colors` |  |  |
| `term.has_unicode` |  |  |
| `term.parent` |  |  |

## link.*

| Function | Args | Description |
|---|---|---|
| `link.start` | $1 |  |
| `link.end` |  |  |
| `link.start_id` |  | With id for multi-line spans |

## Misc helpers

| Function | Args | Description |
|---|---|---|
| `link` |  |  |
| `cl` |  |  |
| `printat` | $1 $2 $3 |  |
| `sprint` |  |  |
| `sync` |  | Synchronized output block |
| `sgr` |  | Raw SGR:  sgr 1 31 42 |
| `putblock` | $1 $2 $3 $4 $5 |  |
| `clearrow` | $1 |  |
| `fillrow` |  |  |

## tab.*

| Function | Args | Description |
|---|---|---|
| `tab.set` |  | Set tab stop at current column |
| `tab.clear` |  | Clear tab stop at current column |
| `tab.clear_all` |  | Clear all tab stops |
| `tab.forward` | $1 | Forward N tab stops (CHT) |
| `tab.backward` | $1 | Backward N tab stops (CBT) |

## mode.*

| Function | Args | Description |
|---|---|---|
| `mode.insert` |  | Insert mode (IRM) |
| `mode.replace` |  | Replace mode |
| `mode.app_cursor_on` |  | Application cursor keys (DECCKM) |
| `mode.app_cursor_off` |  | Normal cursor keys |
| `mode.app_keypad` |  | Application keypad (DECKPAM) |
| `mode.num_keypad` |  | Normal keypad (DECKPNM) |
| `mode.origin_on` |  | Origin mode (relative to margins) |
| `mode.origin_off` |  | Absolute coordinates |
| `mode.col_132` |  | 132-column mode |
| `mode.col_80` |  | 80-column mode |
| `mode.reverse_on` |  | Reverse video (screen-wide) |
| `mode.reverse_off` |  | Normal video |
| `mode.wrap_on` |  | Enable autowrap (DECAWM) |
| `mode.wrap_off` |  | Disable autowrap |
| `mode.lr_margin_on` |  | Enable left/right margins |
| `mode.lr_margin_off` |  | Disable left/right margins |
| `mode.smooth_scroll` |  | Smooth scroll |
| `mode.jump_scroll` |  | Jump scroll |
| `mode.autorepeat_on` |  | Enable auto-repeat |
| `mode.autorepeat_off` |  | Disable auto-repeat |
| `mode.blink_cursor_on` |  | Blinking cursor |
| `mode.blink_cursor_off` |  | Steady cursor |
| `mode.focus_on` |  | Report focus in/out events |
| `mode.focus_off` |  | Stop reporting focus |
| `mode.sync_start` |  | Begin synchronized update |
| `mode.sync_end` |  | End synchronized update |
| `mode.alt_screen` |  | Alt screen buffer (saves cursor) |
| `mode.main_screen` |  | Main screen buffer (restores cursor) |
| `mode.alt_simple` |  | Alt buffer without save/restore |
| `mode.main_simple` |  | Main buffer without save/restore |
| `mode.bracketed_on` |  | Bracketed paste mode |
| `mode.bracketed_off` |  |  |

## mouse.*

| Function | Args | Description |
|---|---|---|
| `mouse.on` |  | Normal tracking (press/release) |
| `mouse.off` |  |  |
| `mouse.highlight_on` |  | Hilite tracking |
| `mouse.highlight_off` |  |  |
| `mouse.button_on` |  | Button-event tracking (drag) |
| `mouse.button_off` |  |  |
| `mouse.any_on` |  | Any-event tracking (all motion) |
| `mouse.any_off` |  |  |
| `mouse.utf8_on` |  | UTF-8 encoding |
| `mouse.utf8_off` |  |  |
| `mouse.sgr_on` |  | SGR encoding (recommended) |
| `mouse.sgr_off` |  |  |
| `mouse.urxvt_on` |  | urxvt encoding |
| `mouse.urxvt_off` |  |  |
| `mouse.pixel_on` |  | SGR-pixel encoding |
| `mouse.pixel_off` |  |  |
| `mouse.full_on` |  | All motion + SGR |
| `mouse.full_off` |  |  |

## report.*

| Function | Args | Description |
|---|---|---|
| `report.device_status` |  | → ESC[0n if OK |
| `report.device_attrs` |  | Primary DA |
| `report.device_attrs2` |  | Secondary DA |
| `report.device_attrs3` |  | Tertiary DA |
| `report.term_params` |  | Terminal parameters |
| `report.term_name` |  | xterm version (XTVERSION) |
| `report.window_title` |  | Report window title |
| `report.icon_title` |  | Report icon title |
| `report.text_area_size` |  | Text area in chars |
| `report.text_area_px` |  | Text area in pixels |
| `report.screen_size` |  | Screen size in chars |
| `report.screen_size_px` |  | Screen size in pixels |
| `report.char_cell_px` |  | Char cell size in pixels |

## win.*

| Function | Args | Description |
|---|---|---|
| `win.deiconify` |  | Un-minimize |
| `win.iconify` |  | Minimize |
| `win.move` | $1 $2 | Move to (x, y) px |
| `win.resize_px` | $1 $2 | Resize to (h, w) px |
| `win.raise` |  | Raise to front |
| `win.lower` |  | Push to back |
| `win.refresh` |  | Refresh |
| `win.resize` | $1 $2 | Resize to (rows, cols) |
| `win.maximize` |  |  |
| `win.unmaximize` |  |  |
| `win.maximize_v` |  | Maximize vertically |
| `win.maximize_h` |  | Maximize horizontally |
| `win.fullscreen` |  |  |
| `win.unfullscreen` |  |  |

## charset.*

| Function | Args | Description |
|---|---|---|
| `charset.ascii` |  | G0 → ASCII |
| `charset.line_drawing` |  | G0 → DEC line-drawing |
| `charset.uk` |  | G0 → UK (£ replaces #) |
| `charset.g1_ascii` |  | G1 → ASCII |
| `charset.g1_drawing` |  | G1 → line-drawing |
| `charset.g1_uk` |  | G1 → UK |
| `charset.invoke_g0` |  | Shift In (SI) |
| `charset.invoke_g1` |  | Shift Out (SO) |
| `charset.utf8_on` |  | Select UTF-8 |
| `charset.utf8_off` |  | Select ISO 8859-1 |
| `charset.box` | $1 | Print line-drawing then back |

## clip.*

| Function | Args | Description |
|---|---|---|
| `clip.copy` |  |  |
| `clip.copy_primary` |  |  |
| `clip.query` |  |  |
| `clip.clear` |  |  |

## print.*

| Function | Args | Description |
|---|---|---|
| `print.screen` |  | Print screen |
| `print.line` |  | Print cursor line |
| `print.start` |  | Start pass-through to printer |
| `print.stop` |  | Stop pass-through |
| `print.auto_on` |  | Auto print mode on |
| `print.auto_off` |  | Auto print mode off |

## osc.*

| Function | Args | Description |
|---|---|---|
| `osc.fg_color` | $1 | Set fg:   osc.fg_color "rgb:ff/ff/ff" |
| `osc.bg_color` | $1 | Set bg |
| `osc.cursor_color` | $1 | Set cursor color |
| `osc.highlight_bg` | $1 | Set highlight bg |
| `osc.highlight_fg` | $1 | Set highlight fg |
| `osc.query_fg` |  | Query fg |
| `osc.query_bg` |  | Query bg |
| `osc.query_cursor` |  | Query cursor color |
| `osc.reset_fg` |  | Reset fg to default |
| `osc.reset_bg` |  | Reset bg to default |
| `osc.reset_cursor` |  | Reset cursor color |
| `osc.cwd` | $1 |  |
| `osc.prompt_start` |  | Prompt start |
| `osc.cmd_start` |  | Command start |
| `osc.cmd_end` |  | Command output end |
| `osc.cmd_exit` | $1 | Command exit status |

## img.*

| Function | Args | Description |
|---|---|---|
| `img.iterm2` |  | iTerm2 inline image |
| `img.kitty` |  | Kitty image protocol (basic) |

## compat.*

| Function | Args | Description |
|---|---|---|
| `compat.vt100` |  |  |
| `compat.vt200` |  |  |
| `compat.vt300` |  |  |

## pb.*

| Function | Args | Description |
|---|---|---|
| `pb.init` |  |  |
| `pb.update` |  |  |
| `pb.teardown` |  |  |
