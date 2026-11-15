# theme_paths.t.sh - `dabt:` paths, and theme load problems that say who asked, once, with a hint.

# _tp_defaults - a fake defaults folder: TUI_DEFAULTS_DIR with glyphs/thin.css and themes/dark.css
_tp_restore() { TUI_DEFAULTS_DIR="$_TP_DEFAULTS_ORIG"; TUI_LOG_DIR="$_TP_LOGDIR_ORIG"; TUI_APP_NAME="$_TP_APP_ORIG"; _TUI_LOG_LV=$_TP_LV_ORIG; _TUI_LOG_DIR_OK=""; _TUI_THEME_CALLER=""; _TUI_THEME_WARNED=(); }
_tp_defaults() {
	[[ -v _TP_DEFAULTS_ORIG ]] || { _TP_DEFAULTS_ORIG="$TUI_DEFAULTS_DIR" _TP_LOGDIR_ORIG="$TUI_LOG_DIR" _TP_APP_ORIG="$TUI_APP_NAME" _TP_LV_ORIG=$_TUI_LOG_LV; } # the runner shares state between tests: every test that calls this ends with _tp_restore
	TUI_DEFAULTS_DIR="$_T_ROOT/tp_defaults_$RANDOM"
	mkdir -p "$TUI_DEFAULTS_DIR/glyphs" "$TUI_DEFAULTS_DIR/themes"
	printf '%s\n' '.progress { fill: "-"; }' >"$TUI_DEFAULTS_DIR/glyphs/thin.css"
	printf '%s\n' '.tp_dark { fg: white; bg: black; }' >"$TUI_DEFAULTS_DIR/themes/dark.css"
}

# _tp_log - fresh log folder; _tp_logtext prints what was logged
_tp_log() {
	TUI_LOG_DIR="$_T_ROOT/tp_log_$RANDOM" TUI_APP_NAME=tp
	_TUI_LOG_DIR_OK="" _TUI_LOG_LV=0
	_TUI_THEME_WARNED=()
	_TUI_THEME_CALLER=""
}
_tp_logtext() { _tui_log.path; [[ -r "$_TUI_LOG_PATH" ]] && printf '%s\n' "$(<"$_TUI_LOG_PATH")"; }

t_dabt_prefix_resolves_to_the_defaults_folder_and_other_paths_stay() {
	_TP_SAVED_DEFAULTS="$TUI_DEFAULTS_DIR"
	TUI_DEFAULTS_DIR=/opt/dabt/share/defaults
	_tui_path_dabt "dabt:glyphs/thin.css"
	eq "/opt/dabt/share/defaults/glyphs/thin.css" "$_DP"
	_tui_path_dabt "themes/x.css"
	eq "themes/x.css" "$_DP"
	_tui_path_dabt "/abs/x.css"
	eq "/abs/x.css" "$_DP"
	TUI_DEFAULTS_DIR="$_TP_SAVED_DEFAULTS"
}

ti_import_of_a_dabt_path_reads_the_default_file() {
	_tp_defaults
	printf '%s\n' '@import "dabt:glyphs/thin.css";' '.tp_own { fg: red; }' >"$_T_ROOT/tp_top.css"
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=() _TUI_G=()
	_tui.theme_parse "$_T_ROOT/tp_top.css"
	_tui.theme_commit
	eq red "${_TUI_CLASS_FG[tp_own]}"
	eq "-" "${_TUI_G[progress.fill]}"
	_tp_restore
}

ti_load_theme_of_a_dabt_path_works() {
	_tp_defaults
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=() _TUI_G=()
	tui.load_theme "dabt:themes/dark.css" 2>/dev/null
	eq white "${_TUI_CLASS_FG[tp_dark]}"
	_tp_restore
}

ti_missing_theme_is_logged_with_its_caller_and_a_did_you_mean() {
	_tp_defaults
	_tp_log
	mkdir -p "$_T_ROOT/tp_app/themes"
	printf '%s\n' '.tp_a { fg: red; }' >"$_T_ROOT/tp_app/themes/theme.css"
	_TUI_THEME_CALLER='<theme src="theme.css"> in page.xml:3'
	tui.load_theme "$_T_ROOT/tp_app/theme.css" 2>/dev/null
	eq "1" "$?"
	local log
	log="$(_tp_logtext)"
	match "$log" 'cannot read .*tp_app/theme\.css'
	match "$log" '<theme src="theme.css"> in page.xml:3'
	match "$log" "did you mean '.*tp_app/themes/theme\.css'"
	_tp_restore
}

