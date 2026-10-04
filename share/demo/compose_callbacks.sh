#!/usr/bin/env bash
# compose_callbacks.sh - Compose demo page: a project board whose views, cards and conditionals are all driven by one
# addon file. The state (view, tasks, workspace settings) is kept in $TUI_APP_CONF/compose.conf; every action rewrites
# $TUI_APP_CONF/addons/compose_state.xml from it - the `test` of the page's view <if>s, the attributes of the Workspace
# <use>, and one card per task appended to its lane - and calls tui.page.refresh, which rebuilds only the panes that
# changed (the typed text of the control panel stays). The addon targets compose.xml only.
# The Addons view copies the ticked example addons from addon_examples/ into the same addons folder.

_CP_READY=0 # the tabs run their action while the page is built; only a visit makes the state real
_CP_VIEW=board
_CP_ENV=dev
_CP_ROLE=guest
_CP_BETA=false
_CP_TASKS=() # "title|owner|prio|done|blocked", text already XML-escaped
_CP_MAX=12

_cp_paths() {
	_CP_CONF="${TUI_APP_CONF:-}/compose.conf"
	_CP_ADDON="${TUI_APP_CONF:-}/addons/compose_state.xml"
}

_cp_seed() {
	_CP_TASKS=("Write release notes|dino|high|false|false" "Fix flaky test||normal|false|true" "Update docs|sam|low|true|false" "Ship v0.1|dino|high|false|false")
}

# _cp_clean TEXT -> _CP_CLEAN : TEXT safe inside a quoted attribute and the conf, shortened to 20 characters. `|` is the
# conf's field separator and `{` `}` would start a template parameter, so they become look-alikes.
_cp_clean() {
	local v="${1//[$'\n\r\t']/ }"
	v="${v:0:20}"
	v="${v//|//}"
	v="${v//\{/(}"
	v="${v//\}/)}"
	v="${v//&/"&amp;"}" # quoted replacements: an unquoted & would stand for the matched text (patsub_replacement)
	v="${v//</"&lt;"}"
	v="${v//>/"&gt;"}"
	_CP_CLEAN="${v//\"/"&quot;"}"
}

