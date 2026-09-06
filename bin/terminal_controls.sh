#!/usr/bin/env bash
# cursor.sh — Sourceable ANSI/VT100 terminal control library
# Usage: source cursor.sh

# ─────────────────────────────────────────────
#  Cursor Movement
# ─────────────────────────────────────────────

cur.home()       { echo -ne "\e[H"; }                    # Move to (1,1)
cur.goto()       { echo -ne "\e[${1};${2}H"; }           # Move to (line, col)
cur.up()         { echo -ne "\e[${1:-1}A"; }              # Up N lines
cur.down()       { echo -ne "\e[${1:-1}B"; }              # Down N lines
cur.right()      { echo -ne "\e[${1:-1}C"; }              # Right N columns
cur.left()       { echo -ne "\e[${1:-1}D"; }              # Left N columns
cur.next_line()  { echo -ne "\e[${1:-1}E"; }              # Beginning of Nth next line
cur.prev_line()  { echo -ne "\e[${1:-1}F"; }              # Beginning of Nth prev line
cur.col()        { echo -ne "\e[${1}G"; }                 # Move to column N
cur.scroll_up()  { echo -ne "\eM"; }                      # Scroll up one line

cur.save()       { echo -ne "\e7"; }                      # Save position (DEC)
cur.restore()    { echo -ne "\e8"; }                      # Restore position (DEC)
cur.save_sco()   { echo -ne "\e[s"; }                     # Save position (SCO)
cur.restore_sco(){ echo -ne "\e[u"; }                     # Restore position (SCO)

# Request cursor position — result arrives as stdin: ESC[line;colR
cur.request_pos() { echo -ne "\e[6n"; }

# Read cursor position into two variables
cur.get_pos() {
    local _pos
    IFS=';' read -rs -d R -p $'\e[6n' _pos
    _pos="${_pos#*[}"
    printf -v "${1:-CURSOR_LINE}" '%s' "${_pos%;*}"
    printf -v "${2:-CURSOR_COL}"  '%s' "${_pos#*;}"
}

# ─────────────────────────────────────────────
#  Cursor Visibility
# ─────────────────────────────────────────────

cur.hide()       { echo -ne "\e[?25l"; }                  # Hide cursor
cur.show()       { echo -ne "\e[?25h"; }                  # Show cursor

# ─────────────────────────────────────────────
#  Cursor Shape (DECSCUSR — xterm/VTE/etc.)
# ─────────────────────────────────────────────

cur.block()          { echo -ne "\e[2 q"; }               # Steady block
cur.block_blink()    { echo -ne "\e[1 q"; }               # Blinking block
cur.underline()      { echo -ne "\e[4 q"; }               # Steady underline
cur.underline_blink(){ echo -ne "\e[3 q"; }               # Blinking underline
cur.bar()            { echo -ne "\e[6 q"; }               # Steady bar (I-beam)
cur.bar_blink()      { echo -ne "\e[5 q"; }               # Blinking bar
cur.shape_default()  { echo -ne "\e[0 q"; }               # Terminal default

# ─────────────────────────────────────────────
#  Erase / Clear
# ─────────────────────────────────────────────

erase.screen()       { echo -ne "\e[2J"; }                # Entire screen
erase.screen_down()  { echo -ne "\e[0J"; }                # Cursor to end of screen
erase.screen_up()    { echo -ne "\e[1J"; }                # Start of screen to cursor
erase.saved()        { echo -ne "\e[3J"; }                # Erase saved/scrollback lines
erase.line()         { echo -ne "\e[2K"; }                # Entire current line
erase.line_right()   { echo -ne "\e[0K"; }                # Cursor to end of line
erase.line_left()    { echo -ne "\e[1K"; }                # Start of line to cursor
erase.chars()        { echo -ne "\e[${1:-1}X"; }          # Erase N chars from cursor

# Clear screen and scrollback, then home
erase.all()          { echo -ne "\e[2J\e[3J\e[H"; }

# ─────────────────────────────────────────────
#  Line / Character Insert & Delete
# ─────────────────────────────────────────────

line.insert()    { echo -ne "\e[${1:-1}L"; }              # Insert N blank lines
line.delete()    { echo -ne "\e[${1:-1}M"; }              # Delete N lines
char.insert()    { echo -ne "\e[${1:-1}@"; }              # Insert N blank chars
char.delete()    { echo -ne "\e[${1:-1}P"; }              # Delete N chars

# ─────────────────────────────────────────────
#  Scroll Region
# ─────────────────────────────────────────────

scroll.set()     { echo -ne "\e[${1};${2}r"; }            # Set scroll region (top, bottom)
scroll.reset()   { echo -ne "\e[r"; }                     # Reset scroll region to full screen
scroll.up()      { echo -ne "\e[${1:-1}S"; }              # Scroll content up N lines
scroll.down()    { echo -ne "\e[${1:-1}T"; }              # Scroll content down N lines

