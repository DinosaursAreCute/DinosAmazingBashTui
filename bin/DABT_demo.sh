#!/usr/bin/env bash
# DABT_demo.sh - starts the demo application (share/demo/home.xml). `dabt demo` runs this too.
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

tui.cmd.load "$DEMO_DIR/commands.xml" # app commands for the palette (ctrl+p)
tui.start_cached "$DEMO_DIR/home.xml"