# _cp_next VALUE CHOICE... -> _CP_NEXT : the choice after VALUE, wrapping round
_cp_next() {
	local cur="$1"
	shift
	_CP_NEXT="$1"
	while (($#)); do
		[[ "$1" == "$cur" ]] && {
			_CP_NEXT="${2:-$_CP_NEXT}"
			return
		}
		shift
	done
}

# _cp_find_next MODE -> _CP_AT : index of the first task that is not done (MODE "any") or also not blocked ("free"), -1 if none
_cp_find_next() {
	local i f
	_CP_AT=-1
	for i in "${!_CP_TASKS[@]}"; do
		IFS='|' read -ra f <<<"${_CP_TASKS[i]}"
		[[ "${f[3]}" == true ]] && continue
		[[ "$1" == free && "${f[4]}" == true ]] && continue
		_CP_AT=$i
		return
	done
}

# _cp_add TITLE OWNER PRIO BLOCKED : rc 1 when the board is full
_cp_add() {
	((${#_CP_TASKS[@]} >= _CP_MAX)) && return 1
	local title owner
	_cp_clean "$1"
	title="${_CP_CLEAN:-Untitled}"
	[[ -n "${title//[[:space:]]/}" ]] || title=Untitled
	_cp_clean "$2"
	owner="$_CP_CLEAN"
	_CP_TASKS+=("$title|$owner|$3|false|$4")
}

_cp_complete_next() {
	local f
	_cp_find_next free
	((_CP_AT < 0)) && return 1
	IFS='|' read -ra f <<<"${_CP_TASKS[_CP_AT]}"
	_CP_TASKS[_CP_AT]="${f[0]}|${f[1]}|${f[2]}|true|false"
}

_cp_toggle_block_next() {
	local f b=true
	_cp_find_next any
	((_CP_AT < 0)) && return 1
	IFS='|' read -ra f <<<"${_CP_TASKS[_CP_AT]}"
	[[ "${f[4]}" == true ]] && b=false
	_CP_TASKS[_CP_AT]="${f[0]}|${f[1]}|${f[2]}|${f[3]}|$b"
}

_cp_remove_last() {
	((${#_CP_TASKS[@]})) || return 1
	unset "_CP_TASKS[${#_CP_TASKS[@]}-1]"
}

# _cp_render -> _CP_XML, _CP_OPEN, _CP_DONE : the addon that makes the page show the state
_cp_render() {
	local i f cards_todo="" cards_done="" use
	_CP_OPEN=0 _CP_DONE=0
	for i in "${!_CP_TASKS[@]}"; do
		IFS='|' read -ra f <<<"${_CP_TASKS[i]}"
		use="<use template=\"task\" id=\"t$i\" title=\"${f[0]}\" owner=\"${f[1]}\" prio=\"${f[2]}\" done=\"${f[3]}\" blocked=\"${f[4]}\"/>"
		if [[ "${f[3]}" == true ]]; then
			cards_done+="$use"
			_CP_DONE=$((_CP_DONE + 1))
		else
			cards_todo+="$use"
			_CP_OPEN=$((_CP_OPEN + 1))
		fi
	done
	_CP_XML="<addon id=\"compose_state\" target=\"compose.xml\" prefix=\"false\">
  <set ref=\"#view_board\" attr=\"test\" value=\"$_CP_VIEW==board\"/>
  <set ref=\"#view_cond\" attr=\"test\" value=\"$_CP_VIEW==cond\"/>
  <set ref=\"#acct\" attr=\"env\" value=\"$_CP_ENV\"/>
  <set ref=\"#acct\" attr=\"role\" value=\"$_CP_ROLE\"/>
  <set ref=\"#acct\" attr=\"beta\" value=\"$_CP_BETA\"/>"
	[[ -n "$cards_todo" ]] && _CP_XML+="
  <remove ref=\"#lane_todo_empty\"/>
  <append ref=\"#lane_todo\">$cards_todo</append>"
	[[ -n "$cards_done" ]] && _CP_XML+="
  <remove ref=\"#lane_done_empty\"/>
  <append ref=\"#lane_done\">$cards_done</append>"
	_CP_XML+="
</addon>"
}

_cp_load() {
	local k v
	_cp_paths
	_CP_TASKS=()
	[[ -r "$_CP_CONF" ]] || return 1
	while IFS='=' read -r k v; do
		case "$k" in
			view) _CP_VIEW="$v" ;;
			env) _CP_ENV="$v" ;;
			role) _CP_ROLE="$v" ;;
			beta) _CP_BETA="$v" ;;
			task) _CP_TASKS+=("$v") ;;
		esac
	done <"$_CP_CONF"
}

# _cp_save : keep the state and rewrite the addon that makes the page show it
_cp_save() {
	local t out
	_cp_paths
	_cp_render
	out="view=$_CP_VIEW"$'\n'"env=$_CP_ENV"$'\n'"role=$_CP_ROLE"$'\n'"beta=$_CP_BETA"$'\n'
	for t in "${_CP_TASKS[@]}"; do out+="task=$t"$'\n'; done
	[[ -d "${_CP_ADDON%/*}" ]] || mkdir -p "${_CP_ADDON%/*}"
	printf '%s' "$out" >"$_CP_CONF"
	printf '%s\n' "$_CP_XML" >"$_CP_ADDON"
}

# _cp_commit : save, then show the change
_cp_commit() {
	[[ -n "${TUI_APP_CONF:-}" ]] || {
		tui.notify "No app config folder: the state can't be applied here." warn
		return
	}
	_cp_save
	tui.page.refresh
	_cp_sync
}

# _cp_sync : texts of the widgets the current view owns (they are not part of the markup)
_cp_sync() { # the refresh of a shell page rebuilds in the background: a widget not built yet is synced by the visit that follows
	case "$_CP_VIEW" in
		board) [[ -n "${_TUI_W_TYPE[lbl_status]:-}" ]] && tui.update lbl_status "$_CP_OPEN open · $_CP_DONE done" ;;
		addons) [[ -n "${_TUI_W_TYPE[lbl_state]:-}" ]] && _cp_addons_status ;;
	esac
}

compose_visit() {
	_CP_READY=1
	if ! _cp_load; then
		_cp_seed
		_cp_commit
	elif [[ ! -e "$_CP_ADDON" ]]; then
		_cp_commit # state without its addon (deleted by hand): write it again
	else
		_cp_render
	fi
	tui.focus "tab_$_CP_VIEW"
	_cp_sync
}

on_compose_tab() {
	((_CP_READY)) || return 0
	[[ "${1#tab_}" == "$_CP_VIEW" ]] && return 0
	_CP_VIEW="${1#tab_}"
	_cp_commit
}

on_cp_add() {
	local title owner prio blocked flag=false
	tui.get inp_title title
	tui.get inp_owner owner
	tui.get sel_prio prio
	tui.get chk_blocked blocked
	[[ "$blocked" == 1 ]] && flag=true
	_cp_add "$title" "$owner" "${prio:-normal}" "$flag" || {
		tui.notify "The board is full ($_CP_MAX tasks): remove one first." warn
		return
	}
	tui.update inp_title ""
	tui.update inp_owner ""
	_cp_commit
}

on_cp_complete() {
	if _cp_complete_next; then _cp_commit; else tui.notify "No open task that is not blocked." info; fi
}
on_cp_block() {
	if _cp_toggle_block_next; then _cp_commit; else tui.notify "No open task to block." info; fi
}
on_cp_remove() {
	if _cp_remove_last; then _cp_commit; else tui.notify "The board is empty." info; fi
}
on_cp_reset() {
	_cp_seed
	_cp_commit
}

on_cp_env() {
	_cp_next "$_CP_ENV" dev staging prod
	_CP_ENV="$_CP_NEXT"
	_cp_commit
}
on_cp_role() {
	_cp_next "$_CP_ROLE" guest member admin
	_CP_ROLE="$_CP_NEXT"
	_cp_commit
}
on_cp_beta() {
	[[ "$_CP_BETA" == true ]] && _CP_BETA=false || _CP_BETA=true
	_cp_commit
}

# ── Addons view ─────────────────────────────────────────────────────────────────────────────────────────────────────
# Everything below avoids starting processes ($(...), cp, rm): a handler runs while the user waits. A file is "switched
# off" by emptying it - an empty addon file adds nothing - and read back with `[[ -s ]]`.

_CP_EXAMPLES="${BASH_SOURCE[0]%/*}/addon_examples"
_CP_EXAMPLE_NAMES=(banner toolbar retitle shout tidy)

_cp_addons_status() {
	local n active=0 dest="${TUI_APP_CONF:+$TUI_APP_CONF/addons}"
	for n in "${_CP_EXAMPLE_NAMES[@]}"; do
		if [[ -n "$dest" && -s "$dest/$n.xml" ]]; then
			tui.update "chk_$n" 1 # tui.set would not redraw: a visit runs after the first frame
			active=$((active + 1))
		fi
	done
	tui.update lbl_state "$active of ${#_CP_EXAMPLE_NAMES[@]} addons applied to this page"
}

on_addon_apply() {
	local n v content dest="${TUI_APP_CONF:+$TUI_APP_CONF/addons}"
	[[ -n "$dest" ]] || {
		tui.notify "No app config folder: addons can't be applied here." warn
		return
	}
	[[ -d "$dest" ]] || mkdir -p "$dest"
	for n in "${_CP_EXAMPLE_NAMES[@]}"; do
		tui.get "chk_$n" v
		if [[ "$v" == 1 ]]; then
			content="$(<"$_CP_EXAMPLES/$n.xml")" # `$(<file)` reads without a subshell
			printf '%s\n' "$content" >"$dest/$n.xml"
		else
			: >"$dest/$n.xml"
		fi
	done
	tui.page.refresh # only the panes the addons changed are rebuilt: within the 100 ms of a page switch
	_cp_addons_status
}

on_addon_click() { tui.notify "Pressed '$1'" info; }