# ─────────────────────────────────────────────
#  Text Attributes / SGR
# ─────────────────────────────────────────────

style.reset()        { echo -ne "\e[0m"; }
style.bold()         { echo -ne "\e[1m"; }
style.dim()          { echo -ne "\e[2m"; }
style.italic()       { echo -ne "\e[3m"; }
style.underline()    { echo -ne "\e[4m"; }
style.blink()        { echo -ne "\e[5m"; }
style.blink_fast()   { echo -ne "\e[6m"; }
style.reverse()      { echo -ne "\e[7m"; }
style.hidden()       { echo -ne "\e[8m"; }
style.strike()       { echo -ne "\e[9m"; }
style.double_under() { echo -ne "\e[21m"; }
style.overline()     { echo -ne "\e[53m"; }

# Remove specific attributes
style.no_bold()      { echo -ne "\e[22m"; }
style.no_dim()       { echo -ne "\e[22m"; }
style.no_italic()    { echo -ne "\e[23m"; }
style.no_underline() { echo -ne "\e[24m"; }
style.no_blink()     { echo -ne "\e[25m"; }
style.no_reverse()   { echo -ne "\e[27m"; }
style.no_hidden()    { echo -ne "\e[28m"; }
style.no_strike()    { echo -ne "\e[29m"; }

# ─────────────────────────────────────────────
#  Foreground Colors (3/4-bit)
# ─────────────────────────────────────────────

fg.black()       { echo -ne "\e[30m"; }
fg.red()         { echo -ne "\e[31m"; }
fg.green()       { echo -ne "\e[32m"; }
fg.yellow()      { echo -ne "\e[33m"; }
fg.blue()        { echo -ne "\e[34m"; }
fg.magenta()     { echo -ne "\e[35m"; }
fg.cyan()        { echo -ne "\e[36m"; }
fg.white()       { echo -ne "\e[37m"; }
fg.default()     { echo -ne "\e[39m"; }

# Bright foreground
fg.br_black()    { echo -ne "\e[90m"; }
fg.br_red()      { echo -ne "\e[91m"; }
fg.br_green()    { echo -ne "\e[92m"; }
fg.br_yellow()   { echo -ne "\e[93m"; }
fg.br_blue()     { echo -ne "\e[94m"; }
fg.br_magenta()  { echo -ne "\e[95m"; }
fg.br_cyan()     { echo -ne "\e[96m"; }
fg.br_white()    { echo -ne "\e[97m"; }

# 256-color:  fg.256 <0-255>
fg.256()         { echo -ne "\e[38;5;${1}m"; }

# Truecolor:  fg.rgb <r> <g> <b>
fg.rgb()         { echo -ne "\e[38;2;${1};${2};${3}m"; }

# Hex shorthand:  fg.hex "FF5500"
fg.hex() {
    local hex="${1#\#}"
    echo -ne "\e[38;2;$((16#${hex:0:2}));$((16#${hex:2:2}));$((16#${hex:4:2}))m"
}

# ─────────────────────────────────────────────
#  Background Colors (3/4-bit)
# ─────────────────────────────────────────────

bg.black()       { echo -ne "\e[40m"; }
bg.red()         { echo -ne "\e[41m"; }
bg.green()       { echo -ne "\e[42m"; }
bg.yellow()      { echo -ne "\e[43m"; }
bg.blue()        { echo -ne "\e[44m"; }
bg.magenta()     { echo -ne "\e[45m"; }
bg.cyan()        { echo -ne "\e[46m"; }
bg.white()       { echo -ne "\e[47m"; }
bg.default()     { echo -ne "\e[49m"; }

# Bright background
bg.br_black()    { echo -ne "\e[100m"; }
bg.br_red()      { echo -ne "\e[101m"; }
bg.br_green()    { echo -ne "\e[102m"; }
bg.br_yellow()   { echo -ne "\e[103m"; }
bg.br_blue()     { echo -ne "\e[104m"; }
bg.br_magenta()  { echo -ne "\e[105m"; }
bg.br_cyan()     { echo -ne "\e[106m"; }
bg.br_white()    { echo -ne "\e[107m"; }

# 256-color:  bg.256 <0-255>
bg.256()         { echo -ne "\e[48;5;${1}m"; }

# Truecolor:  bg.rgb <r> <g> <b>
bg.rgb()         { echo -ne "\e[48;2;${1};${2};${3}m"; }

# Hex shorthand:  bg.hex "FF5500"
bg.hex() {
    local hex="${1#\#}"
    echo -ne "\e[48;2;$((16#${hex:0:2}));$((16#${hex:2:2}));$((16#${hex:4:2}))m"
}

# ─────────────────────────────────────────────
#  Terminal Modes
# ─────────────────────────────────────────────

