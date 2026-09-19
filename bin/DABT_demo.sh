#!/usr/bin/env bash
# markup_demo.sh - launches config/home.xml through the file-based TUI loader.
TUI_APP_NAME=dabt_demo        # user keybinds live in ~/.config/dabt_demo/keybinds.xml
source "$(dirname "$0")/tui.sh"

DEMO_DIR="$(cd "$(dirname "$0")/../config/DABT_demo" && pwd)"

# Re-apply the theme chosen on the Settings page (see settings_callbacks.sh).
_saved_theme="$(sed -n 's/^theme=//p' "${XDG_CONFIG_HOME:-$HOME/.config}/dabt_demo/settings.conf" 2>/dev/null)"
[[ -n "$_saved_theme" && "$_saved_theme" != default && -r "$DEMO_DIR/themes/$_saved_theme.css" ]] \
    && _TUI_THEME_OVERLAY="$DEMO_DIR/themes/$_saved_theme.css"

tui.cmd.load "$DEMO_DIR/commands.xml"       # app commands for the palette (ctrl+p)
tui.start_cached "$DEMO_DIR/home.xml"
