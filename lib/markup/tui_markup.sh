#!/usr/bin/env bash
# tui_markup.sh - declarative HTML/XML-like config loader for tui.sh
#
# Pure bash + POSIX utilities only (no python/perl/xmlstarlet/jq). A tag may
# now span multiple physical lines and use either quote style; a comment can
# appear anywhere. Tokenizing and tree-building live in lib/markup/
# tui_parse.sh and lib/markup/tui_build.sh (markup-v2 stage 1.1/1.2) - this
# file is now a façade: tui.load, page lifecycle (tui.goto/tui.start,
# tui.reset_ui) and the fork-free path canonicalizer they share.
#
# Tags:
#   <tui>                                     root wrapper (ignored)
#   <script src="callbacks.sh"/>              source a bash callback file
#   <theme src="theme.css"/>                  load a CSS-like stylesheet (see tui_style.sh)
#   <include src="fragment.xml"/>             inline another markup file (fragments/shared nav)
#   split="fixed" size_w="N" size_h="N": children are exactly N x M cells (child attrs span="K", newline="true")
#   <pane id="x" split="h|v" weight="N" title="…" border="…" align="left|center|right|fill"
#         valign="top|middle|bottom" min_width="N" min_height="N" max_width="N" max_height="N"
#         class="name">   layout node
#   <row>/<col>/<group> (pane aliases: split="h"/split="v"/plain) and <spacer/>/<divider/>
#   (empty/bordered leaf panes) - see lib/markup/tui_build.sh.
#   hpad="N" vpad="N" (pane + label/input/button/checkbox): blank cols/rows per side. Parent pane: gap to children;
#   leaf pane: shrinks widget/output area. border= on a parent pane frames its children; borders drop when too small.
#   <footer [items="@tui.action.quit|Quit;ctrl+s|Save"]/>   one-row key-hint bar on the LAST terminal row (see tui_footer.sh)
#   <bind key="q" action="fn [args]" [pane="p"] [scope="global"] [pass="true"] [always="true"] desc="…"/>   key/mouse binding, see tui_input.sh
#   <tui on_visit="fn" defaults="-quit,-scroll">   switch default keybind groups off for this page (share/defaults/keybinds.xml)
#   <label  id="x" pane="p" row="N" text="…" align="…" valign="…" min_width="N" max_width="N" class="name"/>
#   <input  id="x" pane="p" row="N" label="…" placeholder="…" submit="fn" align="…" valign="…"  retain_input_on_submit="true|false" sticky="true"
#           min_width="N" max_width="N" label_align="left|center|right" label_width="N" class="name"/>
#   <button id="x" pane="p" row="N" text="…" action="fn" align="…" valign="…" min_width="N" max_width="N" class="name"/>
#   <button id="x" pane="p" row="N" text="…" page="other.xml"/>  navigate to another page
#   Every widget also takes: focusable/tabbable="true|false" tab_order="N" (0 first, -1 last) focus_group="g" focus_nav="arrows|tab|both"
#   focus_wrap="true|false" focus_next="id" focus_prev="id" autofocus="true" hit_pad="N" hitbox="DY DX H W"  (lib/input/tui_focus.sh, tui_hit.sh);
#   <tui focus_wrap="false"> stops Tab at the ends of the list.
#   keep_value="true" (widgets), keep_collapsed / keep_size="true" (panes), <tui keep_state="true">: state kept across page switches, persist="session|disk" (lib/state/tui_store.sh).
#   keep_focus="true" (widgets): focus stays on the same id on the next page; <tui focus_on_enter="ID|keep|first">: where focus lands on entry.
#   <password id pane row placeholder label submit/>   <textarea id pane row placeholder rows value submit on_change/>
#   <list id pane row action rows items="a|b|c" on_change/>   <table id pane row action rows columns="H1|H2" data="a|b;c|d"/>
#   <select id pane row label action items="a|b|c" value on_change/>   <progress id pane row label value/>   (see docs/guide/widgets.md)
#
# `pane=`/`row=` on a widget are optional: nested inside a <pane> (or a
# row/col/group alias), a widget's pane is its parent and its row is
# inferred from document order. Explicit pane=/row= always wins (legacy).
#
# `align`/`valign` on a <pane> set the default for widgets inside it; the same
# attributes on a widget override that default for just that widget (buttons
# center horizontally by default, everything else is left/top). `align="fill"`
# paints the whole row with the element's fg/bg instead of just the text.
#
# `class` applies a named style from a loaded <theme> stylesheet - see
# lib/style/tui_style.sh and config/theme.css. A `.class:hover { … }` rule is
# applied to a widget (button/input) while the mouse sits over it; it has
# no effect on panes. A pane's border instead uses the class's `.class:focus`
# rule while any widget inside it has keyboard focus (falling back to
# `.class:border` otherwise).
#
# `text="…"`/`label="…"` on label/button support ${command args…} runtime
# expressions (see _tui._resolve_text in tui.sh); call tui.redraw to refresh
# them on demand.
#
# `min_width`/`min_height` (panes) and `min_width` (widgets) show a
# "min space = …" warning in place of normal content when the available space
# is smaller than declared. `max_width`/`max_height` cap how large an element
# is allowed to grow.
#
# Multi-page TUIs: each file is a self-contained page (its own <tui>…</tui>).
# tui.goto "path/to/page.xml" clears the current UI and loads a new page,
# so buttons can link between files like anchors between HTML pages.

