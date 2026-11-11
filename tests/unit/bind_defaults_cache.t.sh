# bind_defaults_cache.t.sh - tui.bind.defaults parses its XML once per file version: the result is kept as a snapshot
# under $TUI_HOME/cache/keybinds and loaded with one source while the XML is not newer than it.

_bd_file() { # NAME BODY... -> _BD_F: a keybinds file with one <bind> line per argument
	_BD_F="$_T_ROOT/$1.xml"
	shift
	printf '%s\n' "<binds>" "$@" "</binds>" >"$_BD_F"
}

_bd_dump() { # the four default tables, as text
	local k out=""
	for k in $(printf '%s\n' "${!_TUI_BIND_DEF[@]}" | sort); do
		out+="$k=${_TUI_BIND_DEF[$k]}|${_TUI_BIND_DEF_GROUP[$k]:-}|${_TUI_BIND_DEF_DESC[$k]:-}|${_TUI_BIND_DEF_ALWAYS[$k]:-};"
	done
	printf '%s' "$out"
}

_bd_count_parses() { # CMD... -> _BD_PARSES: how many bind lines CMD parsed
	_BD_PARSES=0
	local saved
	saved="$(declare -f _tui_input.attr)"
	_tui_input.attr() {
		[[ "$2" == key ]] && ((_BD_PARSES++))
		_ATTR=""
		[[ "$1" =~ (^|[[:space:]])$2=\"([^\"]*)\" ]] && _ATTR="${BASH_REMATCH[2]}"
		return 0
	}
	"$@"
	eval "$saved"
}

ti_bind_defaults_second_load_comes_from_the_snapshot() {
	_bd_file bd1 '<bind key="ctrl+a" action="x.a" group="g1" desc="A &amp; B"/>' '<bind key="ctrl+b" action="x.b;x.c" group="g2" always="true"/>'
	_bd_count_parses tui.bind.defaults "$_BD_F"
	eq "2" "$_BD_PARSES"
	local first
	first="$(_bd_dump)"
	_TUI_BIND_DEF=() _TUI_BIND_DEF_GROUP=() _TUI_BIND_DEF_DESC=() _TUI_BIND_DEF_ALWAYS=()
	local gen=$_TUI_BIND_GEN
	_bd_count_parses tui.bind.defaults "$_BD_F"
	eq "0" "$_BD_PARSES"
	eq "$first" "$(_bd_dump)"
	eq "$((gen + 1))" "$_TUI_BIND_GEN" # a reload still announces itself
	tui.bind.defaults                  # the real defaults back: the tables are global
}

ti_bind_defaults_reparses_a_file_that_changed() {
	_bd_file bd2 '<bind key="ctrl+a" action="x.a" group="g1"/>'
	tui.bind.defaults "$_BD_F"
	_bd_file bd2 '<bind key="ctrl+a" action="x.a2" group="g1"/>' '<bind key="ctrl+z" action="x.z" group="g3"/>'
	touch -d '+5 seconds' "$_BD_F" # newer than the snapshot, whatever the clock resolution
	_bd_count_parses tui.bind.defaults "$_BD_F"
	eq "2" "$_BD_PARSES"
	eq "x.a2" "${_TUI_BIND_DEF[ctrl + a]}"
	eq "x.z" "${_TUI_BIND_DEF[ctrl + z]}"
	tui.bind.defaults
}

ti_bind_defaults_keeps_files_apart() {
	_bd_file bd3a '<bind key="ctrl+a" action="x.a" group="g1"/>'
	_bd_file bd3b '<bind key="ctrl+b" action="x.b" group="g2"/>'
	tui.bind.defaults "$_T_ROOT/bd3a.xml"
	tui.bind.defaults "$_T_ROOT/bd3b.xml"
	tui.bind.defaults "$_T_ROOT/bd3a.xml"
	eq "x.a" "${_TUI_BIND_DEF[ctrl + a]}"
	eq "" "${_TUI_BIND_DEF[ctrl + b]:-}"
	tui.bind.defaults
}

ti_bind_defaults_works_without_a_cache_home() {
	local saved_home="$TUI_HOME"
	TUI_HOME=""
	_bd_file bd4 '<bind key="ctrl+a" action="x.a" group="g1"/>'
	_bd_count_parses tui.bind.defaults "$_BD_F"
	_bd_count_parses tui.bind.defaults "$_BD_F"
	eq "1" "$_BD_PARSES" # nothing to keep a snapshot in: parsed again, and loaded
	eq "x.a" "${_TUI_BIND_DEF[ctrl + a]}"
	TUI_HOME="$saved_home"
	tui.bind.defaults
}