term.alt_screen()    { echo -ne "\e[?1049h"; }            # Switch to alt screen buffer
term.main_screen()   { echo -ne "\e[?1049l"; }            # Switch back to main screen
term.wrap_on()       { echo -ne "\e[?7h"; }               # Enable line wrapping
term.wrap_off()      { echo -ne "\e[?7l"; }               # Disable line wrapping
term.bracketed_on()  { echo -ne "\e[?2004h"; }            # Enable bracketed paste
term.bracketed_off() { echo -ne "\e[?2004l"; }            # Disable bracketed paste

# ─────────────────────────────────────────────
#  Window / Title
# ─────────────────────────────────────────────

term.title()     { echo -ne "\e]0;${1}\a"; }              # Set window title
term.icon()      { echo -ne "\e]1;${1}\a"; }              # Set icon name
term.tab_title() { echo -ne "\e]30;${1}\a"; }             # Set tab title (some terms)

# ─────────────────────────────────────────────
#  Bell / Notification
# ─────────────────────────────────────────────

term.bell()      { echo -ne "\a"; }                       # Audible bell
term.flash()     { echo -ne "\e[?5h"; sleep 0.1; echo -ne "\e[?5l"; }  # Visual bell (flash)

# ─────────────────────────────────────────────
#  Hyperlinks (OSC 8 — supported in many modern terminals)
# ─────────────────────────────────────────────

# Usage: link.start "https://example.com"; echo -n "click here"; link.end
link.start()     { echo -ne "\e]8;;${1}\e\\\\"; }
link.end()       { echo -ne "\e]8;;\e\\\\"; }

# One-liner: link "https://example.com" "click here"
link() {
    echo -ne "\e]8;;${1}\e\\\\${2}\e]8;;\e\\\\"
}

# ─────────────────────────────────────────────
#  Convenience Combos
# ─────────────────────────────────────────────

# Clear line and move cursor to start
cl() { echo -ne "\r\e[2K"; }

# Print at specific position: printat <line> <col> <text>
printat() { echo -ne "\e[${1};${2}H${3}"; }

# Styled print: sprint <text>  (pass style calls before it)
sprint() { echo -ne "${*}\e[0m"; }

# Save cursor, do something, restore:  cur.wrap <commands>
cur.wrap() {
    echo -ne "\e7"
    "$@"
    echo -ne "\e8"
}

# ─────────────────────────────────────────────
#  TAB STOPS
# ─────────────────────────────────────────────

tab.set()        { echo -ne "\eH"; }                      # Set tab stop at current column
tab.clear()      { echo -ne "\e[0g"; }                    # Clear tab stop at current column
tab.clear_all()  { echo -ne "\e[3g"; }                    # Clear all tab stops
tab.forward()    { echo -ne "\e[${1:-1}I"; }              # Forward N tab stops (CHT)
tab.backward()   { echo -ne "\e[${1:-1}Z"; }              # Backward N tab stops (CBT)

# ─────────────────────────────────────────────
#  CURSOR EXTRAS
# ─────────────────────────────────────────────

cur.gotof()      { echo -ne "\e[${1};${2}f"; }            # Move to (line, col) — HVP variant
cur.vpa()        { echo -ne "\e[${1}d"; }                 # Move to line N (absolute vertical)
cur.index()      { echo -ne "\eD"; }                      # Index — scroll down one line
cur.newline()    { echo -ne "\eE"; }                      # Next line (CR+LF)
cur.cr()         { echo -ne "\r"; }                       # Carriage return
cur.lf()         { echo -ne "\n"; }                       # Line feed
cur.bs()         { echo -ne "\b"; }                       # Backspace

# ─────────────────────────────────────────────
#  CHARACTER EXTRAS
# ─────────────────────────────────────────────

char.repeat()    { echo -ne "\e[${1:-1}b"; }              # Repeat last printed char N times (REP)

# ─────────────────────────────────────────────
#  TERMINAL MODES (SM / RM)
# ─────────────────────────────────────────────

