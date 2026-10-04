#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_refresh.sh                                                       ║
# ╚════════════════════════════════════════════════════════════════════════╝
# tui.page.refresh   re-applies the addons (and everything else the parser reads) to the page on screen and rebuilds
#                    only the panes whose content changed. A page switch has a budget of 100 ms; so has this.
#
# How it stays fast. A full rebuild means parsing the page's files, which costs more than the whole budget. Instead the
# page remembers two things (both part of the cached page, so a cache hit has them too):
#   _TUI_P_RAW      the parsed tree as written, before addons and templates (tui_node.dump)
#   _TUI_P_SIG_*    a signature per pane of the tree that was built: _OWN (the pane's own attributes, its non-pane
#                   children, and the weights of its pane children), _FULL (OWN plus every pane below) and the flat
#                   widgets and other tags outside all panes (_TOP)
# A refresh loads the raw tree back (no parsing), applies the addons now on disk, expands templates and loops, signs the
# result and compares. A pane whose OWN signature differs is rebuilt from its new nodes (everything below it is torn
# down first); a pane whose OWN is equal but FULL differs is not touched itself, only the panes below it are looked at.
# So the cost follows what changed, not the size of the page, and widgets in panes that did not change (a half-typed
# input next to a regenerated list) keep their state.
#
# When the change cannot be applied this way - something outside the panes changed, a pane without an id would have to
# be rebuilt, the root pane itself changed, or the changed part holds tabs or another tag the incremental build does not
# handle - the page is rebuilt in the background instead (tui.page.rebuild, with a spinner).
# requires:

declare -g _TUI_P_RAW=""                                             # tui_node.dump of the parsed page, before addons and templates
declare -gA _TUI_P_SIG_OWN=() _TUI_P_SIG_FULL=() _TUI_P_SIG_PLAIN=() # pane key -> signature / 1 when only plain tags below
declare -g _TUI_P_SIG_TOP=""                                         # signature of everything outside the panes

# scratch: the signatures of the tree currently in the node store
declare -gA _RF_OWN=() _RF_FULL=() _RF_PLAIN=() _RF_NODE=() _RF_KIDS=() _RF_FLAT=() # _RF_FLAT: panes that widgets outside all panes point at (pane="x")
declare -ga _RF_TOPKEYS=() _RF_TARGETS=()
declare -g _RF_S="" _RF_TOP="" _RF_BAD=0
declare -gi _RF_ANON=0

# 0 skips the background job that brings the cached page up to date after a refresh (the page then rebuilds from its
# files on the next visit): for measuring the refresh without it
declare -gi TUI_REFRESH_CACHE_JOB="${TUI_REFRESH_CACHE_JOB:-1}"

# tags the incremental build knows how to rebuild (panes are handled by their own rule)
_RF_PLAIN_TAGS=" label button input checkbox password textarea list table select progress text "

_tui_refresh.reset() {
	_TUI_P_RAW=""
	_TUI_P_SIG_OWN=() _TUI_P_SIG_FULL=() _TUI_P_SIG_PLAIN=()
	_TUI_P_SIG_TOP=""
}

_tui_refresh.is_pane() {
	case "$1" in pane | row | col | spacer | divider | group | details | accordion) return 0 ;; esac
	return 1
}

# ── signatures ───────────────────────────────────────────────────────────

# _tui_refresh.node_sig N - appends N and everything below it to _RF_S; sets _RF_BAD for a tag the incremental build
# does not handle
_tui_refresh.node_sig() {
	local n="$1" a k
	_RF_S+="<${_N_TYPE[$n]}"
	[[ "$_RF_PLAIN_TAGS" == *" ${_N_TYPE[$n]} "* ]] || _RF_BAD=1
	for a in ${_N_ANAMES[$n]:-}; do
		[[ "$a" == __* ]] && continue
		_RF_S+=$'\x1f'"$a=${_N_ATTR["$n.$a"]}"
	done
	_RF_S+=">"
	for k in ${_N_KIDS[$n]:-}; do _tui_refresh.node_sig "$k"; done
	_RF_S+="</>"
}

