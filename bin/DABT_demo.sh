#!/usr/bin/env bash
# DABT_demo.sh - starts the demo application (share/demo/home.xml unless DABT_DEMO_PAGE names another page). `dabt demo` runs this too.
TUI_APP_NAME=dabt_demo # its files live in ~/.config/DABT/apps/dabt_demo/ (settings, keybinds, app.meta)
TUI_APP_TITLE="DABT demo"
TUI_APP_DESC="The showcase application that ships with DinosAmazingBashTui"
TUI_APP_ENTRY="bin/DABT_demo.sh"
# shellcheck source=../lib/tui.sh
source "$(dirname "$0")/../lib/tui.sh"

DEMO_DIR="$(cd "$(dirname "$0")/../share/demo" && pwd)"

# Re-apply the theme chosen on the Settings page (see settings_callbacks.sh).
_saved_theme="$(sed -n 's/^theme=//p' "$TUI_APP_CONF/settings.conf" 2>/dev/null)"
[[ -n "$_saved_theme" && "$_saved_theme" != default && -r "$DEMO_DIR/themes/$_saved_theme.css" ]] &&
	_TUI_THEME_OVERLAY="$DEMO_DIR/themes/$_saved_theme.css"

# The Scrolling page's row count follows the terminal height through an addon file; writing it before the first load builds
# that page once, at its final size, instead of once and again on its first visit.
source "$DEMO_DIR/scroll_callbacks.sh"
read -r _rows _ < <(stty size 2>/dev/null) && scroll_write_rows "${_rows:-0}"

tui.cmd.load "$DEMO_DIR/commands.xml"                    # app commands for the palette (ctrl+p)
tui.start_cached "$DEMO_DIR/${DABT_DEMO_PAGE:-home}.xml" # DABT_DEMO_PAGE=components starts on another page (the profiler does: Home is the heaviest)