mode.insert()          { echo -ne "\e[4h"; }              # Insert mode (IRM)
mode.replace()         { echo -ne "\e[4l"; }              # Replace mode
mode.app_cursor_on()   { echo -ne "\e[?1h"; }             # Application cursor keys (DECCKM)
mode.app_cursor_off()  { echo -ne "\e[?1l"; }             # Normal cursor keys
mode.app_keypad()      { echo -ne "\e="; }                # Application keypad (DECKPAM)
mode.num_keypad()      { echo -ne "\e>"; }                # Normal keypad (DECKPNM)
mode.origin_on()       { echo -ne "\e[?6h"; }             # Origin mode (relative to margins)
mode.origin_off()      { echo -ne "\e[?6l"; }             # Absolute coordinates
mode.col_132()         { echo -ne "\e[?3h"; }             # 132-column mode
mode.col_80()          { echo -ne "\e[?3l"; }             # 80-column mode
mode.reverse_on()      { echo -ne "\e[?5h"; }             # Reverse video (screen-wide)
mode.reverse_off()     { echo -ne "\e[?5l"; }             # Normal video
mode.wrap_on()         { echo -ne "\e[?7h"; }             # Enable autowrap (DECAWM)
mode.wrap_off()        { echo -ne "\e[?7l"; }             # Disable autowrap
mode.lr_margin_on()    { echo -ne "\e[?69h"; }            # Enable left/right margins
mode.lr_margin_off()   { echo -ne "\e[?69l"; }            # Disable left/right margins
mode.smooth_scroll()   { echo -ne "\e[?4h"; }             # Smooth scroll
mode.jump_scroll()     { echo -ne "\e[?4l"; }             # Jump scroll
mode.autorepeat_on()   { echo -ne "\e[?8h"; }             # Enable auto-repeat
mode.autorepeat_off()  { echo -ne "\e[?8l"; }             # Disable auto-repeat
mode.blink_cursor_on() { echo -ne "\e[?12h"; }            # Blinking cursor
mode.blink_cursor_off(){ echo -ne "\e[?12l"; }            # Steady cursor
mode.focus_on()        { echo -ne "\e[?1004h"; }          # Report focus in/out events
mode.focus_off()       { echo -ne "\e[?1004l"; }          # Stop reporting focus
mode.sync_start()      { echo -ne "\e[?2026h"; }          # Begin synchronized update
mode.sync_end()        { echo -ne "\e[?2026l"; }          # End synchronized update
mode.alt_screen()      { echo -ne "\e[?1049h"; }          # Alt screen buffer (saves cursor)
mode.main_screen()     { echo -ne "\e[?1049l"; }          # Main screen buffer (restores cursor)
mode.alt_simple()      { echo -ne "\e[?47h"; }            # Alt buffer without save/restore
mode.main_simple()     { echo -ne "\e[?47l"; }            # Main buffer without save/restore
mode.bracketed_on()    { echo -ne "\e[?2004h"; }          # Bracketed paste mode
mode.bracketed_off()   { echo -ne "\e[?2004l"; }

# ─────────────────────────────────────────────
#  MOUSE TRACKING
# ─────────────────────────────────────────────

mouse.on()             { echo -ne "\e[?1000h"; }          # Normal tracking (press/release)
mouse.off()            { echo -ne "\e[?1000l"; }
mouse.highlight_on()   { echo -ne "\e[?1001h"; }          # Hilite tracking
mouse.highlight_off()  { echo -ne "\e[?1001l"; }
mouse.button_on()      { echo -ne "\e[?1002h"; }          # Button-event tracking (drag)
mouse.button_off()     { echo -ne "\e[?1002l"; }
mouse.any_on()         { echo -ne "\e[?1003h"; }          # Any-event tracking (all motion)
mouse.any_off()        { echo -ne "\e[?1003l"; }
mouse.utf8_on()        { echo -ne "\e[?1005h"; }          # UTF-8 encoding
mouse.utf8_off()       { echo -ne "\e[?1005l"; }
mouse.sgr_on()         { echo -ne "\e[?1006h"; }          # SGR encoding (recommended)
mouse.sgr_off()        { echo -ne "\e[?1006l"; }
mouse.urxvt_on()       { echo -ne "\e[?1015h"; }          # urxvt encoding
mouse.urxvt_off()      { echo -ne "\e[?1015l"; }
mouse.pixel_on()       { echo -ne "\e[?1016h"; }          # SGR-pixel encoding
mouse.pixel_off()      { echo -ne "\e[?1016l"; }
mouse.full_on()        { echo -ne "\e[?1003h\e[?1006h"; } # All motion + SGR
mouse.full_off()       { echo -ne "\e[?1003l\e[?1006l"; }

# ─────────────────────────────────────────────
#  DEVICE / TERMINAL REPORTS
# ─────────────────────────────────────────────

report.device_status()   { echo -ne "\e[5n"; }            # → ESC[0n if OK
report.device_attrs()    { echo -ne "\e[c"; }             # Primary DA
report.device_attrs2()   { echo -ne "\e[>c"; }            # Secondary DA
report.device_attrs3()   { echo -ne "\e[=c"; }            # Tertiary DA
report.term_params()     { echo -ne "\e[x"; }             # Terminal parameters
report.term_name()       { echo -ne "\e[>q"; }            # xterm version (XTVERSION)
report.window_title()    { echo -ne "\e[21t"; }           # Report window title
report.icon_title()      { echo -ne "\e[20t"; }           # Report icon title
report.text_area_size()  { echo -ne "\e[18t"; }           # Text area in chars
report.text_area_px()    { echo -ne "\e[14t"; }           # Text area in pixels
report.screen_size()     { echo -ne "\e[19t"; }           # Screen size in chars
report.screen_size_px()  { echo -ne "\e[15t"; }           # Screen size in pixels
report.char_cell_px()    { echo -ne "\e[16t"; }           # Char cell size in pixels

