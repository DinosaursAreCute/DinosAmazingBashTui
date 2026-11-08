# theme_import.t.sh - `@import "file.css";` in a stylesheet: imported values apply, the importing file's own declarations win.

_imp_write() { # NAME CONTENT -> $_T_ROOT/NAME (parent dirs made)
	[[ "$1" == */* ]] && mkdir -p "$_T_ROOT/${1%/*}"
	printf '%s\n' "$2" >"$_T_ROOT/$1"
}

_imp_load() { # NAME -> parses and commits $_T_ROOT/NAME into fresh tables
	_TUI_CLASS_FG=() _TUI_CLASS_BG=() _TUI_CLASS_MOD=() _TUI_G=()
	_tui.theme_parse "$_T_ROOT/$1"
	_tui.theme_commit
}

ti_import_supplies_values_the_importer_does_not_set() {
	_imp_write base.css '.imp_panel { fg: red; bg: blue; }'
	_imp_write top.css '@import "base.css";
.imp_panel { fg: green; }'
	_imp_load top.css
	eq green "${_TUI_CLASS_FG[imp_panel]}"
	eq blue "${_TUI_CLASS_BG[imp_panel]}"
}

ti_import_accepts_url_form_and_single_line_rules() {
	_imp_write base.css '.imp_a { fg: red; }'
	_imp_write top.css '@import url("base.css");'
	_imp_load top.css
	eq red "${_TUI_CLASS_FG[imp_a]}"
}

ti_import_carries_glyphs_and_variants() {
	_imp_write g.css '.progress { fill: "#"; }
.progress.thin { fill: "-"; }'
	_imp_write top.css '@import "g.css";
.progress.thin { fill: "="; }'
	_imp_load top.css
	eq "#" "${_TUI_G[progress.fill]}"
	eq "=" "${_TUI_G[progress.thin.fill]}"
}

ti_import_path_is_relative_to_the_importing_file() {
	_imp_write sub/base.css '.imp_b { fg: red; }'
	_imp_write sub/mid.css '@import "base.css";'
	_imp_write top.css '@import "sub/mid.css";'
	_imp_load top.css
	eq red "${_TUI_CLASS_FG[imp_b]}"
}

ti_import_accepts_an_absolute_path() {
	_imp_write base.css '.imp_c { fg: red; }'
	_imp_write top.css "@import \"$_T_ROOT/base.css\";"
	_imp_load top.css
	eq red "${_TUI_CLASS_FG[imp_c]}"
}

ti_import_of_a_missing_file_is_skipped_and_the_rest_still_applies() {
	_imp_write top.css '@import "nope.css";
.imp_d { fg: red; }'
	_imp_load top.css
	eq red "${_TUI_CLASS_FG[imp_d]}"
}

ti_import_cycle_terminates() {
	_imp_write a.css '@import "b.css";
.imp_e { fg: red; }'
	_imp_write b.css '@import "a.css";
.imp_f { fg: blue; }'
	_imp_load a.css
	eq red "${_TUI_CLASS_FG[imp_e]}"
	eq blue "${_TUI_CLASS_FG[imp_f]}"
}

ti_import_memoized_theme_reapplies_imported_values() {
	_t_needs_caches || return 0
	_imp_write base.css '.imp_g { bg: blue; }'
	_imp_write top.css '@import "base.css";
.imp_g { fg: green; }'
	_TUI_CLASS_FG=() _TUI_CLASS_BG=()
	_tui.theme_load_file "$_T_ROOT/top.css"
	_TUI_CLASS_FG=() _TUI_CLASS_BG=()
	_tui.theme_load_file "$_T_ROOT/top.css"
	eq green "${_TUI_CLASS_FG[imp_g]}"
	eq blue "${_TUI_CLASS_BG[imp_g]}"
}

ti_import_editing_the_imported_file_invalidates_the_memo() {
	_t_needs_caches || return 0
	_TUI_CACHE_TRUSTED=0
	_imp_write base.css '.imp_h { bg: blue; }'
	_imp_write top.css '@import "base.css";'
	_tui.theme_load_file "$_T_ROOT/top.css"
	_imp_write base.css '.imp_h { bg: red; }'
	touch -d @4102444800 "$_T_ROOT/base.css" # 2100: newer than the memo stamp
	_TUI_CLASS_BG=()
	_tui.theme_load_file "$_T_ROOT/top.css"
	eq red "${_TUI_CLASS_BG[imp_h]}"
}

ti_import_every_shipped_stylesheet_import_resolves_inside_share_defaults() {
	local f line imp dir bad="" listed
	listed=$'\n'"$(_tui_sync.config_list "$REPO")"$'\n' # what an install copies
	while IFS= read -r f; do
		dir="${f%/*}"
		while IFS= read -r line; do
			[[ "$line" =~ ^@import[[:space:]]+(url\()?\"([^\"]+)\" ]] || continue
			imp="$(cd "$dir" && realpath -m "${BASH_REMATCH[2]}")"
			imp="${imp#"$REPO"/share/}"
			[[ "$listed" == *$'\n'"$imp"$'\n'* ]] || bad+="${f##*/}->${BASH_REMATCH[2]} "
		done <"$f"
	done < <(printf '%s\n' "$REPO"/share/defaults/*.css "$REPO"/share/defaults/*/*.css)
	eq "" "$bad"
}
