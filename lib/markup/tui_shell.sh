#!/usr/bin/env bash
# tui_shell.sh - shells: persistent page chrome around swappable page content (stage 3D of
# docs/concepts/markup-v2-implementation-plan.md).
#
#   page.xml    <tui shell="_shell.xml"> ...page content... </tui>
#   _shell.xml  <tui> <pane id="root" split="v"> header, nav, <outlet/>, footer panes... </pane> </tui>
#
# A shell is a markup file with the chrome that stays while the user moves between pages plus exactly one
# <outlet id="..." weight= border= class= split= /> (id defaults to "outlet"). The outlet is a pane; the top-level
# children of a page that names the shell are built inside it. tui.goto between two pages of one shell keeps every
# shell pane and widget (focus, values, scroll, timers, binds) and rebuilds only what the previous page created;
# a page of another shell, or one without a shell, gets the full tui.reset_ui.
#
# State:
#   _TUI_SHELL_FILE      canonical path of the live shell ("" without one)
#   _TUI_OUTLET          id of its outlet pane          _TUI_OUTLET_SPLIT  the outlet's split ("h" | "v" | "")
#   _TUI_SHELL_AT        index in _TUI_W_ORDER where the page's widgets go (document order of the outlet tag)
#   _TUI_SHELL_IDS[id]   w | p for every widget / pane the shell built
#   _TUI_PAGE_IDS[id]    w | p for every widget / pane the current page built (what leaving the page removes)
# The page cache stores a page of a shell as a delta (see _tui_shell.delta): only the array entries the page's build
# added or changed, so a replay lands on top of the live shell and never touches shell state.
# requires:

declare -g _TUI_SHELL_FILE="" _TUI_OUTLET="" _TUI_OUTLET_SPLIT=""
declare -gi _TUI_SHELL_AT=0
declare -gA _TUI_SHELL_IDS=() _TUI_PAGE_IDS=()
declare -g _TUI_PAGE_UNDO="" # script putting the scalars the page changed back (runs when the page is left)
declare -gi _SHL_SOFT=0      # 1 while tui.goto swaps pages inside a live shell (the store then only saves/restores page ids)
declare -ga _SHL_TIMERS=() _SHL_WATCH=()
declare -gA _SHL_BINDS=()
declare -g _SH_OF=""
declare -g _SHL_SKIP='^(_TUI_(FOCUS_ID|FOCUS_IDX|CURSOR|FOCUSABLE|PANE_FOCUS|PENDING_OUTPUT|HOVERED_.*|P_ALL|P_LEAVES|P_RAW|P_SIG_.*|STYLE_SIG)|_TUI_SHELL_.*|_TUI_OUTLET.*|__B_.*)$'
declare -gA _SHL_FLAGS=()

# tui.shell.file -> stdout: the canonical path of the live shell (nothing when the page has none).
tui.shell.file() {
	[[ -n "$_TUI_SHELL_FILE" ]] && printf '%s' "$_TUI_SHELL_FILE"
	return 0
}