# ─────────────────────────────────────────────
#  WINDOW MANIPULATION (CSI t)
# ─────────────────────────────────────────────

win.deiconify()    { echo -ne "\e[1t"; }                  # Un-minimize
win.iconify()      { echo -ne "\e[2t"; }                  # Minimize
win.move()         { echo -ne "\e[3;${1};${2}t"; }        # Move to (x, y) px
win.resize_px()    { echo -ne "\e[4;${1};${2}t"; }        # Resize to (h, w) px
win.raise()        { echo -ne "\e[5t"; }                  # Raise to front
win.lower()        { echo -ne "\e[6t"; }                  # Push to back
win.refresh()      { echo -ne "\e[7t"; }                  # Refresh
win.resize()       { echo -ne "\e[8;${1};${2}t"; }        # Resize to (rows, cols)
win.maximize()     { echo -ne "\e[9;1t"; }
win.unmaximize()   { echo -ne "\e[9;0t"; }
win.maximize_v()   { echo -ne "\e[9;2t"; }                # Maximize vertically
win.maximize_h()   { echo -ne "\e[9;3t"; }                # Maximize horizontally
win.fullscreen()   { echo -ne "\e[10;1t"; }
win.unfullscreen() { echo -ne "\e[10;0t"; }

# Title stack
term.push_title()  { echo -ne "\e[22t"; }                 # Push title to stack
term.pop_title()   { echo -ne "\e[23t"; }                 # Pop title from stack

# ─────────────────────────────────────────────
#  CHARACTER SETS (SCS)
# ─────────────────────────────────────────────

charset.ascii()        { echo -ne "\e(B"; }               # G0 → ASCII
charset.line_drawing() { echo -ne "\e(0"; }               # G0 → DEC line-drawing
charset.uk()           { echo -ne "\e(A"; }               # G0 → UK (£ replaces #)
charset.g1_ascii()     { echo -ne "\e)B"; }               # G1 → ASCII
charset.g1_drawing()   { echo -ne "\e)0"; }               # G1 → line-drawing
charset.g1_uk()        { echo -ne "\e)A"; }               # G1 → UK
charset.invoke_g0()    { echo -ne "\x0f"; }               # Shift In (SI)
charset.invoke_g1()    { echo -ne "\x0e"; }               # Shift Out (SO)
charset.utf8_on()      { echo -ne "\e%G"; }               # Select UTF-8
charset.utf8_off()     { echo -ne "\e%@"; }               # Select ISO 8859-1
charset.box()          { echo -ne "\e(0${1}\e(B"; }       # Print line-drawing then back

# ─────────────────────────────────────────────
#  CLIPBOARD (OSC 52)
# ─────────────────────────────────────────────

clip.copy() {
    local enc
    enc=$(echo -n "$1" | base64 -w0 2>/dev/null || echo -n "$1" | base64)
    echo -ne "\e]52;c;${enc}\a"
}
clip.copy_primary() {
    local enc
    enc=$(echo -n "$1" | base64 -w0 2>/dev/null || echo -n "$1" | base64)
    echo -ne "\e]52;p;${enc}\a"
}
clip.query()   { echo -ne "\e]52;c;?\a"; }
clip.clear()   { echo -ne "\e]52;c;!\a"; }

# ─────────────────────────────────────────────
#  PRINTER / MEDIA COPY
# ─────────────────────────────────────────────

print.screen()     { echo -ne "\e[i"; }                   # Print screen
print.line()       { echo -ne "\e[1i"; }                  # Print cursor line
print.start()      { echo -ne "\e[5i"; }                  # Start pass-through to printer
print.stop()       { echo -ne "\e[4i"; }                  # Stop pass-through
print.auto_on()    { echo -ne "\e[?5i"; }                 # Auto print mode on
print.auto_off()   { echo -ne "\e[?4i"; }                 # Auto print mode off

# ─────────────────────────────────────────────
#  DYNAMIC COLORS (OSC 10-19, 110-119)
# ─────────────────────────────────────────────