# _tui_refresh.sign_pane NODE KEY - fills _RF_OWN/_FULL/_PLAIN/_NODE/_KIDS for the pane NODE (and every pane below)
_tui_refresh.sign_pane() {
	local n="$1" key="$2" k a i=0 kkey own full bad_here=0 saved_bad="$_RF_BAD" spec
	local -a kidnodes=() kidkeys=()
	_RF_BAD=0
	_RF_S="<${_N_TYPE[$n]}"
	for a in ${_N_ANAMES[$n]:-}; do
		[[ "$a" == __* ]] && continue
		_RF_S+=$'\x1f'"$a=${_N_ATTR["$n.$a"]}"
	done
	_RF_S+=">"
	for k in ${_N_KIDS[$n]:-}; do
		if _tui_refresh.is_pane "${_N_TYPE[$k]}"; then
			kkey="${_N_ID[$k]:-}"
			[[ -n "$kkey" ]] || kkey="~$key/$i"
			i=$((i + 1))
			spec=""
			for a in weight width height grid_row grid_col span newline; do
				tui_node.attr_get "$k" "$a" && spec+=$'\x1f'"$a=$_N_ATTR_V"
			done
			_RF_S+="[pane $kkey$spec]"
			kidnodes+=("$k")
			kidkeys+=("$kkey")
		else
			_tui_refresh.node_sig "$k"
		fi
	done
	own="$_RF_S"
	bad_here=$_RF_BAD
	full="$own"
	for i in "${!kidnodes[@]}"; do
		_RF_BAD=0
		_tui_refresh.sign_pane "${kidnodes[i]}" "${kidkeys[i]}"
		full+="{${_RF_FULL[${kidkeys[i]}]}}"
		((_RF_PLAIN[${kidkeys[i]}])) || bad_here=1
	done
	_RF_OWN[$key]="$own"
	_RF_FULL[$key]="$full"
	_RF_PLAIN[$key]=$((! bad_here))
	_RF_NODE[$key]=$n
	_RF_KIDS[$key]="${kidkeys[*]}"
	_RF_BAD=$saved_bad
}

# _tui_refresh.sign_top N - signs the non-pane tags outside all panes into _RF_TOP and every top-level pane tree
_tui_refresh.sign_top() {
	local n="$1" k a key i=0
	for k in ${_N_KIDS[$n]:-}; do
		if _tui_refresh.is_pane "${_N_TYPE[$k]}"; then
			key="${_N_ID[$k]:-}"
			[[ -n "$key" ]] || key="~top/${_RF_ANON}"
			_RF_ANON=$((_RF_ANON + 1))
			_RF_TOPKEYS+=("$key")
			_tui_refresh.sign_pane "$k" "$key"
		else
			_RF_TOP+="<${_N_TYPE[$k]}"
			tui_node.attr_get "$k" pane && _RF_FLAT[$_N_ATTR_V]=1
			for a in ${_N_ANAMES[$k]:-}; do
				[[ "$a" == __* ]] && continue
				_RF_TOP+=$'\x1f'"$a=${_N_ATTR["$k.$a"]}"
			done
			_RF_TOP+=">"
			_tui_refresh.sign_top "$k"
		fi
	done
}

# _tui_refresh.sign_tree - signatures of the tree in the node store (rooted at _P_ROOT) -> _RF_*
_tui_refresh.sign_tree() {
	_RF_OWN=() _RF_FULL=() _RF_PLAIN=() _RF_NODE=() _RF_KIDS=() _RF_FLAT=()
	_RF_TOPKEYS=() _RF_TOP="" _RF_ANON=0 _RF_BAD=0
	_tui_refresh.sign_top "$_P_ROOT"
}

# _tui_refresh.adopt - the signatures of the tree just built become the page's (called at the end of every build)
_tui_refresh.adopt() {
	local k
	_TUI_P_SIG_OWN=() _TUI_P_SIG_FULL=() _TUI_P_SIG_PLAIN=()
	for k in "${!_RF_OWN[@]}"; do
		_ps.panes.set "$k" sig_own "${_RF_OWN[$k]}"
		_ps.panes.set "$k" sig_full "${_RF_FULL[$k]}"
		_ps.panes.set "$k" sig_plain "${_RF_PLAIN[$k]}"
	done
	_TUI_P_SIG_TOP="$_RF_TOP"
}

# ── what changed ─────────────────────────────────────────────────────────

# _tui_refresh.targets - _RF_TARGETS = the panes to rebuild; rc 1 when the change cannot be applied incrementally
_tui_refresh.targets() {
	_RF_TARGETS=()
	[[ "$_RF_TOP" == "$_TUI_P_SIG_TOP" ]] || return 1
	local key
	for key in "${_RF_TOPKEYS[@]}"; do _tui_refresh.visit "$key" || return 1; done
	return 0
}

