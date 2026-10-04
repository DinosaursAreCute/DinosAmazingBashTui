#!/usr/bin/env bash
# tui_store.sh - page-state store: what a page keeps across page switches and, for persist="disk", across runs
# (stage 3D of docs/concepts/markup-v2-implementation-plan.md).
#
#   <input keep_value="true"/>     the widget's value, cursor, scroll and selection survive leaving the page
#   <pane keep_collapsed="true"/>  collapsed / expanded survives (parsed by tui_collapse.sh)
#   <pane keep_size="true"/>       the pane's size after a resize survives
#   <tui keep_state="true">        all of the above for every widget and pane of the page (and pane scroll offsets)
#   persist="session|disk"         session is the default; disk implies the keep flags and also writes the fields to a file
#   keep_focus="true"              a focused widget with it keeps the focus when the next page has the same id
#   <tui focus_on_enter="ID|keep|first">  where focus lands on entry: first (default), the last focused id of this page, an ID
#
# One associative array, _TUI_STORE["PAGE|ID|FIELD"]=VALUE. PAGE is the page file's basename; a '%' or '|' inside PAGE
# or ID is written as %25 / %7C, so ids never collide. Fields:
#   value     _TUI_W_VALUE                      cursor  _TXC
#   scroll    list/table _WXTOP, text widgets "_TXT _TXS", panes "_TUI_P_SOFF_V _TUI_P_SOFF_H"
#   sel       _WXSEL (list, table, select)      collapsed  1|0 (a collapsible pane)
#   size      the pane's parent's size specs (space separated, collapsed panes at their expanded spec); only while resized
# What each widget type keeps: _TUI_STORE_FIELDS[TYPE] (tui.store.register_type adds one). A field FIELD is read by
# _tui_store.get.FIELD ID (sets _SF, rc 1 = nothing to keep) and written by _tui_store.put.FIELD ID VALUE; a widget with
# a field of its own defines the pair.
#
# Disk: fields of items marked persist="disk" are mirrored in _TUI_STORE_FILE and written to $TUI_HOME/state/store when
# something changed (page leave, app exit, tui.store.flush). The file is data only: the first line is "# dabt-state 1",
# then one line per entry, PAGE TAB ID TAB FIELD TAB VALUE, with \\ \t \n \r escaped in every column. It is read line by
# line with `read -r` and unescaped by parameter expansion; nothing in it is ever sourced or evaluated. Lines with the
# wrong column count, a field the store does not know, or more than 64 KiB are skipped. The file is loaded once, on the
# first store use, and its entries merge into _TUI_STORE when the page they belong to is restored.
#
# Seams: tui.goto calls _tui_store.save_page (and writes the file when it changed) before tui.reset_ui and _tui_store.restore_page after the page is loaded;
# tui.page.refresh does both around the rebuilt panes; tui.start restores once after the first load. The first restore
# of a page also snapshots its defaults (_TUI_STORE_DEFAULT, same keys), which a restore never overwrites and a reset
# returns to.
#   tui.page.reset [PAGE]   tui.page.reset_field ID   tui.page.reset_all   tui.page.resettable
#
# Page-local keep flags are _TUI_W_KEEP / _TUI_P_KEEP_SIZE / _TUI_P_KEEP_COLLAPSED / _TUI_P_KEEP_STATE: _TUI_P_ and
# _TUI_W_ variables, so the page cache snapshots and replays them with everything else.
# requires:

declare -gA _TUI_STORE=() _TUI_STORE_DEFAULT=() _TUI_STORE_DEFAULTED=()
declare -gA _TUI_W_KEEP=() _TUI_P_KEEP_SIZE=()
declare -g _TUI_P_KEEP_STATE=""
declare -gA _TUI_STORE_FIELDS=(
	[input]="value cursor scroll" [password]="value cursor scroll" [textarea]="value cursor scroll"
	[checkbox]="value" [select]="value sel" [list]="sel scroll" [table]="sel scroll" [progress]="value"
)
declare -g _SE="" _SK="" _SP="" _SF="" _SFL=""
declare -gA _TUI_STORE_FILE=() _TUI_W_DISK=() _TUI_P_DISK=() _TUI_W_KEEPFOCUS=()
declare -g _TUI_STORE_LOADED="" _TUI_STORE_DIRTY="" _TUI_STORE_ARMED="" _TUI_P_DISK_STATE="" _TUI_P_FOCUS_ON_ENTER=""

# ── the store ─────────────────────────────────────────────────────────────

# _tui_store.key PAGE ID FIELD -> _SK
_tui_store.key() {
	local p="${1//%/%25}" i="${2//%/%25}"
	p="${p//|/%7C}" i="${i//|/%7C}"
	_SK="$p|$i|$3"
}