osc.fg_color()       { echo -ne "\e]10;${1}\a"; }         # Set fg:   osc.fg_color "rgb:ff/ff/ff"
osc.bg_color()       { echo -ne "\e]11;${1}\a"; }         # Set bg
osc.cursor_color()   { echo -ne "\e]12;${1}\a"; }         # Set cursor color
osc.highlight_bg()   { echo -ne "\e]17;${1}\a"; }         # Set highlight bg
osc.highlight_fg()   { echo -ne "\e]19;${1}\a"; }         # Set highlight fg
osc.query_fg()       { echo -ne "\e]10;?\a"; }            # Query fg
osc.query_bg()       { echo -ne "\e]11;?\a"; }            # Query bg
osc.query_cursor()   { echo -ne "\e]12;?\a"; }            # Query cursor color
osc.reset_fg()       { echo -ne "\e]110\a"; }             # Reset fg to default
osc.reset_bg()       { echo -ne "\e]111\a"; }             # Reset bg to default
osc.reset_cursor()   { echo -ne "\e]112\a"; }             # Reset cursor color

# Current working directory (OSC 7 — shell integration)
osc.cwd()            { echo -ne "\e]7;file://${HOSTNAME}${1:-$PWD}\a"; }

# Prompt marking (OSC 133 — shell integration)
osc.prompt_start()   { echo -ne "\e]133;A\a"; }           # Prompt start
osc.cmd_start()      { echo -ne "\e]133;B\a"; }           # Command start
osc.cmd_end()        { echo -ne "\e]133;C\a"; }           # Command output end
osc.cmd_exit()       { echo -ne "\e]133;D;${1:-0}\a"; }   # Command exit status

# ─────────────────────────────────────────────
#  INLINE IMAGES
# ─────────────────────────────────────────────

img.iterm2() {                                            # iTerm2 inline image
    [[ -f "$1" ]] || return 1
    local data size
    data=$(base64 -w0 "$1" 2>/dev/null || base64 "$1")
    size=$(wc -c < "$1")
    echo -ne "\e]1337;File=size=${size};inline=1:${data}\a"
}

img.kitty() {                                             # Kitty image protocol (basic)
    [[ -f "$1" ]] || return 1
    local data
    data=$(base64 -w0 "$1" 2>/dev/null || base64 "$1")
    echo -ne "\e_Gf=100,a=T,t=d;${data}\e\\\\"
}

# ─────────────────────────────────────────────
#  HYPERLINK EXTRAS
# ─────────────────────────────────────────────

link.start_id() {                                         # With id for multi-line spans
    echo -ne "\e]8;${1};${2}\e\\\\"
}

# ─────────────────────────────────────────────
#  STYLE EXTRAS
# ─────────────────────────────────────────────

style.fraktur()          { echo -ne "\e[20m"; }           # Fraktur (rarely supported)
style.superscript()      { echo -ne "\e[73m"; }           # Superscript (mintty)
style.subscript()        { echo -ne "\e[74m"; }           # Subscript (mintty)
style.no_overline()      { echo -ne "\e[55m"; }
style.no_superscript()   { echo -ne "\e[75m"; }
style.no_subscript()     { echo -ne "\e[75m"; }

# Underline variants (kitty / VTE / mintty)
style.underline_double() { echo -ne "\e[4:2m"; }          # Double underline
style.underline_curly()  { echo -ne "\e[4:3m"; }          # Curly underline
style.underline_dotted() { echo -ne "\e[4:4m"; }          # Dotted underline
style.underline_dashed() { echo -ne "\e[4:5m"; }          # Dashed underline

# Underline color
style.underline_rgb()     { echo -ne "\e[58;2;${1};${2};${3}m"; }
style.underline_256()     { echo -ne "\e[58;5;${1}m"; }
style.underline_default() { echo -ne "\e[59m"; }          # Reset underline color

# ─────────────────────────────────────────────
#  RESET
# ─────────────────────────────────────────────

term.soft_reset()  { echo -ne "\e[!p"; }                  # Soft reset (DECSTR)
term.full_reset()  { echo -ne "\ec"; }                    # Full reset (RIS)

# ─────────────────────────────────────────────
#  NOTIFICATIONS
# ─────────────────────────────────────────────

term.notify()       { echo -ne "\e]9;${1}\a"; }           # OSC 9 (iterm2 / conemu)
term.notify_urxvt() { echo -ne "\e]777;notify;${1};${2}\a"; }  # OSC 777 (urxvt)

# ─────────────────────────────────────────────
#  CONFORMANCE
# ─────────────────────────────────────────────

compat.vt100()   { echo -ne "\e[61\"p"; }
compat.vt200()   { echo -ne "\e[62\"p"; }
compat.vt300()   { echo -ne "\e[63\"p"; }

# ─────────────────────────────────────────────
#  LEFT/RIGHT SCROLL MARGINS
# ─────────────────────────────────────────────

scroll.set_lr()  { echo -ne "\e[${1};${2}s"; }            # Set left/right margins (needs mode.lr_margin_on)

# ─────────────────────────────────────────────
#  CONVENIENCE EXTRAS
# ─────────────────────────────────────────────

sync() {                                                  # Synchronized output block
    echo -ne "\e[?2026h"
    "$@"
    echo -ne "\e[?2026l"
}