_tui_refresh.visit() {
	local key="$1" kid
	if [[ -z "${_TUI_P_SIG_OWN[$key]+x}" || "${_RF_OWN[$key]}" != "${_TUI_P_SIG_OWN[$key]}" ]]; then
		_tui_refresh.target "$key"
		return
	fi
	[[ "${_RF_FULL[$key]}" == "${_TUI_P_SIG_FULL[$key]}" ]] && return 0
	for kid in ${_RF_KIDS[$key]}; do _tui_refresh.visit "$kid" || return 1; done
	return 0
}

# _tui_refresh.target KEY - rebuild this pane; refused for what the incremental build cannot do
_tui_refresh.target() {
	local key="$1"
	[[ "$key" == '~'* || "$key" == root ]] && return 1              # anonymous or the page's root pane
	[[ -n "${_TUI_P_ROW[$key]+x}" ]] || return 1                    # no such pane on screen to rebuild
	((_RF_PLAIN[$key] && ${_TUI_P_SIG_PLAIN[$key]:-0})) || return 1 # tabs and the like, before or after
	_tui_refresh.has_flat "$key" && return 1                        # a widget outside the panes belongs to it
	_RF_TARGETS+=("$key")
}

# _tui_refresh.has_flat KEY - rc 0 if KEY or a pane below it is named by a widget written outside all panes
_tui_refresh.has_flat() {
	local kid
	[[ -n "${_RF_FLAT[$1]:-}" ]] && return 0
	for kid in ${_RF_KIDS[$1]:-}; do _tui_refresh.has_flat "$kid" && return 0; done
	return 1
}

# ── tearing down what is below a pane ────────────────────────────────────

declare -ga _EF_PANES=()
declare -gA _EF_SET=()
declare -gi _EF_POS=0 # _tui_engine.forget_below: index in _TUI_W_ORDER where the removed widgets stood

_tui_engine.collect_panes() {
	local c
	_EF_PANES+=("$1")
	for c in ${_TUI_P_CHILDREN[$1]:-}; do _tui_engine.collect_panes "$c"; done
}

# _tui_engine.forget_widget ID - every per-widget array entry (page state, focus, hit, text/list state)
_tui_engine.forget_widget() {
	local id="$1"
	unset '_TUI_W_TYPE[$id]' '_TUI_W_PANE[$id]' '_TUI_W_ROW[$id]' '_TUI_W_LABEL[$id]' \
		'_TUI_W_VALUE[$id]' '_TUI_W_ACTION[$id]' '_TUI_W_SUBMIT[$id]' '_TUI_W_PH[$id]' \
		'_TUI_W_ALIGN[$id]' '_TUI_W_VALIGN[$id]' '_TUI_W_MINW[$id]' '_TUI_W_MAXW[$id]' \
		'_TUI_W_MINH[$id]' '_TUI_W_MAXH[$id]' '_TUI_W_EXPAND[$id]' \
		'_TUI_W_WIDTH[$id]' '_TUI_W_HEIGHT[$id]' \
		'_TUI_W_LABEL_ALIGN[$id]' '_TUI_W_LABEL_WIDTH[$id]' '_TUI_W_RETAIN[$id]' '_TUI_W_STICKY[$id]' '_TUI_W_PIN[$id]' '_TUI_W_HPAD[$id]' '_TUI_W_VPAD[$id]' \
		'_TUI_W_FOCUSABLE[$id]' '_TUI_W_TABBABLE[$id]' '_TUI_W_TABORDER[$id]' '_TUI_W_FGROUP[$id]' '_TUI_W_FNAV[$id]' '_TUI_W_FWRAP[$id]' \
		'_TUI_W_FNEXT[$id]' '_TUI_W_FPREV[$id]' '_TUI_W_AUTOFOCUS[$id]' '_TUI_W_HITPAD[$id]' '_TUI_W_HITBOX[$id]'
	_tui_wx.forget "$id"
}