# _tui_store.prefix PAGE [ID] -> _SK: the key prefix of a page (or of one id)
_tui_store.prefix() {
	local p="${1//%/%25}" i
	p="${p//|/%7C}"
	_SK="$p|"
	[[ -n "${2+x}" ]] || return 0
	i="${2//%/%25}"
	_SK+="${i//|/%7C}|"
}

# tui.store.set PAGE ID FIELD VALUE
tui.store.set() {
	[[ -n "$_TUI_STORE_LOADED" ]] || _tui_store.load_disk
	_tui_store.key "$1" "$2" "$3"
	_TUI_STORE["$_SK"]="$4"
}

# tui.store.get PAGE ID FIELD -> REPLY (rc 1 when absent)
tui.store.get() {
	[[ -n "$_TUI_STORE_LOADED" ]] || _tui_store.load_disk
	_tui_store.key "$1" "$2" "$3"
	[[ -n "${_TUI_STORE["$_SK"]+x}" ]] || return 1
	REPLY="${_TUI_STORE["$_SK"]}"
}

# tui.store.unset PAGE [ID [FIELD]] - drops one field, one id's fields or a whole page
tui.store.unset() {
	local k pre
	if [[ -n "${3+x}" ]]; then
		_tui_store.key "$1" "$2" "$3"
		unset '_TUI_STORE["$_SK"]'
		return 0
	fi
	if [[ -n "${2+x}" ]]; then _tui_store.prefix "$1" "$2"; else _tui_store.prefix "$1"; fi
	pre="$_SK"
	for k in "${!_TUI_STORE[@]}"; do
		[[ "$k" == "$pre"* ]] && unset '_TUI_STORE["$k"]'
	done
	return 0
}

# tui.store.has PAGE [ID] - rc 0 when anything is stored for the page (or the id)
tui.store.has() {
	local k pre
	if [[ -n "${2+x}" ]]; then _tui_store.prefix "$1" "$2"; else _tui_store.prefix "$1"; fi
	pre="$_SK"
	for k in "${!_TUI_STORE[@]}"; do
		[[ "$k" == "$pre"* ]] && return 0
	done
	return 1
}

# tui.store.register_type TYPE FIELD... - which fields a widget type keeps (fields without an accessor are skipped)
tui.store.register_type() {
	local t="$1"
	shift
	_TUI_STORE_FIELDS[$t]="$*"
}

# ── build ─────────────────────────────────────────────────────────────────

# _tui_store.build_widget ID KEEP PERSIST / build_pane ID KEEP PERSIST / build_page KEEP PERSIST FOCUS_ON_ENTER - the
# markup build steps. persist="disk" implies keeping (unless keep is "false"); build_focus ID marks keep_focus.
_tui_store.build_widget() {
	[[ "$2" != false ]] || return 0
	[[ "$2" == true || "${3:-}" == disk ]] || return 0
	_ps.widgets.set "$1" keep 1
	[[ "${3:-}" == disk ]] && _TUI_W_DISK[$1]=1
	return 0
}
_tui_store.build_pane() {
	[[ "$2" != false ]] || return 0
	[[ "$2" == true || "${3:-}" == disk ]] || return 0
	_ps.panes.set "$1" keep_size 1
	if [[ "${3:-}" == disk ]]; then
		_ps.panes.set "$1" keep_collapsed 1
		_ps.panes.set "$1" disk 1
	fi
	return 0
}
_tui_store.build_page() {
	_TUI_P_FOCUS_ON_ENTER="${3:-}"
	[[ "${1:-}" != false ]] || return 0
	[[ "${1:-}" == true || "${2:-}" == disk ]] || return 0
	_TUI_P_KEEP_STATE=1
	[[ "${2:-}" == disk ]] && _TUI_P_DISK_STATE=1
	return 0
}
_tui_store.build_focus() { _TUI_W_KEEPFOCUS[$1]=1; }

# _tui_store.clear - tui.reset_ui: the keep flags belong to the page that was built
_tui_store.clear() {
	_TUI_W_KEEP=() _TUI_P_KEEP_SIZE=() _TUI_P_KEEP_STATE="" _TUI_W_DISK=() _TUI_P_DISK=() _TUI_P_DISK_STATE=""
	_TUI_W_KEEPFOCUS=() _TUI_P_FOCUS_ON_ENTER=""
}

# ── fields ────────────────────────────────────────────────────────────────