sgr() {                                                   # Raw SGR:  sgr 1 31 42
    local IFS=';'; echo -ne "\e[${*}m"
}

putblock() { echo -ne "\e[${1};${2}H\e[38;2;${3};${4};${5}m█\e[0m"; }
clearrow() { echo -ne "\e[${1};1H\e[2K"; }
fillrow() {
    local row=$1 col=$2 char=$3 count=$4
    echo -ne "\e[${row};${col}H"
    printf "%${count}s" '' | tr ' ' "$char"
}

#!/usr/bin/env bash
# ─────────────────────────────────────────────
#  TERMINAL QUERIES & CONTROLS
# ─────────────────────────────────────────────

# Get terminal size in characters → TERM_ROWS, TERM_COLS
term.size() {
    local _r _c
    read -r _r _c < <(stty size 2>/dev/null || echo "24 80")
    printf -v "${1:-TERM_ROWS}" '%s' "$_r"
    printf -v "${2:-TERM_COLS}" '%s' "$_c"
}

# Get terminal size in pixels → TERM_PX_H, TERM_PX_W
term.size_px() {
    local _resp
    IFS=';' read -rs -d t -p $'\e[14t' _resp 2>/dev/null
    _resp="${_resp#*;}"
    printf -v "${1:-TERM_PX_H}" '%s' "${_resp%;*}"
    printf -v "${2:-TERM_PX_W}" '%s' "${_resp#*;}"
}

# Get character cell size in pixels → CELL_H, CELL_W
term.cell_size() {
    local _resp
    IFS=';' read -rs -d t -p $'\e[16t' _resp 2>/dev/null
    _resp="${_resp#*;}"
    printf -v "${1:-CELL_H}" '%s' "${_resp%;*}"
    printf -v "${2:-CELL_W}" '%s' "${_resp#*;}"
}

# Get screen size in characters → SCREEN_ROWS, SCREEN_COLS
term.screen_size() {
    local _resp
    IFS=';' read -rs -d t -p $'\e[19t' _resp 2>/dev/null
    _resp="${_resp#*;}"
    printf -v "${1:-SCREEN_ROWS}" '%s' "${_resp%;*}"
    printf -v "${2:-SCREEN_COLS}" '%s' "${_resp#*;}"
}

# Get screen size in pixels → SCREEN_PX_H, SCREEN_PX_W
term.screen_size_px() {
    local _resp
    IFS=';' read -rs -d t -p $'\e[15t' _resp 2>/dev/null
    _resp="${_resp#*;}"
    printf -v "${1:-SCREEN_PX_H}" '%s' "${_resp%;*}"
    printf -v "${2:-SCREEN_PX_W}" '%s' "${_resp#*;}"
}

# Get cursor position → CURSOR_LINE, CURSOR_COL
term.cursor_pos() {
    local _pos
    IFS=';' read -rs -d R -p $'\e[6n' _pos
    _pos="${_pos#*[}"
    printf -v "${1:-CURSOR_LINE}" '%s' "${_pos%%;*}"
    printf -v "${2:-CURSOR_COL}"  '%s' "${_pos#*;}"
}

# Get window title → WINDOW_TITLE
term.get_title() {
    local _resp
    read -rs -d $'\e' -p $'\e[21t' _resp 2>/dev/null
    # response is ESC ] l <title> ESC \   — varies by terminal
    read -rs -d $'\\' _resp
    printf -v "${1:-WINDOW_TITLE}" '%s' "${_resp#*l}"
}

# Check device status (returns 0 if terminal is OK)
term.is_ok() {
    local _resp
    read -rs -d n -p $'\e[5n' _resp 2>/dev/null
    [[ "${_resp}" == *"0" ]]
}

term.color_level() {                                      # Detect color depth → TERM_COLORS
    if term.has_truecolor; then TERM_COLORS=16777216
    elif [[ "${TERM}" == *256color* ]]; then TERM_COLORS=256
    elif [[ -n "${TERM}" ]]; then TERM_COLORS=16
    else TERM_COLORS=0; fi
}

# Check truecolor support (boolean)
term.has_truecolor() {
    [[ "${COLORTERM}" =~ ^(truecolor|24bit)$ ]]
}

# Check if running inside tmux
term.is_tmux() {
    [[ -n "${TMUX}" ]]
}

# Check if running inside screen
term.is_screen() {
    [[ "${TERM}" == screen* ]]
}

# Check if running in SSH session
term.is_ssh() {
    [[ -n "${SSH_CONNECTION}" || -n "${SSH_TTY}" ]]
}

# Check if stdout is a terminal (vs pipe/redirect)
term.is_tty() {
    [[ -t 1 ]]
}

# Check if stdin is a terminal
term.is_interactive() {
    [[ -t 0 ]]
}