# _tui_engine.forget_pane ID - every per-pane array entry (geometry included)
_tui_engine.forget_pane() {
	local id="$1"
	unset '_TUI_P_ROW[$id]' '_TUI_P_COL[$id]' '_TUI_P_H[$id]' '_TUI_P_W[$id]' \
		'_TUI_P_DIR[$id]' '_TUI_P_CHILDREN[$id]' '_TUI_P_WEIGHTS[$id]' '_TUI_P_CELLW[$id]' '_TUI_P_CELLH[$id]' '_TUI_P_SPAN[$id]' '_TUI_P_NEWLINE[$id]' \
		'_TUI_P_TITLE[$id]' '_TUI_P_BORDER[$id]' '_TUI_P_ALIGN[$id]' '_TUI_P_VALIGN[$id]' \
		'_TUI_P_MINW[$id]' '_TUI_P_MINH[$id]' '_TUI_P_MAXW[$id]' '_TUI_P_MAXH[$id]' \
		'_TUI_P_SCROLL[$id]' '_TUI_P_SOFF_V[$id]' '_TUI_P_SOFF_H[$id]' '_TUI_P_STUCK[$id]' '_TUI_P_HPAD[$id]' '_TUI_P_VPAD[$id]' '_TUI_P_BORDER_EXPL[$id]' '_TUI_P_NOREVEAL[$id]' \
		'_TUI_P_GAP[$id]' '_TUI_P_FUSE[$id]' '_TUI_P_DIVIDER[$id]' '_TUI_P_DIVIDER_CLASS[$id]' '_TUI_P_TITLE_POS[$id]' '_TUI_P_TITLE_ALIGN[$id]' '_TUI_P_RESIZABLE[$id]' '_TUI_P_HANDLE[$id]' '_TUI_P_ON_RESIZE[$id]' '_TUI_P_WEIGHTS0[$id]' '_TUI_P_STRICT_FIT[$id]' '_TUI_P_CONTENT[$id]' '_TUI_PANE_LAST_WIDGET[$id]' '_TUI_P_CONTENT_H[$id]'
}

# _tui_engine.clear_children PANE - PANE keeps its geometry and attributes but has no children (a shell's outlet between pages)
_tui_engine.clear_children() {
	unset '_TUI_P_CHILDREN[$1]' '_TUI_P_WEIGHTS[$1]' '_TUI_P_DIR[$1]' '_TUI_P_GAP[$1]' '_TUI_P_CELLW[$1]' '_TUI_P_CELLH[$1]'
}

# _tui_engine.forget_styles ID... - the class styles baked for these ids (keys "ID_normal", "ID_hover", ...)
_tui_engine.forget_styles() {
	local -A gone=()
	local id k
	for id in "$@"; do gone[$id]=1; done
	for k in "${!_TUI_STYLE_FG[@]}" "${!_TUI_STYLE_BG[@]}" "${!_TUI_STYLE_MOD[@]}"; do
		[[ -n "${gone[${k%_*}]:-}" ]] && unset '_TUI_STYLE_FG[$k]' '_TUI_STYLE_BG[$k]' '_TUI_STYLE_MOD[$k]'
	done
}