_tui_store.get.value() { [[ -n "${_TUI_W_VALUE[$1]+x}" ]] && _SF="${_TUI_W_VALUE[$1]}"; }
_tui_store.put.value() { _TUI_W_VALUE[$1]="$2"; }
_tui_store.get.cursor() { [[ -n "${_TXC[$1]+x}" ]] && _SF="${_TXC[$1]}"; }
_tui_store.put.cursor() {
	_TXC[$1]="$2"
	_tui_text.norm "$1"
}
_tui_store.get.sel() { [[ -n "${_WXSEL[$1]+x}" ]] && _SF="${_WXSEL[$1]}"; }
_tui_store.put.sel() {
	local v="$2"
	_tui_wx.arr "$1"
	((${#_WXA[@]} && v >= ${#_WXA[@]})) && v=$((${#_WXA[@]} - 1))
	_WXSEL[$1]="$v"
}
_tui_store.get.scroll() {
	local t="${_TUI_W_TYPE[$1]:-}"
	case "$t" in
		"") _SF="${_TUI_P_SOFF_V[$1]:-0} ${_TUI_P_SOFF_H[$1]:-0}" ;;
		list | table) _SF="${_WXTOP[$1]:-0}" ;;
		input | password | textarea) _SF="${_TXT[$1]:-0} ${_TXS[$1]:-0}" ;;
		*) return 1 ;;
	esac
}
_tui_store.put.scroll() {
	local a b
	read -r a b <<<"$2"
	case "${_TUI_W_TYPE[$1]:-}" in
		"") _TUI_P_SOFF_V[$1]="$a" _TUI_P_SOFF_H[$1]="${b:-0}" ;;
		list | table) _WXTOP[$1]="$a" ;;
		*) _TXT[$1]="$a" _TXS[$1]="${b:-0}" ;;
	esac
}
_tui_store.get.collapsed() {
	[[ -n "${_TUI_P_COLLAPSIBLE[$1]:-}" ]] || return 1
	[[ -n "${_TUI_P_COLLAPSED[$1]:-}" ]] && _SF=1 || _SF=0
}
_tui_store.put.collapsed() {
	((${2:-0})) && _tui_collapse.flip "$1" 1 || _tui_collapse.flip "$1" 0
	_CL_CHANGED=()
	return 0
}
_tui_store.get.size() {
	local p i
	local -a spec ch
	_tui_resize.parent "$1" || return 1
	p="$_RZ_P"
	[[ -n "${_TUI_P_WEIGHTS0[$p]+x}" ]] || return 1
	read -ra spec <<<"${_TUI_P_WEIGHTS[$p]}"
	read -ra ch <<<"${_TUI_P_CHILDREN[$p]}"
	for i in "${!ch[@]}"; do
		[[ -n "${_TUI_P_COLLAPSED[${ch[i]}]:-}" ]] && spec[i]="${_TUI_P_COLLAPSE_SAVED[${ch[i]}]:-${spec[i]}}"
	done
	_SF="${spec[*]}"
}
_tui_store.put.size() {
	_tui_resize.parent "$1" && _tui_store.put_weights "$_RZ_P" "$2"
}

