# cmd_load_cache.t.sh - tui.cmd.load parses its XML once per file version: the result is kept as a script of tui.cmd.add
# calls under $TUI_HOME/cache/commands and replayed with one source while the XML is not newer than it.

_cl_file() { # NAME BODY... -> _CL_F: a commands file with one <cmd> line per argument
	_CL_F="$_T_ROOT/$1.xml"
	shift
	printf '%s\n' "<cmds>" "$@" "</cmds>" >"$_CL_F"
}

_cl_count_parses() { # CMD... -> _CL_PARSES: how many cmd lines CMD parsed
	_CL_PARSES=0
	local saved
	saved="$(declare -f _tui_input.attr)"
	_tui_input.attr() { [[ "$2" == id ]] && ((_CL_PARSES++)); _ATTR=""; [[ "$1" =~ (^|[[:space:]])$2=\"([^\"]*)\" ]] && _ATTR="${BASH_REMATCH[2]}"; return 0; }
	"$@"
	eval "$saved"
}

_cl_dump() { printf '%s|%s|%s|%s|%s' "${_TUI_CMD_TITLE[$1]:-}" "${_TUI_CMD_ACTION[$1]:-}" "${_TUI_CMD_GROUP[$1]:-}" "${_TUI_CMD_DESC[$1]:-}" "${_TUI_CMD_WHEN[$1]:-}"; }

ti_cmd_load_second_load_comes_from_the_snapshot() {
	_cl_file cl1 '<cmd id="t.a" title="A &amp; B" action="x.a;x.b c" group="G" desc="d &quot;q&quot;"/>' '<cmd id="t.b" title="B" action="x.z" when="w"/>'
	_cl_count_parses tui.cmd.load "$_CL_F"
	eq "2" "$_CL_PARSES"
	local a b
	a="$(_cl_dump t.a)" b="$(_cl_dump t.b)"
	tui.cmd.remove t.a
	tui.cmd.remove t.b
	_cl_count_parses tui.cmd.load "$_CL_F"
	eq "0" "$_CL_PARSES"
	eq "$a" "$(_cl_dump t.a)"
	eq "$b" "$(_cl_dump t.b)"
	tui.cmd.remove t.a
	tui.cmd.remove t.b
}

ti_cmd_load_reparses_a_file_that_changed() {
	_cl_file cl2 '<cmd id="t.c" title="C" action="x.c"/>'
	tui.cmd.load "$_CL_F"
	_cl_file cl2 '<cmd id="t.c" title="C2" action="x.c2"/>' '<cmd id="t.d" title="D" action="x.d"/>'
	touch -d '+5 seconds' "$_CL_F"
	_cl_count_parses tui.cmd.load "$_CL_F"
	eq "2" "$_CL_PARSES"
	eq "C2" "${_TUI_CMD_TITLE[t.c]}"
	eq "D" "${_TUI_CMD_TITLE[t.d]}"
	tui.cmd.remove t.c
	tui.cmd.remove t.d
}