# _tui_engine.forget_below PANE - removes every pane below PANE and every widget in PANE or below, and puts PANE back
# to a freshly created leaf (its geometry stays) so the build can set it up from the new nodes.
_tui_engine.forget_below() {
	local p="$1" w c
	local -a keep=() gone=() ids=()
	_EF_PANES=()
	_EF_SET=()
	_EF_POS=-1
	for c in ${_TUI_P_CHILDREN[$p]:-}; do _tui_engine.collect_panes "$c"; done
	for c in "${_EF_PANES[@]}"; do _EF_SET[$c]=1; done
	_EF_SET[$p]=1
	for w in "${_TUI_W_ORDER[@]}"; do
		if [[ -n "${_EF_SET[${_TUI_W_PANE[$w]:-}]:-}" ]]; then
			((_EF_POS < 0)) && _EF_POS=${#keep[@]} # where the new widgets go back in: document order is Tab order
			gone+=("$w")
		else
			keep+=("$w")
		fi
	done
	((_EF_POS < 0)) && _EF_POS=${#keep[@]}
	_TUI_W_ORDER=("${keep[@]}")
	for w in "${gone[@]}"; do _tui_engine.forget_widget "$w"; done
	for c in "${_EF_PANES[@]}"; do
		unset "_TUI_PANE_CONTENT_${c}" '_TUI_PANE_CONTENT[$c]'
		_tui_engine.forget_pane "$c"
	done
	local geo_r="${_TUI_P_ROW[$p]:-}" geo_c="${_TUI_P_COL[$p]:-}" geo_h="${_TUI_P_H[$p]:-}" geo_w="${_TUI_P_W[$p]:-}"
	_tui_engine.forget_pane "$p"
	_TUI_P_ROW[$p]="$geo_r" _TUI_P_COL[$p]="$geo_c" _TUI_P_H[$p]="$geo_h" _TUI_P_W[$p]="$geo_w"
	_TUI_P_BORDER[$p]="single" _TUI_P_TITLE[$p]="" # what _tui._split gives every pane it creates
	ids=("$p" "${_EF_PANES[@]}" "${gone[@]}")
	_tui_engine.forget_styles "${ids[@]}"
	_tui_w.changed
}

# ── tui.page.refresh ─────────────────────────────────────────────────────

# tui.page.refresh - see the header. Returns 0 when the screen is up to date (also when nothing changed); a change it
# cannot apply incrementally is handed to tui.page.rebuild.
tui.page.refresh() {
	local file="${_TUI_MARKUP_FILE:-}" key node pid kept at
	[[ -n "$file" ]] || return 1
	if [[ -z "$_TUI_P_RAW" ]]; then # a page cached before pages carried their raw tree
		tui.page.rebuild --label "Updating page..." "$file"
		return
	fi
	_tui_perf.begin page_refresh
	tui_node.load "$_TUI_P_RAW"
	_P_ROOT=0
	_P_ERRORS=()
	_P_SEEN=() # files read for addons and components count as unread again
	tui_addon.apply "$_P_ROOT" "$file"
	tui_compose.expand "$_P_ROOT"
	((${#_P_ERRORS[@]})) && printf 'tui.page.refresh: %s\n' "${_P_ERRORS[@]}" >&2
	_tui_refresh.sign_tree
	if ! _tui_refresh.targets; then
		_tui_perf.end page_refresh
		tui.page.rebuild --label "Updating page..." "$file"
		return
	fi
	if ((${#_RF_TARGETS[@]} == 0)); then
		_tui_perf.end page_refresh
		return 0
	fi
	_tui_store.save_page
	_TUI_BUILD_TITLE=()
	_TUI_BUILD_BORDER=()
	for key in "${_RF_TARGETS[@]}"; do
		node="${_RF_NODE[$key]}"
		_tui_engine.forget_below "$key"
		kept=${#_TUI_W_ORDER[@]}
		at=$_EF_POS
		_TUI_BUILD_CTX_PANE=""
		_TUI_BUILD_CTX_ROW=0
		_tui_build.dispatch "$node"
		# the widgets just built were appended: move them to where the pane's old ones stood
		_TUI_W_ORDER=("${_TUI_W_ORDER[@]:0:at}" "${_TUI_W_ORDER[@]:kept}" "${_TUI_W_ORDER[@]:at:kept-at}")
	done
	for pid in "${!_TUI_BUILD_TITLE[@]}"; do tui.pane_title "$pid" "${_TUI_BUILD_TITLE[$pid]}"; done
	for pid in "${!_TUI_BUILD_BORDER[@]}"; do tui.pane_border "$pid" "${_TUI_BUILD_BORDER[$pid]}"; done
	_TUI_P_ALL=()
	_TUI_P_LEAVES=()
	_tui._collect_leaves root
	_tui_refresh.after_teardown
	_tui_store.restore_page
	_tui_refresh.adopt
	tui.cache.forget "$file" # the cached page predates this change: a visit before the refresh below lands rebuilds it
	_tui_perf.end page_refresh
	tui.relayout
	# the cache catches up in the background, from the tree just expanded (a page of a shell is recorded on its next visit:
	# the background build starts from a clean engine, shell included)
	((_TUI_RUNNING && TUI_REFRESH_CACHE_JOB)) && [[ -z "$_TUI_SHELL_FILE" ]] && tui.page.rebuild --quiet --expanded "$file"
	return 0
}

# _tui_refresh.after_teardown - focus, hover and keyboard pane must not point at things that no longer exist
_tui_refresh.after_teardown() {
	if [[ -n "$_TUI_FOCUS_ID" && -z "${_TUI_W_TYPE[$_TUI_FOCUS_ID]:-}" ]]; then
		_TUI_FOCUS_ID=""
		_TUI_FOCUS_IDX=-1
		_TUI_CURSOR=0
	fi
	[[ -n "$_TUI_HOVERED_WIDGET" && -z "${_TUI_W_TYPE[$_TUI_HOVERED_WIDGET]:-}" ]] && _TUI_HOVERED_WIDGET=""
	[[ -n "$_TUI_HOVERED_PANE" && -z "${_TUI_P_ROW[$_TUI_HOVERED_PANE]+x}" ]] && _TUI_HOVERED_PANE=""
	[[ -n "$_TUI_PANE_FOCUS" && -z "${_TUI_P_ROW[$_TUI_PANE_FOCUS]+x}" ]] && _TUI_PANE_FOCUS=""
	_tui_w.changed
}