# _tui_store.put_weights SPLIT "SPECS" - SPLIT's size specs, panes that are collapsed now keep their collapsed size and
# remember the given spec as the one to expand to. The weights before are what tui.resize.reset goes back to.
_tui_store.put_weights() {
	local p="$1" i c
	local -a spec ch cur
	read -ra spec <<<"$2"
	read -ra ch <<<"${_TUI_P_CHILDREN[$p]:-}"
	read -ra cur <<<"${_TUI_P_WEIGHTS[$p]:-}"
	((${#spec[@]} == ${#ch[@]} && ${#cur[@]} == ${#ch[@]})) || return 1
	[[ -n "${_TUI_P_WEIGHTS0[$p]+x}" ]] || _TUI_P_WEIGHTS0[$p]="${_TUI_P_WEIGHTS[$p]}"
	for i in "${!ch[@]}"; do
		c="${ch[i]}"
		if [[ -n "${_TUI_P_COLLAPSED[$c]:-}" ]]; then
			_ps.panes.set "$c" collapse_saved "${spec[i]}"
			spec[i]="${cur[i]}"
		fi
	done
	_ps.panes.set "$p" weights "${spec[*]}"
}

# _tui_store.unsize SPLIT - back to the weights before the first resize
_tui_store.unsize() {
	[[ -n "${_TUI_P_WEIGHTS0[$1]+x}" ]] || return 1
	local w="${_TUI_P_WEIGHTS0[$1]}"
	_tui_store.put_weights "$1" "$w"
	unset '_TUI_P_WEIGHTS0[$1]'
}

# _tui_store.fields ID -> _SFL: the fields the page keeps for ID (a widget by type, a pane by its keep flags)
_tui_store.fields() {
	local id="$1" t="${_TUI_W_TYPE[$1]:-}"
	_SFL=""
	if [[ -n "$t" ]]; then
		[[ -n "${_TUI_W_KEEP[$id]:-}" || -n "$_TUI_P_KEEP_STATE" ]] && _SFL="${_TUI_STORE_FIELDS[$t]:-}"
		return 0
	fi
	[[ -n "${_TUI_P_KEEP_COLLAPSED[$id]:-}" || -n "$_TUI_P_KEEP_STATE" ]] && _SFL="collapsed "
	[[ -n "${_TUI_P_KEEP_SIZE[$id]:-}" || -n "$_TUI_P_KEEP_STATE" ]] && _SFL+="size "
	[[ -n "$_TUI_P_KEEP_STATE" ]] && _SFL+="scroll"
	return 0
}

# _tui_store.active - rc 0 when the built page keeps anything
_tui_store.active() {
	[[ -n "$_TUI_P_KEEP_STATE" ]] || ((${#_TUI_W_KEEP[@]} || ${#_TUI_P_KEEP_SIZE[@]} || ${#_TUI_P_KEEP_COLLAPSED[@]}))
}

# _tui_store.ids -> _SIDS: every widget, then every pane
_tui_store.ids() { _SIDS=("${_TUI_W_ORDER[@]}" "${_TUI_P_ALL[@]}"); }
declare -ga _SIDS=()

# _tui_store.page -> _SP
_tui_store.page() { _SP="${_TUI_MARKUP_FILE##*/}"; }

# _tui_store.owner ID -> _SP: the store page key of ID. With a live shell (lib/markup/tui_shell.sh) the widgets and panes the
# shell built are keyed by the shell file's name, the ones of the page by the page's.
_tui_store.owner() {
	if [[ -n "${_TUI_SHELL_FILE:-}" && -z "${_TUI_PAGE_IDS[$1]+x}" ]]; then _SP="${_TUI_SHELL_FILE##*/}"; else _SP="${_TUI_MARKUP_FILE##*/}"; fi
}

# ── save / restore ───────────────────────────────────────────────────────

# _tui_store.save_page - the current page's kept fields into the store (tui.goto: before tui.reset_ui)
_tui_store.save_page() {
	[[ -n "${_TUI_MARKUP_FILE:-}" ]] || return 0
	_tui_store.active || return 0
	local id f page
	_tui_store.ids
	for id in "${_SIDS[@]}"; do
		((_SHL_SOFT)) && [[ -z "${_TUI_PAGE_IDS[$id]+x}" ]] && continue # a page switch inside a shell leaves the shell's state alone
		_tui_store.owner "$id"
		page="$_SP"
		_tui_store.fields "$id"
		for f in $_SFL; do _tui_store.save_field "$page" "$id" "$f"; done
	done
	return 0
}

# _tui_store.save_field PAGE ID FIELD - one live field into the store (and into the disk image when ID is persisted)
_tui_store.save_field() {
	if "_tui_store.get.$3" "$2" 2>/dev/null; then
		tui.store.set "$1" "$2" "$3" "$_SF"
		_tui_store.disk_set "$1" "$2" "$3" "$_SF"
	else
		tui.store.unset "$1" "$2" "$3"
		_tui_store.disk_unset "$1" "$2" "$3"
	fi
}

# _tui_store.save_widget ID - one widget's (or pane's) kept fields into the store
_tui_store.save_widget() {
	local f page
	_tui_store.owner "$1"
	page="$_SP"
	_tui_store.fields "$1"
	for f in $_SFL; do _tui_store.save_field "$page" "$1" "$f"; done
}

# _tui_store.capture - the first time a page is seen: its kept fields as built, the defaults a reset returns to
_tui_store.capture() {
	local id f page
	_tui_store.page
	page="$_SP"
	local shell_page="${_TUI_SHELL_FILE##*/}" fresh_page=1 fresh_shell=1
	[[ -z "${_TUI_STORE_DEFAULTED[$page]:-}" ]] || fresh_page=0
	[[ -n "$shell_page" && -z "${_TUI_STORE_DEFAULTED[$shell_page]:-}" ]] || fresh_shell=0
	((fresh_page || fresh_shell)) || return 0
	((fresh_page)) && _TUI_STORE_DEFAULTED[$page]=1
	((fresh_shell)) && _TUI_STORE_DEFAULTED[$shell_page]=1
	_tui_store.ids
	for id in "${_SIDS[@]}"; do
		_tui_store.owner "$id"
		page="$_SP"
		[[ -n "${_TUI_SHELL_FILE:-}" && "$page" == "$shell_page" ]] && ((! fresh_shell)) && continue
		[[ "$page" == "${_TUI_MARKUP_FILE##*/}" ]] && ((! fresh_page)) && continue
		_tui_store.fields "$id"
		for f in $_SFL; do
			[[ "$f" == size ]] && continue # the default size is the weights before the first resize (_TUI_P_WEIGHTS0)
			if "_tui_store.get.$f" "$id" 2>/dev/null; then
				_tui_store.key "$page" "$id" "$f"
				_TUI_STORE_DEFAULT["$_SK"]="$_SF"
			fi
		done
	done
	return 0
}

# _tui_store.restore_widget ID PASS - the stored fields of ID (PASS size: only the size field, else all the others)
_tui_store.restore_widget() {
	local id="$1" f page
	_tui_store.owner "$id"
	page="$_SP"
	_tui_store.fields "$id"
	for f in $_SFL; do
		[[ "$f" == size ]] && [[ "${2:-}" != size ]] && continue
		[[ "$f" != size ]] && [[ "${2:-}" == size ]] && continue
		tui.store.get "$page" "$id" "$f" || continue
		"_tui_store.put.$f" "$id" "$REPLY" 2>/dev/null
	done
	return 0
}

# _tui_store.restore_page - the stored fields into the page that was just built (tui.goto: after the load). Collapsed
# states first, then the sizes, which have to know which panes are collapsed.
_tui_store.restore_page() {
	[[ -n "${_TUI_MARKUP_FILE:-}" ]] || return 0
	_tui_store.active || return 0
	_tui_store.capture
	_tui_store.merge_disk
	_TUI_STORE_ARMED=1
	_tui_store.page
	tui.store.has "$_SP" || { [[ -n "${_TUI_SHELL_FILE:-}" ]] && tui.store.has "${_TUI_SHELL_FILE##*/}"; } || return 0
	local id pass
	_tui_store.ids
	for pass in all size; do
		for id in "${_SIDS[@]}"; do
			((_SHL_SOFT)) && [[ -z "${_TUI_PAGE_IDS[$id]+x}" ]] && continue
			_tui_store.restore_widget "$id" "$pass"
		done
	done
	_tui.epoch_bump layout
	_tui.epoch_bump widgets
	return 0
}

# ── reset ─────────────────────────────────────────────────────────────────

# _tui_store.reset_item ID PASS - ID's kept fields back to the captured defaults (PASS as in restore_widget)
_tui_store.reset_item() {
	local id="$1" f
	_tui_store.owner "$id"
	_tui_store.fields "$id"
	for f in $_SFL; do
		if [[ "$f" == size ]]; then
			[[ "${2:-}" == size ]] && _tui_store.unsize_chain "$id"
			continue
		fi
		[[ "${2:-}" == size ]] && continue
		_tui_store.key "$_SP" "$id" "$f"
		[[ -n "${_TUI_STORE_DEFAULT["$_SK"]+x}" ]] && "_tui_store.put.$f" "$id" "${_TUI_STORE_DEFAULT["$_SK"]}" 2>/dev/null
	done
	return 0
}

# _tui_store.unsize_chain ID - the sizes of the splits above ID back to what they were before the first resize
_tui_store.unsize_chain() {
	local node="$1" p
	while _tui_resize.parent "$node"; do
		p="$_RZ_P"
		_tui_store.unsize "$p"
		node="$p"
	done
	return 0
}

# _tui_store.reset_done - lay out again, run on_resize callbacks, repaint
_tui_store.reset_done() {
	_tui.epoch_bump layout
	_tui.epoch_bump widgets
	_tui_resize.commit
}

# tui.page.reset [PAGE] - forgets the stored state of PAGE (default: the current page) and, for the current page, puts
# every kept widget and pane back to its first-build value, selection, scroll, collapsed state and size.
tui.page.reset() {
	local cur id pass p
	_tui_store.page
	cur="$_SP"
	tui.store.unset "${1:-$cur}"
	_tui_store.disk_drop "${1:-$cur}"
	[[ -z "${1:-}" || "$1" == "$cur" ]] || return 0
	_tui_resize.snap
	_tui_store.ids
	for pass in all size; do
		for id in "${_SIDS[@]}"; do _tui_store.reset_item "$id" "$pass"; done
	done
	for p in "${!_TUI_P_WEIGHTS0[@]}"; do _tui_store.unsize "$p"; done # every resized split, kept or not
	_tui_store.reset_done
	return 0
}

# tui.page.reset_field ID - the same for one widget or pane (rc 1 when the page keeps nothing for ID)
tui.page.reset_field() {
	local pass
	_tui_store.fields "$1"
	[[ -n "$_SFL" ]] || return 1
	_tui_store.owner "$1"
	tui.store.unset "$_SP" "$1"
	_tui_store.disk_drop "$_SP" "$1"
	_tui_resize.snap
	for pass in all size; do _tui_store.reset_item "$1" "$pass"; done
	_tui_store.reset_done
	return 0
}

# tui.page.reset_all - empties the whole store, deletes every disk entry and resets the current page
tui.page.reset_all() {
	_TUI_STORE=()
	[[ -n "$_TUI_STORE_LOADED" ]] || _tui_store.load_disk
	if ((${#_TUI_STORE_FILE[@]})); then
		_TUI_STORE_FILE=()
		_TUI_STORE_DIRTY=1
		_tui_store.flush_disk
	fi
	tui.page.reset
}

# tui.page.resettable - rc 0 while the current page is resized or a kept field differs from its default
tui.page.resettable() {
	local id f cur
	((${#_TUI_P_WEIGHTS0[@]})) && return 0
	_tui_store.active || return 1
	_tui_store.page
	_tui_store.ids
	for id in "${_SIDS[@]}"; do
		_tui_store.owner "$id"
		_tui_store.fields "$id"
		for f in $_SFL; do
			[[ "$f" == size ]] && continue
			_tui_store.key "$_SP" "$id" "$f"
			[[ -n "${_TUI_STORE_DEFAULT["$_SK"]+x}" ]] || continue
			cur="${_TUI_STORE_DEFAULT["$_SK"]}"
			"_tui_store.get.$f" "$id" 2>/dev/null && [[ "$_SF" != "$cur" ]] && return 0
		done
	done
	return 1
}

# ── actions ───────────────────────────────────────────────────────────────

# tui.action.page_reset - alt+shift+r
tui.action.page_reset() { tui.page.reset; }

# tui.action.page_reset_all
tui.action.page_reset_all() { tui.page.reset_all; }

# tui.action.page_reset_field - the focused widget, else the nearest pane around the focus that keeps something
tui.action.page_reset_field() {
	local p
	[[ -n "$_TUI_FOCUS_ID" ]] && tui.page.reset_field "$_TUI_FOCUS_ID" && return 0
	_tui_input.pane_current
	p="$_PC"
	while [[ -n "$p" ]]; do
		tui.page.reset_field "$p" && return 0
		_tui_resize.parent "$p" && p="$_RZ_P" || p=""
	done
	return 1
}

# ── disk ──────────────────────────────────────────────────────────────────

# _tui_store.is_disk ID - rc 0 when ID's fields are persisted (its own persist="disk" or a page-wide one)
_tui_store.is_disk() {
	[[ -n "$_TUI_P_DISK_STATE" || -n "${_TUI_W_DISK[$1]:-}" || -n "${_TUI_P_DISK[$1]:-}" ]]
}

# _tui_store.disk_put VALUE - _SK's entry into the disk image, dirty when it changed. A value that equals the page's
# first-build default is not written unless the file already holds something to overwrite.
_tui_store.disk_put() {
	if [[ -z "${_TUI_STORE_FILE["$_SK"]+x}" ]]; then
		[[ -n "${_TUI_STORE_DEFAULT["$_SK"]+x}" && "${_TUI_STORE_DEFAULT["$_SK"]}" == "$1" ]] && return 0
	elif [[ "${_TUI_STORE_FILE["$_SK"]}" == "$1" ]]; then
		return 0
	fi
	_TUI_STORE_FILE["$_SK"]="$1"
	_TUI_STORE_DIRTY=1
}

# _tui_store.disk_set PAGE ID FIELD VALUE / disk_unset PAGE ID FIELD - mirror a store change for a persisted id
_tui_store.disk_set() {
	_tui_store.is_disk "$2" || return 0
	_tui_store.key "$1" "$2" "$3"
	_tui_store.disk_put "$4"
}
_tui_store.disk_unset() {
	_tui_store.is_disk "$2" || return 0
	_tui_store.key "$1" "$2" "$3"
	[[ -n "${_TUI_STORE_FILE["$_SK"]+x}" ]] || return 0
	unset '_TUI_STORE_FILE["$_SK"]'
	_TUI_STORE_DIRTY=1
}

# _tui_store.disk_drop PAGE [ID] - removes a page's (or one id's) entries from the disk image
_tui_store.disk_drop() {
	[[ -n "$_TUI_STORE_LOADED" ]] || _tui_store.load_disk
	local k pre
	if [[ -n "${2+x}" ]]; then _tui_store.prefix "$1" "$2"; else _tui_store.prefix "$1"; fi
	pre="$_SK"
	for k in "${!_TUI_STORE_FILE[@]}"; do
		[[ "$k" == "$pre"* ]] || continue
		unset '_TUI_STORE_FILE["$k"]'
		_TUI_STORE_DIRTY=1
	done
	return 0
}

# _tui_store.merge_disk - the file's entries for the persisted items of the built page into _TUI_STORE (an entry that is
# already there wins)
_tui_store.merge_disk() {
	[[ -n "$_TUI_P_DISK_STATE" ]] || ((${#_TUI_W_DISK[@]} || ${#_TUI_P_DISK[@]})) || return 0
	[[ -n "$_TUI_STORE_LOADED" ]] || _tui_store.load_disk
	((${#_TUI_STORE_FILE[@]})) || return 0
	local id f page
	_tui_store.page
	page="$_SP"
	_tui_store.ids
	for id in "${_SIDS[@]}"; do
		_tui_store.is_disk "$id" || continue
		_tui_store.fields "$id"
		for f in $_SFL; do _tui_store.merge_key "$page" "$id" "$f"; done
	done
	_tui_store.merge_key "$page" "" focus
	return 0
}
_tui_store.merge_key() {
	_tui_store.key "$1" "$2" "$3"
	[[ -n "${_TUI_STORE_FILE["$_SK"]+x}" && -z "${_TUI_STORE["$_SK"]+x}" ]] && _TUI_STORE["$_SK"]="${_TUI_STORE_FILE["$_SK"]}"
	return 0
}

# _tui_store.esc VALUE -> _SE: \ TAB newline CR as \\ \t \n \r
_tui_store.esc() {
	local bs='\' v="$1"
	v="${v//"$bs"/"$bs$bs"}"
	v="${v//$'\t'/"${bs}t"}"
	v="${v//$'\n'/"${bs}n"}"
	_SE="${v//$'\r'/"${bs}r"}"
}

# _tui_store.unesc TEXT -> _SE: the inverse of esc (an unknown escape stays as written)
_tui_store.unesc() {
	local s="$1" out="" bs='\' c
	while [[ "$s" == *"$bs"* ]]; do
		out+="${s%%"$bs"*}"
		s="${s#*"$bs"}"
		c="${s:0:1}"
		case "$c" in
			t) out+=$'\t' ;;
			n) out+=$'\n' ;;
			r) out+=$'\r' ;;
			"$bs") out+="$bs" ;;
			*) out+="$bs$c" ;;
		esac
		s="${s:1}"
	done
	_SE="$out$s"
}

# _tui_store.load_disk - reads $TUI_HOME/state/store into _TUI_STORE_FILE, once. Anything that does not parse is skipped.
_tui_store.load_disk() {
	_TUI_STORE_LOADED=1
	local file="${TUI_HOME:-}/state/store" fd line tabs p i f v rest
	[[ -n "${TUI_HOME:-}" && -f "$file" && -r "$file" ]] || return 0
	exec {fd}<"$file" 2>/dev/null || return 0
	IFS= read -r -u "$fd" line 2>/dev/null
	if [[ "$line" == "# dabt-state 1" ]]; then
		while IFS= read -r -u "$fd" line || [[ -n "$line" ]]; do
			((${#line} > 65536)) && continue
			tabs="${line//[!$'\t']/}"
			((${#tabs} == 3)) || continue
			p="${line%%$'\t'*}" rest="${line#*$'\t'}"
			i="${rest%%$'\t'*}" rest="${rest#*$'\t'}"
			f="${rest%%$'\t'*}" v="${rest#*$'\t'}"
			_tui_store.unesc "$f"
			f="$_SE"
			case "$f" in value | cursor | scroll | sel | collapsed | size | focus) ;; *) continue ;; esac
			_tui_store.unesc "$p"
			p="$_SE"
			[[ -n "$p" ]] || continue
			_tui_store.unesc "$i"
			i="$_SE"
			_tui_store.unesc "$v"
			_tui_store.key "$p" "$i" "$f"
			_TUI_STORE_FILE["$_SK"]="$_SE"
		done
	fi
	exec {fd}<&-
	return 0
}

# tui.store.file - prints the path of the disk file
tui.store.file() {
	[[ -n "${TUI_HOME:-}" ]] || return 1
	printf '%s\n' "$TUI_HOME/state/store"
}

# tui.store.flush - writes the disk image now: the temp file store.tmp.PID (mode 0600) in a 0700 folder, then one mv
tui.store.flush() {
	[[ -n "${TUI_HOME:-}" ]] || return 1
	[[ -n "$_TUI_STORE_LOADED" ]] || _tui_store.load_disk
	local dir="$TUI_HOME/state" key k p i f out um tmp
	out="# dabt-state 1"$'\n'
	for key in "${!_TUI_STORE_FILE[@]}"; do
		p="${key%%|*}" k="${key#*|}"
		i="${k%%|*}" f="${k#*|}"
		p="${p//%7C/|}" p="${p//%25/%}"
		i="${i//%7C/|}" i="${i//%25/%}"
		_tui_store.esc "$p"
		out+="$_SE"$'\t'
		_tui_store.esc "$i"
		out+="$_SE"$'\t'
		_tui_store.esc "$f"
		out+="$_SE"$'\t'
		_tui_store.esc "${_TUI_STORE_FILE["$key"]}"
		out+="$_SE"$'\n'
	done
	[[ -d "$dir" ]] || mkdir -p -m 700 "$dir" 2>/dev/null || return 1
	tmp="$dir/store.tmp.$BASHPID"
	um="$(umask)"
	umask 077
	if printf '%s' "$out" >"$tmp" 2>/dev/null && mv -f "$tmp" "$dir/store" 2>/dev/null; then
		umask "$um"
		_TUI_STORE_DIRTY=""
		return 0
	fi
	umask "$um"
	rm -f "$tmp" 2>/dev/null
	return 1
}

# _tui_store.flush_disk - tui.store.flush when something changed since the last write
_tui_store.flush_disk() {
	[[ -n "$_TUI_STORE_DIRTY" ]] || return 0
	tui.store.flush
}

# _tui_store.exit - app exit (_master_cleanup): the current page's state, then the file. Only after a page was restored,
# so a process that merely built pages never overwrites what is on disk.
_tui_store.exit() {
	[[ -n "$_TUI_STORE_ARMED" ]] || return 0
	_tui_store.save_page
	_tui_store.save_focus
	_tui_store.flush_disk
	return 0
}

# ── focus ─────────────────────────────────────────────────────────────────

# _tui_store.save_focus - the focused widget's id as the page's `focus` field, when the page can use it (focus_on_enter
# keep, or a keep_focus widget); in the file for a persisted page or widget
_tui_store.save_focus() {
	[[ -n "${_TUI_MARKUP_FILE:-}" && -n "${_TUI_FOCUS_ID:-}" ]] || return 0
	local id="$_TUI_FOCUS_ID"
	[[ "$_TUI_P_FOCUS_ON_ENTER" == keep || -n "${_TUI_W_KEEPFOCUS[$id]:-}" ]] || return 0
	_tui_store.page
	tui.store.set "$_SP" "" focus "$id"
	[[ -n "$_TUI_P_DISK_STATE" || -n "${_TUI_W_DISK[$id]:-}" ]] || return 0
	_tui_store.key "$_SP" "" focus
	_tui_store.disk_put "$id"
}

# _tui_store.carry -> _SF: the focused widget's id when it is a keep_focus widget (tui.goto: before the page is left)
_tui_store.carry() {
	_SF=""
	[[ -n "${_TUI_FOCUS_ID:-}" && -n "${_TUI_W_KEEPFOCUS[$_TUI_FOCUS_ID]:-}" ]] && _SF="$_TUI_FOCUS_ID"
	return 0
}

# _tui_store.enter_focus [CARRIED_ID] - where focus lands on a page that was just built: the keep_focus widget carried from
# the page left when this page has it, else the page's focus_on_enter (keep: the last focused id of this page, ID: that
# widget, first: the first focusable widget); with no focus_on_enter a stored keep_focus widget is taken back. An id that
# is not a focusable widget of the page leaves the focus on the first one.
_tui_store.enter_focus() {
	local want="${1:-}" foe="$_TUI_P_FOCUS_ON_ENTER"
	_tui_store.page
	if [[ -z "$want" || -z "${_TUI_W_TYPE[$want]:-}" ]]; then
		want=""
		case "$foe" in
			first) ;;
			keep) tui.store.get "$_SP" "" focus && want="$REPLY" ;;
			"") tui.store.get "$_SP" "" focus && [[ -n "${_TUI_W_KEEPFOCUS[$REPLY]:-}" ]] && want="$REPLY" ;;
			*) want="$foe" ;;
		esac
	fi
	[[ -n "$want" && -n "${_TUI_W_TYPE[$want]:-}" ]] || return 0
	_tui_focus.ensure
	[[ -n "${_TUI_FOCUS_POS[$want]+x}" ]] || return 0
	_TUI_FOCUS_ID="$want"
	_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[$want]}"
	return 0
}
