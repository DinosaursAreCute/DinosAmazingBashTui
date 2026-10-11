#!/usr/bin/env bash
# chrome_cmd.t.sh - lib/chrome/tui_cmd.sh buffer-mode command palette draw path (stage 0.3).

t_palette_draw_appends_to_frame_when_active() {
	_TUI_MODAL="palette"
	_PAL_Q=""
	_PAL_SEL=0
	_PAL_TOP=0
	_PAL_ROWS=3
	_PAL_IDS=()
	_PAL_SGR_BOX="" _PAL_SGR_IN="" _PAL_SGR_SEL="" _PAL_SGR_DIM=""
	_TUI_COLS=80
	_TUI_ROWS=24
	_TUI_FRAME="prefix:"
	_tui_cmd.palette_draw
	ok '[[ "$_TUI_FRAME" == prefix:$'"'"'\e7'"'"'* ]]'
	ok '[[ "$_TUI_FRAME" == *"Command palette"* ]]'
	_TUI_MODAL=""
}

t_palette_draw_appends_nothing_when_not_active() {
	_TUI_MODAL=""
	_TUI_FRAME="prefix:"
	_tui_cmd.palette_draw
	eq "prefix:" "$_TUI_FRAME"
}

t_theme_list_is_built_in_the_calling_shell_sorted_by_name_with_the_app_winning() {
	local d="$_T_ROOT/themes" saved_def="${TUI_DEFAULTS_DIR:-}" saved_app="${TUI_THEMES_DIR:-}" out
	mkdir -p "$d/def/themes" "$d/app"
	: >"$d/def/themes/sunset.css" && : >"$d/def/themes/ocean.css" && : >"$d/app/ocean.css" && : >"$d/app/forest.css"
	TUI_DEFAULTS_DIR="$d/def" TUI_THEMES_DIR="$d/app"
	_tui_api.theme_list # fills _TA_THEMES here: no $( ) and no sort process
	out="${_TA_THEMES[*]}"
	TUI_DEFAULTS_DIR="$saved_def" TUI_THEMES_DIR="$saved_app"
	eq "forest	$d/app/forest.css ocean	$d/app/ocean.css sunset	$d/def/themes/sunset.css" "$out"
}