ti_missing_import_suggests_the_dabt_copy() {
	_tp_defaults
	_tp_log
	mkdir -p "$_T_ROOT/tp_app2/themes"
	printf '%s\n' '@import "../glyphs/thin.css";' >"$_T_ROOT/tp_app2/themes/theme.css"
	_TUI_THEME_CALLER='tui.theme.set at run.sh:21'
	_tui.theme_parse "$_T_ROOT/tp_app2/themes/theme.css"
	local log
	log="$(_tp_logtext)"
	match "$log" 'cannot read .*glyphs/thin\.css.*@import in .*themes/theme\.css'
	match "$log" 'tui.theme.set at run.sh:21'
	match "$log" 'dabt:glyphs/thin\.css'
	_tp_restore
}

ti_the_same_problem_from_the_same_caller_is_logged_once() {
	_tp_defaults
	_tp_log
	_TUI_THEME_CALLER='<theme> in a.xml:1'
	tui.load_theme "$_T_ROOT/tp_none.css" 2>/dev/null
	tui.load_theme "$_T_ROOT/tp_none.css" 2>/dev/null
	_TUI_THEME_CALLER='<theme> in b.xml:1'
	tui.load_theme "$_T_ROOT/tp_none.css" 2>/dev/null
	local log n=0 line
	log="$(_tp_logtext)"
	while IFS= read -r line; do [[ "$line" == *"cannot read"* ]] && ((n++)); done <<<"$log"
	eq "2" "$n" # one per requesting file
	_tp_restore
}

ti_theme_set_of_a_missing_file_fails_with_the_caller_and_keeps_the_overlay() {
	_tp_defaults
	_tp_log
	_TUI_THEME_OVERLAY="$_T_ROOT/tp_keep.css"
	tui.theme.set "$_T_ROOT/tp_missing.css"
	eq "1" "$?"
	eq "$_T_ROOT/tp_keep.css" "$_TUI_THEME_OVERLAY"
	match "$(_tp_logtext)" 'tui\.theme\.set at .*theme_paths\.t\.sh:[0-9]+'
	_TUI_THEME_OVERLAY=""
	_tp_restore
}

ti_include_of_a_dabt_path_is_read() {
	_tp_defaults
	printf '%s\n' '<pane id="tp_inc"/>' >"$TUI_DEFAULTS_DIR/part.xml"
	printf '%s\n' '<tui>' '  <include src="dabt:part.xml"/>' '</tui>' >"$_T_ROOT/tp_page.xml"
	tui.parse.file "$_T_ROOT/tp_page.xml"
	eq "" "${_P_ERRORS[*]}"
	tui_ops.select "$_P_ROOT" '#tp_inc'
	eq "1" "${#_OP_NODES[@]}"
	_tp_restore
}

ti_validator_reports_a_missing_theme_and_a_missing_import() {
	_tp_defaults
	mkdir -p "$_T_ROOT/tp_v/themes"
	printf '%s\n' '@import "../glyphs/thin.css";' >"$_T_ROOT/tp_v/themes/bad.css"
	printf '%s\n' '@import "dabt:glyphs/thin.css";' >"$_T_ROOT/tp_v/themes/good.css"
	printf '%s\n' '<tui>' '  <theme src="themes/good.css"/>' '  <theme src="dabt:themes/dark.css"/>' '  <theme src="theme.css"/>' '  <theme src="themes/bad.css"/>' '</tui>' >"$_T_ROOT/tp_v/p.xml"
	tui.validate.files "$_T_ROOT/tp_v/p.xml"
	tui.validate.messages
	local out="${_TV_LINES[*]}"
	ok '[[ "$out" == *"theme.css"*"does not exist"* ]]'
	ok '[[ "$out" == *"themes/bad.css"*"imports"*"glyphs/thin.css"* ]]'
	ok '[[ "$out" != *"good.css"* && "$out" != *"dark.css"* ]]'
	_tp_restore
}