# _tui_shell.scan PAGE_FILE [FRESH] -> _SH_OF - canonical path of the shell a page names in its <tui shell="...">
# (resolved against the page's folder), "" for a page without one. A page the cache knows answers from its record unless
# FRESH is 1 (the file is read).
_tui_shell.scan() {
	local f="$1" txt src re='<tui[[:space:]]([^>]*[[:space:]])?shell="([^"]*)"'
	_SH_OF=""
	if [[ "${2:-}" != 1 && -n "${_TUI_CACHE_SHELL[$f]+x}" ]]; then
		_SH_OF="${_TUI_CACHE_SHELL[$f]}"
		return 0
	fi
	[[ -r "$f" ]] || return 0
	IFS= read -r -d '' txt <"$f" || true
	[[ "$txt" == *'shell="'* && "$txt" =~ $re ]] || return 0
	src="${BASH_REMATCH[2]}"
	[[ -n "$src" ]] || return 0
	[[ "$src" != /* ]] && src="${f%/*}/$src"
	_tui_path_canon "$src"
	_SH_OF="$_CANON"
}

# _tui_shell.ensure SHELL_FILE CACHED - builds SHELL_FILE (replayed from the page cache when CACHED is 1) unless it is the
# live shell; the markup file and folder of the page being loaded are put back afterwards. rc 1 when it cannot be loaded.
_tui_shell.ensure() {
	local s="$1" md="$_TUI_MARKUP_DIR" mf="$_TUI_MARKUP_FILE" rc=0
	[[ "$_TUI_SHELL_FILE" == "$s" ]] && return 0
	[[ -n "$_TUI_SHELL_FILE" ]] && tui.reset_ui # another shell is live: a page of this one starts from scratch
	if [[ ! -r "$s" ]]; then
		echo "tui.load: shell '$s' cannot be read" >&2
		return 1
	fi
	if (($2)); then tui.load_cached "$s" || rc=1; else tui.load "$s" || rc=1; fi
	_TUI_MARKUP_DIR="$md"
	_TUI_MARKUP_FILE="$mf"
	((rc == 0)) && _tui_shell.seal
	return $rc
}

# _tui_shell.seal - what a shell owns that is not in the snapshot: its timers, watchers and page-scoped binds, so
# leaving a page cancels only the ones the page started.
_tui_shell.seal() {
	_SHL_TIMERS=("${_TA_IDS[@]}")
	_SHL_WATCH=("${_TA_WIDS[@]}")
	_SHL_BINDS=()
	local k
	for k in "${!_TUI_BIND_PAGE[@]}"; do _SHL_BINDS[$k]=1; done
}

# _tui_shell.collect_ids - _TUI_SHELL_IDS for the shell that was just built (every widget and pane)
_tui_shell.collect_ids() {
	local w p
	_TUI_SHELL_IDS=()
	for w in "${_TUI_W_ORDER[@]}"; do _TUI_SHELL_IDS[$w]=w; done
	_EF_PANES=()
	_tui_engine.collect_panes root
	for p in "${_EF_PANES[@]}"; do _TUI_SHELL_IDS[$p]=p; done
}

# _tui_shell.build_page NODE - the markup build of a page's <tui shell="..."> NODE on a live shell: its children are the
# outlet's, and what they created is recorded in _TUI_PAGE_IDS. The widgets move from the end of _TUI_W_ORDER to where
# the outlet stands in the shell, so tab order follows the document order of shell and page together.
_tui_shell.build_page() {
	local node="$1" kept=${#_TUI_W_ORDER[@]} at=$_TUI_SHELL_AT total w c
	_TUI_PAGE_IDS=()
	_TUI_BUILD_CTX_PANE=""
	_TUI_BUILD_CTX_ROW=0
	_tui_build.pane_kids "$_TUI_OUTLET" "$node" "$_TUI_OUTLET_SPLIT" "" "" "" "" "" "" "" 1
	total=${#_TUI_W_ORDER[@]}
	((at > kept)) && at=$kept
	_TUI_W_ORDER=("${_TUI_W_ORDER[@]:0:at}" "${_TUI_W_ORDER[@]:kept}" "${_TUI_W_ORDER[@]:at:kept-at}")
	for w in "${_TUI_W_ORDER[@]:at:total-kept}"; do _TUI_PAGE_IDS[$w]=w; done
	_EF_PANES=()
	for c in ${_TUI_P_CHILDREN[$_TUI_OUTLET]:-}; do _tui_engine.collect_panes "$c"; done
	for c in "${_EF_PANES[@]}"; do _TUI_PAGE_IDS[$c]=p; done
	_tui_w.changed
}

# ── leaving a page ────────────────────────────────────────────────────────

# _tui_shell.leave_page - removes exactly what the current page built (_TUI_PAGE_IDS: its panes and widgets, wherever
# they sit) and what it started (timers, watchers, page binds, modals); the shell is untouched.
_tui_shell.leave_page() {
	local id k o="$_TUI_OUTLET"
	local -a keep=() wl=() pl=() ids=()
	local -A gone=()
	for id in "${!_TUI_PAGE_IDS[@]}"; do
		ids+=("$id")
		if [[ "${_TUI_PAGE_IDS[$id]}" == w ]]; then
			gone[$id]=1
			wl+=("$id")
		else
			pl+=("$id")
		fi
	done
	for id in "${_TUI_W_ORDER[@]}"; do [[ -n "${gone[$id]:-}" ]] || keep+=("$id"); done
	_TUI_W_ORDER=("${keep[@]}")
	for id in "${wl[@]}"; do
		_tui_engine.forget_widget "$id"
		unset '_TUI_W_HIDDEN[$id]' '_TUI_W_COLLAPSED_TEXT[$id]' '_TUI_W_LABEL_SAVED[$id]' '_TUI_W_KEEP[$id]' '_TUI_W_KEEPFOCUS[$id]' '_TUI_W_DISK[$id]'
	done
	for id in "${pl[@]}"; do
		unset "_TUI_PANE_CONTENT_${id}" '_TUI_PANE_CONTENT[$id]'
		_tui_engine.forget_pane "$id"
		unset '_TUI_P_COLLAPSIBLE[$id]' '_TUI_P_COLLAPSED[$id]' '_TUI_P_COLLAPSE_DEFAULT[$id]' '_TUI_P_COLLAPSE_TO[$id]' '_TUI_P_KEEP_COLLAPSED[$id]' \
			'_TUI_P_ON_TOGGLE[$id]' '_TUI_P_COLLAPSE_SAVED[$id]' '_TUI_P_ACCORDION[$id]' '_TUI_P_COLLAPSE_KEY[$id]' '_TUI_P_COLLAPSE_CLASS[$id]' \
			'_TUI_P_KEEP_SIZE[$id]' '_TUI_P_DISK[$id]'
	done
	((${#ids[@]})) && _tui_engine.forget_styles "${ids[@]}"
	[[ -n "$o" ]] && unset '_TUI_P_CHILDREN[$o]' '_TUI_P_WEIGHTS[$o]' '_TUI_P_DIR[$o]' '_TUI_P_GAP[$o]' '_TUI_P_CELLW[$o]' '_TUI_P_CELLH[$o]'
	_TUI_PAGE_IDS=()
	[[ -n "$_TUI_PAGE_UNDO" ]] && eval "$_TUI_PAGE_UNDO"
	_TUI_PAGE_UNDO=""
	for id in "${_TA_IDS[@]}"; do
		for k in "${_SHL_TIMERS[@]}"; do [[ "$k" == "$id" ]] && continue 2; done
		tui.every.cancel "$id"
	done
	for id in "${_TA_WIDS[@]}"; do
		for k in "${_SHL_WATCH[@]}"; do [[ "$k" == "$id" ]] && continue 2; done
		tui.watch.stop "$id"
	done
	((_TUI_BIND_GEN++))
	for k in "${!_TUI_BIND_PAGE[@]}"; do
		[[ -n "${_SHL_BINDS[$k]:-}" ]] && continue
		unset '_TUI_BIND[$k]' '_TUI_BIND_PASS[$k]' '_TUI_BIND_ALWAYS[$k]' '_TUI_BIND_PAGE[$k]' '_TUI_BIND_DESC[$k]'
	done
	_TUI_DEF_OFF_PAGE=()
	_tui_modal.reset
	_tui_dialog.reset
	_TUI_P_ALL=()
	_TUI_P_LEAVES=()
	_tui._collect_leaves root
	_tui_w.changed
	_tui.epoch_bump layout
}

# ── the page's cache entry: a delta over the shell ─────────────────────────

# _tui_shell.names -> _SH_NAMES: the engine variables a page build can change (the snapshot set minus focus, hover and the
# shell's own state)
declare -ga _SH_NAMES=()
_tui_shell.names() {
	local v
	_SH_NAMES=()
	while IFS= read -r v; do _SH_NAMES+=("$v"); done < <(compgen -A variable | grep -E "$_TUI_CACHE_STATE_REGEX" | grep -vE "$_SHL_SKIP")
}

# _tui_shell.flags DUMP - fills _SHL_FLAGS[name]=declare flags from a `declare -p` dump
_tui_shell.flags() {
	local line rest fl name
	_SHL_FLAGS=()
	while IFS= read -r line; do
		[[ "$line" == "declare "* ]] || continue
		rest="${line#declare }"
		fl="${rest%% *}"
		rest="${rest#* }"
		name="${rest%%=*}"
		name="${name%% *}"
		_SHL_FLAGS[$name]="$fl"
	done <<<"$1"
}

# _tui_shell.base_capture - copies the current engine state to __B_<name> variables: the shell as it stands before a
# page is built into it (the baseline _tui_shell.delta compares against)
_tui_shell.base_capture() {
	local dump line rest fl out=""
	_tui_shell.names
	((${#_SH_NAMES[@]})) || return 0
	dump="$(declare -p "${_SH_NAMES[@]}")"
	while IFS= read -r line; do
		if [[ "$line" == "declare "* ]]; then
			rest="${line#declare }"
			fl="${rest%% *}"
			rest="${rest#* }"
			[[ "$fl" == -- ]] && fl=-g || fl="-g${fl#-}"
			line="declare $fl __B_${rest}"
		fi
		out+="$line"$'\n'
	done <<<"$dump"
	eval "$out"
}

# _tui_shell.splice NAME PREFIX SUFFIX ITEM... - the indexed array NAME keeps its first PREFIX and last SUFFIX elements
# and gets ITEMs between them
_tui_shell.splice() {
	local -n _sp_a="$1"
	local _sp_p=$2 _sp_s=$3 _sp_n=${#_sp_a[@]}
	shift 3
	_sp_a=("${_sp_a[@]:0:_sp_p}" "$@" "${_sp_a[@]:_sp_n-_sp_s:_sp_s}")
}

# _tui_shell.delta -> _SH_APPLY _SH_UNDO - what the page build changed against the baseline of _tui_shell.base_capture:
# a script that sets those array entries / scalars again on top of a live shell, and the script that puts the scalars back
_tui_shell.delta() {
	local n k b dump fl pl sl ln i lb lf
	local -a mid=()
	_SH_APPLY="" _SH_UNDO=""
	_tui_shell.names
	((${#_SH_NAMES[@]})) || return 0
	dump="$(declare -p "${_SH_NAMES[@]}")"
	_tui_shell.flags "$dump"
	for n in "${_SH_NAMES[@]}"; do
		fl="${_SHL_FLAGS[$n]:--}"
		b="__B_$n"
		local -n _dF="$n"
		if [[ "$fl" == *A* ]]; then
			local -n _dB="$b" # a baseline that does not exist reads as empty
			local first=1
			for k in "${!_dF[@]}"; do
				if [[ -n "${_dB[$k]+x}" && "${_dB[$k]}" == "${_dF[$k]}" ]]; then continue; fi
				if ((first)); then
					_SH_APPLY+="declare -gA $n"$'\n'
					first=0
				fi
				printf -v ln '%s[%q]=%q\n' "$n" "$k" "${_dF[$k]}"
				_SH_APPLY+="$ln"
			done
			unset -n _dB
		elif [[ "$fl" == *a* ]]; then
			local hasb=0
			declare -p "$b" &>/dev/null && hasb=1
			lf=${#_dF[@]}
			if ((hasb)); then
				local -n _dB="$b"
				lb=${#_dB[@]}
				pl=0
				while ((pl < lb && pl < lf)) && [[ "${_dB[pl]}" == "${_dF[pl]}" ]]; do ((pl++)); done
				sl=0
				while ((sl < lb - pl && sl < lf - pl)) && [[ "${_dB[lb - 1 - sl]}" == "${_dF[lf - 1 - sl]}" ]]; do ((sl++)); done
				unset -n _dB
			else
				lb=0 pl=0 sl=0
			fi
			if ((lb != lf || pl + sl != lf)); then
				mid=("${_dF[@]:pl:lf-pl-sl}")
				printf -v ln '_tui_shell.splice %s %d %d' "$n" "$pl" "$sl"
				for i in "${mid[@]}"; do
					printf -v k ' %q' "$i"
					ln+="$k"
				done
				_SH_APPLY+="$ln"$'\n'
			fi
		else
			local bv="" hasb=0
			if declare -p "$b" &>/dev/null; then
				local -n _dB="$b"
				bv="$_dB"
				hasb=1
				unset -n _dB
			fi
			if ((! hasb)) || [[ "$bv" != "$_dF" ]]; then
				printf -v ln '%s=%q\n' "$n" "$_dF"
				_SH_APPLY+="$ln"
				printf -v ln '%s=%q\n' "$n" "$bv"
				_SH_UNDO+="$ln"
			fi
		fi
		unset -n _dF
	done
}

# _tui_shell.drop_base - frees the baseline copies
_tui_shell.drop_base() {
	local v
	for v in $(compgen -A variable __B_); do unset "$v"; done
}

# _tui_shell.apply FILE - the cached page delta of FILE onto the live shell
_tui_shell.apply() {
	local f="$1" id
	eval "${_TUI_CACHE_PAGE[$f]}"
	_TUI_PAGE_UNDO="${_TUI_CACHE_PAGEUNDO[$f]:-}"
	_TUI_PAGE_IDS=()
	for id in ${_TUI_CACHE_PAGEIDS[$f]:-}; do _TUI_PAGE_IDS[${id#?:}]="${id%%:*}"; done
	_TUI_P_ALL=()
	_TUI_P_LEAVES=()
	_tui._collect_leaves root
	_tui_w.changed
}

# _tui_shell.page_ids_string -> _SH_STR: _TUI_PAGE_IDS as "w:id p:id ..." (the cache record)
_tui_shell.page_ids_string() {
	local id
	_SH_STR=""
	for id in "${!_TUI_PAGE_IDS[@]}"; do _SH_STR+="${_SH_STR:+ }${_TUI_PAGE_IDS[$id]}:$id"; done
}

# _tui_shell.geometry -> _SH_GEO: the outlet's "row col height width", the space a recorded page was laid out in
_tui_shell.geometry() {
	_SH_GEO="${_TUI_P_ROW[$_TUI_OUTLET]:-} ${_TUI_P_COL[$_TUI_OUTLET]:-} ${_TUI_P_H[$_TUI_OUTLET]:-} ${_TUI_P_W[$_TUI_OUTLET]:-}"
}

# _tui_shell.enter_focus KEEP_ID KEEP_CURSOR CARRIED - focus after a page swap in a shell: a shell widget that had it keeps
# it (unless the page names a focus_on_enter); otherwise the page's choice, else the first focusable widget of the page.
_tui_shell.enter_focus() {
	local keep="$1" cur="$2" carry="$3" had=0 id
	_tui_focus.ensure
	if [[ -n "$keep" && -n "${_TUI_W_TYPE[$keep]:-}" && -z "${_TUI_PAGE_IDS[$keep]:-}" && -n "${_TUI_FOCUS_POS[$keep]+x}" ]]; then
		_TUI_FOCUS_ID="$keep"
		_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[$keep]}"
		_TUI_CURSOR=$cur
		had=1
	fi
	if ((had)) && [[ -z "$_TUI_P_FOCUS_ON_ENTER" ]]; then return 0; fi
	if ((! had)); then
		_TUI_FOCUS_ID=""
		_TUI_FOCUS_IDX=-1
		_TUI_CURSOR=0
	fi
	_tui_store.enter_focus "$carry"
	[[ -n "$_TUI_FOCUS_ID" ]] && return 0
	for id in "${_TUI_FOCUSABLE[@]}"; do
		[[ -n "${_TUI_PAGE_IDS[$id]:-}" ]] || continue
		_TUI_FOCUS_ID="$id"
		_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[$id]}"
		break
	done
	return 0
}