# Get terminal type/emulator name via DA2 → TERM_NAME
term.identify() {
    local _resp
    read -rs -d c -p $'\e[>c' _resp 2>/dev/null
    printf -v "${1:-TERM_ID}" '%s' "${_resp#*[?}"
}

# Get stty settings dump
term.stty_dump() {
    stty -a 2>/dev/null
}

# Save entire terminal state
term.save_state() {
    _SAVED_STTY=$(stty -g 2>/dev/null)
}

# Restore saved terminal state
term.restore_state() {
    [[ -n "${_SAVED_STTY}" ]] && stty "${_SAVED_STTY}" 2>/dev/null
}

# Enter raw mode (for custom key reading)
term.raw() {
    term.save_state
    stty raw -echo 2>/dev/null
}

# Enter cbreak mode (char-at-a-time, signals still work)
term.cbreak() {
    term.save_state
    stty -icanon -echo min 1 time 0 2>/dev/null
}

# Restore cooked mode
term.cooked() {
    term.restore_state
}

# Disable echo
term.echo_off() {
    stty -echo 2>/dev/null
}

# Enable echo
term.echo_on() {
    stty echo 2>/dev/null
}

# Read a single keypress (returns in KEYPRESS)
term.read_key() {
    local _old
    _old=$(stty -g 2>/dev/null)
    stty raw -echo min 1 time 0 2>/dev/null
    IFS= read -r -n1 "${1:-KEYPRESS}"
    stty "$_old" 2>/dev/null
}

# Read a single keypress with timeout (seconds)
term.read_key_timeout() {
    local _old _timeout="${2:-1}"
    _old=$(stty -g 2>/dev/null)
    stty raw -echo min 0 time $((_timeout * 10)) 2>/dev/null
    IFS= read -r -n1 "${1:-KEYPRESS}"
    stty "$_old" 2>/dev/null
}

# Query background color → TERM_BG (light/dark/unknown)
# Useful for choosing color schemes
term.detect_bg() {
    local _resp _r _g _b
    # OSC 11 query
    echo -ne "\e]11;?\a"
    if IFS=: read -rs -d $'\a' -t 1 _resp 2>/dev/null; then
        _resp="${_resp##*/}"
        _r=$((16#${_resp:0:2}))
        _g=$((16#${_resp:2:2}))
        _b=$((16#${_resp:4:2}))
        local luma=$(( (_r * 299 + _g * 587 + _b * 114) / 1000 ))
        if (( luma > 128 )); then
            printf -v "${1:-TERM_BG}" 'light'
        else
            printf -v "${1:-TERM_BG}" 'dark'
        fi
    else
        printf -v "${1:-TERM_BG}" 'unknown'
    fi
}

# Get number of available colors via tput
term.colors() {
    printf -v "${1:-TERM_COLORS_TPUT}" '%s' "$(tput colors 2>/dev/null || echo 0)"
}

# Check if unicode is supported
term.has_unicode() {
    local _lang="${LANG:-}${LC_ALL:-}${LC_CTYPE:-}"
    [[ "$_lang" == *UTF-8* || "$_lang" == *utf8* ]]
}

# Get process controlling the terminal
term.parent() {
    ps -o comm= -p "$(ps -o ppid= -p $$)" 2>/dev/null
}

pb.init() {
    local rows cols
    read -r rows cols < <(stty size)

    _PB_ROW="$rows"

    # Scroll region = all lines except the last
    echo -ne "\e[1;$((_PB_ROW - 1))r"

    # Move cursor into the scroll region
    echo -ne "\e[$((_PB_ROW - 1));1H"

    # Draw initial empty bar on the reserved bottom line
    echo -ne "\e7"                          # save cursor
    echo -ne "\e[${_PB_ROW};1H\e[2K"       # jump to bottom, clear
    echo -ne "\e8"                          # restore cursor
}

pb.update() {
    local msg="${1}" current="${2}" total="${3}"
    local bar='████████████████████'
    local space='....................'
    local wheel=('\' '|' '/' '-')
    local wi=$((current % 4))
    local pct=$((100 * current / total))
    local bp=$((pct / 5))

    local line="|${bar:0:$bp}$(tput dim)${space:$bp:20}$(tput sgr0)| ${wheel[$wi]} ${pct}% [ ${msg} ] "

    echo -ne "\e7"                          # save cursor
    echo -ne "\e[${_PB_ROW};1H\e[2K"       # jump to bottom, clear
    echo -ne "$(tput setaf 6)${line}$(tput sgr0)"                      # draw bar
    echo -ne "\e8"                          # restore cursor
}

pb.teardown() {
    echo -ne "\e[r"                         # reset scroll region to full screen
    echo -ne "\e[${_PB_ROW};1H\e[2K"       # clear the bar line
    echo -ne "\e[$((_PB_ROW - 1));1H"       # move cursor to last usable line
    unset _PB_ROW
}