declare -g _TUI_MARKUP_DIR=""
declare -g _TUI_MARKUP_FILE=""
declare -g _TUI_APP_DIR="" # directory of the first page an app started with (themes/ lives there)

# _markup_attr LINE NAME -> stdout : one attribute's value out of a raw
# markup line, decoding XML entities. Still used by lib/widgets/tui_widgets.sh's
# _markup_wx (password/textarea/list/table/select/progress), out of this
# module's scope to change; every other tag reads attributes off the node
# store instead (lib/markup/tui_build.sh's _tui_build.attr).
_markup_attr() {
	local line="$1" name="$2"
	if [[ "$line" =~ $name[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
		local v="${BASH_REMATCH[1]}"
		[[ "$v" == *"&"* ]] && {
			v="${v//&lt;/<}"
			v="${v//&gt;/>}"
			v="${v//&quot;/\"}"
			v="${v//&amp;/\&}"
		} # XML entities
		printf '%s' "$v"
	fi
}

# _markup_attrv LINE NAME VAR - _markup_attr into VAR (a nameref), no `$(...)` fork.
_markup_attrv() {
	local -n _mav_out="$3"
	_mav_out=""
	if [[ "$1" =~ $2[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
		_mav_out="${BASH_REMATCH[1]}"
		[[ "$_mav_out" == *"&"* ]] && {
			_mav_out="${_mav_out//&lt;/<}"
			_mav_out="${_mav_out//&gt;/>}"
			_mav_out="${_mav_out//&quot;/\"}"
			_mav_out="${_mav_out//&amp;/\&}"
		} # XML entities
	fi
}

# tui.load FILE - parse a markup file and build panes/widgets via tui.* calls.
tui.load() {
	local file="$1"
	[[ -r "$file" ]] || {
		echo "tui.load: cannot read '$file'" >&2
		return 1
	}
	_tui_path_canon "$file"
	_TUI_MARKUP_FILE="$_CANON"
	_TUI_MARKUP_DIR="${_CANON%/*}"

	# a page of a shell: the shell is built first (unless it is live) and the page goes into its outlet
	_tui_shell.scan "$_TUI_MARKUP_FILE" 1
	local _ld_shell="$_SH_OF"
	[[ -z "$_ld_shell" && -n "$_TUI_SHELL_FILE" && "$_TUI_SHELL_FILE" != "$_TUI_MARKUP_FILE" ]] && tui.reset_ui # a page without a shell never builds on top of one
	if [[ -n "$_ld_shell" ]]; then
		_tui_shell.ensure "$_ld_shell" 0 || return 1
	fi

	# framework default theme first: every app gets the shared classes; its own <theme> tags override
	if [[ -z "$_ld_shell" && -r "${TUI_DEFAULTS_DIR:-}/theme.css" ]]; then
		tui.log.debug "tui.load: loading framework default theme for $file"
		tui.load_theme "$TUI_DEFAULTS_DIR/theme.css"
	fi

	tui_build.load "$file"
	[[ -n "$_TUI_SHELL_FILE" && "$_TUI_SHELL_FILE" == "$_TUI_MARKUP_FILE" ]] && _tui_shell.collect_ids
	if [[ -n "$_ld_shell" ]]; then
		_tui.layout_bump
		_tui._layout "$_TUI_OUTLET"
		_TUI_P_ALL=()
		_TUI_P_LEAVES=()
		_tui._collect_leaves root
	else
		_tui_cache_relayout
	fi

	# <tui on_visit="fn"> - runs once the page's panes/widgets are fully
	# built, so a page can, say, scan a directory and build dynamic tabs
	# (see config/docu_callbacks.sh) instead of needing every widget known
	# up front in the markup. Fires on every tui.load, including a
	# tui.goto back to a page already visited before.
	_tui_cache_run_on_visit "$_TUI_BUILD_ON_VISIT"
}

# Recorded by tui.cache so a replayed page also re-lays out once borders/pads
# are final, before its on_visit runs. Also the fix point for a cache-hit
# replay: _tui_cache_restore's snapshot includes _TUI_P_W[root]/_TUI_P_H[root]
# (every _TUI_P_* is in the snapshot) at whatever size the page was recorded
# at - _tui._root_w/_tui._root_h re-derive both from the live terminal
# before layout runs, so root is never left at a stale, cache-build-time size.
_tui_cache_relayout() {
	# Forces a real recompute regardless of _tui.layout_arrange's memoization
	# (2A): a cache-hit replay restores every _TUI_P_* array verbatim
	# (_tui_cache_restore, declare -p), but NOT _TUI_LY_KEY/_TUI_LY_GEN_AT -
	# those live in this process across page switches, so a same-named pane
	# from a DIFFERENT page (or an earlier visit to this one, at a different
	# terminal size) could otherwise coincidentally satisfy the memo's key
	# check. The memo's own generation counter can't tell replay apart from
	# an ordinary call, so this is the one unconditional bump point.
	_tui.layout_bump
	_tui._root_w
	_tui._root_h
	_tui._layout root
} # leaves the last row to a <footer/>

# tui.reset_ui - wipe all panes/widgets and rebuild a full-screen root pane.
tui.reset_ui() {
	local _pc _ei
	# exec instances die with their page: their panes/widgets are wiped below
	for _ei in "${!_EXEC_STATUS[@]}"; do _exec_dismiss_instance "$_ei"; done
	_EXEC_PANE_CTL_ROW=()
	for _pc in "${!_TUI_PANE_CONTENT[@]}"; do unset "_TUI_PANE_CONTENT_${_pc}"; done
	_TUI_PANE_CONTENT=()
	_TUI_P_ROW=()
	_TUI_P_COL=()
	_TUI_P_H=()
	_TUI_P_W=()
	_TUI_P_DIR=()
	_TUI_P_CHILDREN=()
	_TUI_P_WEIGHTS=()
	_TUI_P_CELLW=()
	_TUI_P_CELLH=()
	_TUI_P_SPAN=()
	_TUI_P_NEWLINE=()
	_TUI_P_TITLE=()
	_TUI_P_BORDER=()
	_TUI_P_LEAVES=()
	_TUI_P_ALIGN=()
	_TUI_P_VALIGN=()
	_TUI_P_CONTENT=()
	_TUI_P_MINW=()
	_TUI_P_MINH=()
	_TUI_P_MAXW=()
	_TUI_P_MAXH=()
	_TUI_P_GAP=()
	_TUI_P_FUSE=() _TUI_P_DIVIDER=() _TUI_P_DIVIDER_CLASS=() _TUI_P_TITLE_POS=() _TUI_P_TITLE_ALIGN=()
	_tui_resize.clear
	_tui_collapse.clear
	_tui_store.clear
	_TUI_SHELL_FILE="" _TUI_OUTLET="" _TUI_OUTLET_SPLIT="" _TUI_SHELL_AT=0 _TUI_SHELL_IDS=() _TUI_PAGE_IDS=() _TUI_PAGE_UNDO=""
	_TUI_P_STRICT_FIT=()
	_TUI_P_EFFECTIVE_MINW=()
	_TUI_P_EFFECTIVE_MINH=()
	_TUI_P_HPAD=()
	_TUI_P_VPAD=()
	_TUI_P_BORDER_EXPL=()
	_TUI_W_HPAD=()
	_TUI_W_VPAD=()
	_TUI_FACTORY_IDS=()
	_TUI_FACTORY_GRID_PARENTS=()
	_TUI_FACTORY_COUNTER=()
	_TUI_TABS_ACTIVE=()
	_TUI_TABS_CONTENT_PANE=()
	_TUI_TABS_COMPACT=()
	_TUI_TAB_TEXT=()
	_TUI_TAB_ACTION=()
	_TUI_TAB_DEFAULT=()
	_TUI_TAB_GROUP=()
	_TUI_W_TYPE=()
	_TUI_W_PANE=()
	_TUI_W_ROW=()
	_TUI_W_LABEL=()
	_TUI_W_VALUE=()
	_TUI_W_ACTION=()
	_TUI_W_SUBMIT=()
	_TUI_W_PH=()
	_TUI_W_ALIGN=()
	_TUI_W_VALIGN=()
	_TUI_W_MINW=()
	_TUI_W_MAXW=()
	_TUI_W_LABEL_ALIGN=()
	_TUI_W_LABEL_WIDTH=()
	_TUI_W_RETAIN=()
	_TUI_W_STICKY=()
	_TUI_W_FOCUSABLE=() _TUI_W_TABBABLE=() _TUI_W_TABORDER=() _TUI_W_FGROUP=() _TUI_W_FNAV=() _TUI_W_FWRAP=()
	_TUI_W_FNEXT=() _TUI_W_FPREV=() _TUI_W_AUTOFOCUS=() _TUI_W_HITPAD=() _TUI_W_HITBOX=()
	_TUI_FOCUS_GLAST=() _TUI_FOCUS_WRAP=1 _TUI_FOCUS_AUTO=1 _TUI_FOCUS_DIRTY=1 _TUI_HZ_DIRTY=1
	_tui_hit.extra_clear
	_tui_refresh.reset
	_tui_wx.reset
	_TUI_W_ORDER=()
	_TUI_FOCUSABLE=()
	_TUI_FOCUS_ID=""
	_TUI_FOCUS_IDX=-1
	_TUI_CURSOR=0
	_TUI_PANE_FOCUS=""
	_TUI_PANE_LAST_WIDGET=()
	_TUI_HOVERED_PANE=""
	_TUI_HOVERED_WIDGET=""
	_TUI_PENDING_OUTPUT=()
	_TUI_RENDER_TIMEOUT=-1
	_TUI_TICK_FN=""
	_TUI_ON_RESIZE_FN=""
	_TUI_ON_INPUT_EVENT=""
	_TUI_ON_KEY_EVENT=""
	_TUI_STYLE_FG=()
	_TUI_STYLE_BG=()
	_TUI_STYLE_MOD=()
	_TUI_RC_EPOCH+=1

	_tui_api.shutdown 2>/dev/null
	_tui_input.clear_page
	_tui_modal.reset
	_tui_footer.reset
	_tui_dialog.reset
	((_EXEC_PID > 0)) && _exec_cleanup_process

	# a running app keeps _TUI_ROWS/_TUI_COLS current from its resize handler: no stty fork on every page switch
	((_TUI_RUNNING)) || term.size _TUI_ROWS _TUI_COLS
	_TUI_P_ROW[root]=1
	_TUI_P_COL[root]=1
	_TUI_P_H[root]=$_TUI_ROWS
	_TUI_P_W[root]=$_TUI_COLS
	_TUI_P_BORDER[root]="single"
	_TUI_P_TITLE[root]=""
	_TUI_P_LEAVES=(root)

	erase.all
}

# tui.goto FILE - navigate to another page, resolved relative to the current page's directory.
# _tui_path_canon PATH -> _CANON: absolute, with . and .. folded - string operations only. (`cd "$(dirname ..)" && pwd`
# was 3 forks per tui.goto and per cache lookup.) Symlinks are not resolved, matching what `pwd` printed.
_tui_path_canon() {
	local p="$1" IFS=/ part
	local -a out=() parts
	[[ "$p" != /* ]] && p="${PWD}/$p"
	read -ra parts <<<"$p"
	for part in "${parts[@]}"; do
		case "$part" in
			"" | .) ;;
			..) ((${#out[@]})) && unset 'out[-1]' ;;
			*) out+=("$part") ;;
		esac
	done
	_CANON="/${out[*]}"
}

declare -ga _TUI_PAGE_HISTORY=()
declare -g _TUI_GOING_BACK=""

tui.goto() {
	local file="$1" resolved
	resolved="$file"
	[[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR:-.}/${file}"

	# Reloading the SAME page (theme switch, tui.theme.reload) keeps the user where they were:
	# remember the focused widget + cursor and put focus back if that id exists again.
	local keep_id="" keep_cur=0 canon carry=""
	_tui_path_canon "$resolved"
	canon="$_CANON"
	if [[ "$canon" == "${_TUI_MARKUP_FILE:-}" ]]; then
		keep_id="$_TUI_FOCUS_ID"
		keep_cur=$_TUI_CURSOR
	else
		_tui_store.carry
		carry="$_SF"
	fi
	# page history for tui.action.back: remember where we came from (not on a same-page reload, not while going back)
	if [[ "$canon" != "${_TUI_MARKUP_FILE:-}" && -n "${_TUI_MARKUP_FILE:-}" && -z "$_TUI_GOING_BACK" ]]; then
		_TUI_PAGE_HISTORY+=("$_TUI_MARKUP_FILE")
		((${#_TUI_PAGE_HISTORY[@]} > 30)) && _TUI_PAGE_HISTORY=("${_TUI_PAGE_HISTORY[@]:1}")
	fi

	# One synchronized frame: the terminal never shows the cleared, half-built page.
	((_TUI_RUNNING)) && mode.sync_start
	# a page of the live shell (not a reload of the current page): only the previous page's panes and widgets go
	local _gt_soft=0 _gt_fid="$_TUI_FOCUS_ID" _gt_fcur=$_TUI_CURSOR
	if [[ -n "$_TUI_SHELL_FILE" && "$canon" != "${_TUI_MARKUP_FILE:-}" ]]; then
		_tui_shell.scan "$canon"
		[[ "$_SH_OF" == "$_TUI_SHELL_FILE" ]] && _gt_soft=1
	fi
	if ((_gt_soft)); then
		_SHL_SOFT=1
		_tui_store.save_page
		_tui_store.save_focus
		_tui_store.flush_disk
		_tui_shell.leave_page
	else
		_tui_store.save_page
		_tui_store.save_focus
		_tui_store.flush_disk
		tui.reset_ui
	fi
	# on_visit code often ends with tui.render (layout changes); the render below covers it, so skip those.
	# A goto made from inside an on_visit leaves the decision to the outermost goto.
	local _gt_defer=$_TUI_DEFER_RENDER
	_TUI_DEFER_RENDER=1
	tui.load_cached "$resolved"
	_TUI_DEFER_RENDER=$_gt_defer
	_tui_store.restore_page
	_SHL_SOFT=0
	if ((_gt_soft)); then
		_tui_shell.enter_focus "$_gt_fid" "$_gt_fcur" "$carry"
	elif [[ -n "$keep_id" && -n "${_TUI_W_TYPE[$keep_id]:-}" ]]; then
		_tui_focus.ensure
		if [[ -n "${_TUI_FOCUS_POS[$keep_id]+x}" ]]; then
			_TUI_FOCUS_ID="$keep_id"
			_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[$keep_id]}"
			_TUI_CURSOR=$keep_cur
		fi
	else
		_tui_store.enter_focus "$carry"
	fi
	if ((_TUI_RUNNING)); then
		tui.render
		mode.sync_end
	fi
	tui.hook.fire page "$resolved"
}

# tui.start FILE - full lifecycle for a config-driven TUI: init, load, run, and
# guaranteed cleanup, so callers only need to hand over a markup file.
tui.start() {
	local file="$1"
	_TUI_APP_DIR="$(cd "$(dirname "$file")" 2>/dev/null && pwd)"
	[[ -z "${TUI_THEMES_DIR:-}" && -d "$_TUI_APP_DIR/themes" ]] && TUI_THEMES_DIR="$_TUI_APP_DIR/themes"
	[[ -z "${TUI_THEMES_DIR:-}" && -d "$TUI_DEFAULTS_DIR/themes" ]] && TUI_THEMES_DIR="$TUI_DEFAULTS_DIR/themes"
	[[ -r "$file" ]] || {
		echo "tui.start: cannot read '$file'" >&2
		return 1
	}

	_tui_validate.gate "$file" || return 1

	tui.init
	if ! tui.load "$file"; then
		_master_cleanup
		return 1
	fi
	_tui_store.restore_page
	_tui_store.enter_focus
	_tui_validate.notify
	tui.run
}
