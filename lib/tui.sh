#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  tui.sh - Terminal UI & Background Execution Framework                     ║
# ║  Built on terminal_controls.sh + colors.sh                                 ║
# ║  Provides: weighted layout panes, buttons, input fields, labels,           ║
# ║  mouse click routing, Tab/Shift-Tab focus cycling, and live                ║
# ║  background process streaming with pseudo-terminal (PTY) support.          ║
# ║                                                                            ║
# ║  Usage:                                                                    ║
# ║    source tui.sh                                                           ║
# ║                                                                            ║
# ║    tui.init                                                                ║
# ║                                                                            ║
# ║    tui.hsplit "root" "main:75" "sidebar:25"                                ║
# ║    tui.exec "ping google.com" "main" "sidebar"                             ║
# ║    tui.run                                                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # the lib/ folder, symlinks resolved
# shellcheck source=tui_configuration.sh
source "${SCRIPT_DIR}/tui_configuration.sh"
# shellcheck source=state.sh
source "${SCRIPT_DIR}/state.sh"
# shellcheck source=perf.sh
source "${SCRIPT_DIR}/perf.sh"
# shellcheck source=layout/tui_layout.sh
source "${SCRIPT_DIR}/layout/tui_layout.sh"
# shellcheck source=terminal_controls.sh
source "${SCRIPT_DIR}/terminal_controls.sh"
# shellcheck source=render/tui_emit.sh
source "${SCRIPT_DIR}/render/tui_emit.sh"
# shellcheck source=render/tui_canvas.sh
source "${SCRIPT_DIR}/render/tui_canvas.sh"
# shellcheck source=render/tui_paint.sh
source "${SCRIPT_DIR}/render/tui_paint.sh"
# shellcheck source=render/tui_rowcache.sh
source "${SCRIPT_DIR}/render/tui_rowcache.sh"
# shellcheck source=input/tui_hit.sh
source "${SCRIPT_DIR}/input/tui_hit.sh"
# shellcheck source=input/tui_focus.sh
source "${SCRIPT_DIR}/input/tui_focus.sh"
# shellcheck source=layout/tui_scroll.sh
source "${SCRIPT_DIR}/layout/tui_scroll.sh"
# shellcheck source=layout/tui_frame.sh
source "${SCRIPT_DIR}/layout/tui_frame.sh"
# shellcheck source=layout/tui_resize.sh
source "${SCRIPT_DIR}/layout/tui_resize.sh"
# shellcheck source=layout/tui_collapse.sh
source "${SCRIPT_DIR}/layout/tui_collapse.sh"
# shellcheck source=state_api.sh
source "${SCRIPT_DIR}/state_api.sh"
# shellcheck source=state/tui_store.sh
source "${SCRIPT_DIR}/state/tui_store.sh"
# shellcheck source=colors.sh
source "${SCRIPT_DIR}/colors.sh"
# shellcheck source=tui_home.sh
source "${SCRIPT_DIR}/tui_home.sh"
_tui_plugin.own() { :; } # replaced by tui_plugin.sh; modules sourced before it may already register things
# shellcheck source=markup/tui_node.sh
source "${SCRIPT_DIR}/markup/tui_node.sh"
# shellcheck source=markup/tui_markup.sh
source "${SCRIPT_DIR}/markup/tui_markup.sh"
# shellcheck source=markup/tui_parse.sh
source "${SCRIPT_DIR}/markup/tui_parse.sh"
# shellcheck source=markup/tui_validate.sh
source "${SCRIPT_DIR}/markup/tui_validate.sh"
# shellcheck source=style/tui_style.sh
source "${SCRIPT_DIR}/style/tui_style.sh"
# shellcheck source=tui_registry.sh
source "${SCRIPT_DIR}/tui_registry.sh"
# shellcheck source=widgets/tui_widget_contract.sh
source "${SCRIPT_DIR}/widgets/tui_widget_contract.sh"
# shellcheck source=markup/tui_ops.sh
source "${SCRIPT_DIR}/markup/tui_ops.sh"
# shellcheck source=markup/tui_compose.sh
source "${SCRIPT_DIR}/markup/tui_compose.sh"
# shellcheck source=markup/tui_addon.sh
source "${SCRIPT_DIR}/markup/tui_addon.sh"
# shellcheck source=markup/tui_build.sh
source "${SCRIPT_DIR}/markup/tui_build.sh"
# shellcheck source=markup/tui_refresh.sh
source "${SCRIPT_DIR}/markup/tui_refresh.sh"
# shellcheck source=markup/tui_shell.sh
source "${SCRIPT_DIR}/markup/tui_shell.sh"
# shellcheck source=markup/tui_factory.sh
source "${SCRIPT_DIR}/markup/tui_factory.sh"
# shellcheck source=tui_api.sh
source "${SCRIPT_DIR}/tui_api.sh"
# shellcheck source=input/tui_input.sh
source "${SCRIPT_DIR}/input/tui_input.sh"
# shellcheck source=input/tui_mouse.sh
source "${SCRIPT_DIR}/input/tui_mouse.sh"
# shellcheck source=chrome/tui_modal.sh
source "${SCRIPT_DIR}/chrome/tui_modal.sh"
# shellcheck source=chrome/tui_cmd.sh
source "${SCRIPT_DIR}/chrome/tui_cmd.sh"
# shellcheck source=chrome/tui_footer.sh
source "${SCRIPT_DIR}/chrome/tui_footer.sh"
# shellcheck source=chrome/tui_dialog.sh
source "${SCRIPT_DIR}/chrome/tui_dialog.sh"
# shellcheck source=core/tui_loop.sh
source "${SCRIPT_DIR}/core/tui_loop.sh"
# shellcheck source=exec/tui_exec.sh
source "${SCRIPT_DIR}/exec/tui_exec.sh"
# shellcheck source=tui_job.sh
source "${SCRIPT_DIR}/tui_job.sh"
# shellcheck source=widgets/tui_text.sh
source "${SCRIPT_DIR}/widgets/tui_text.sh"
# shellcheck source=widgets/tui_widgets.sh
source "${SCRIPT_DIR}/widgets/tui_widgets.sh"
# shellcheck source=config/tui_config.sh
source "${SCRIPT_DIR}/config/tui_config.sh"
# shellcheck source=plugin/tui_plugin.sh
source "${SCRIPT_DIR}/plugin/tui_plugin.sh"
# shellcheck source=apps/tui_sync.sh
source "${SCRIPT_DIR}/apps/tui_sync.sh"
# shellcheck source=apps/tui_install.sh
source "${SCRIPT_DIR}/apps/tui_install.sh"
# shellcheck source=apps/tui_update.sh
source "${SCRIPT_DIR}/apps/tui_update.sh"
# shellcheck source=markup/tui_cache.sh
source "${SCRIPT_DIR}/markup/tui_cache.sh"

# ═══════════════════════════════════════════════════════════════════════
#  INTERNAL STATE (UI & LAYOUT)
# ═══════════════════════════════════════════════════════════════════════
#  Pane geometry/tree, widget registries, focus/hover/drag state, and the
#  input byte-pushback/escape-sequence buffers all live in state.sh next
#  to this file - see it for the full field-by-field list.
# ═══════════════════════════════════════════════════════════════════════

declare -g _TUI_TICK_FN=""

# Additive tick listeners, separate from the single-slot _TUI_TICK_FN a
# page sets for its own per-frame work (e.g. a dashboard's own refresh
# cadence). tui.exec registers itself here instead of overwriting
# _TUI_TICK_FN, so a page's own tick function and any number of running
# tui.exec instances all get ticked every frame without clobbering each
# other - the exact problem the old single-instance tui.exec had: any
# page that both drove its own _TUI_TICK_FN and called tui.exec would
# have one silently stop firing.
declare -ga _TUI_TICK_LISTENERS=()
tui.tick.add() {
	local fn="$1" existing
	for existing in "${_TUI_TICK_LISTENERS[@]}"; do
		[[ "$existing" == "$fn" ]] && return
	done
	_TUI_TICK_LISTENERS+=("$fn")
	_tui_plugin.own tick "$fn"
}
tui.tick.remove() {
	local fn="$1" existing
	local -a out=()
	for existing in "${_TUI_TICK_LISTENERS[@]}"; do
		[[ "$existing" == "$fn" ]] || out+=("$existing")
	done
	_TUI_TICK_LISTENERS=("${out[@]}")
}

# Optional observability hook, same idiom as _TUI_TICK_FN: if set, called
# with a one-line description of every DISPATCHED input event (a motion
# report the mouse-coalescer discarded never reaches this - only what
# actually got acted on). The framework doesn't know or care who sets
# this; it exists so a page (e.g. the debug page) can log/display input
# without the framework needing any debug-specific code of its own.
declare -g _TUI_ON_INPUT_EVENT=""
_tui._notify_input() { [[ -n "$_TUI_ON_INPUT_EVENT" ]] && "$_TUI_ON_INPUT_EVENT" "$1"; }

# ═══════════════════════════════════════════════════════════════════════
#  LOGGING
# ═══════════════════════════════════════════════════════════════════════

# tui.log MSG [LEVEL] - append to $TUI_LOG_DIR/<yyyy-mm-dd>_<TUI_APP_NAME>.log (stdout is the screen).
# Fork-free once the dir exists; the file name follows the date, so a run past midnight rolls over.
declare -g _TUI_LOG_DIR_OK=""
tui.log.file() {
	local d
	printf -v d '%(%Y-%m-%d)T' -1
	printf '%s\n' "$TUI_LOG_DIR/${d}_${TUI_APP_NAME}.log"
}
tui.log() {
	local ts
	printf -v ts '%(%Y-%m-%d %H:%M:%S)T' -1
	if [[ "$_TUI_LOG_DIR_OK" != "$TUI_LOG_DIR" ]]; then
		[[ -d "$TUI_LOG_DIR" ]] || mkdir -p "$TUI_LOG_DIR" 2>/dev/null
		_TUI_LOG_DIR_OK="$TUI_LOG_DIR"
	fi
	printf '[%s] [%s] %s\n' "${ts#* }" "${2:-info}" "$1" 2>/dev/null >>"$TUI_LOG_DIR/${ts%% *}_${TUI_APP_NAME}.log" || return 0 # never fail a caller
}
tui.log.debug() { tui.log "$1" "debug"; }
tui.log.info() { tui.log "$1" "info"; }
tui.log.warn() { tui.log "$1" "warn"; }
tui.log.error() { tui.log "$1" "error"; }

# ═══════════════════════════════════════════════════════════════════════
#  INIT / CLEANUP
# ═══════════════════════════════════════════════════════════════════════

tui.init() {
	# Installed here, not in tui.run: a tiling WM can still be settling the
	# window (or a slow cache warm-up can still be running behind the
	# splash) for a while between tui.init and tui.run's first render. A
	# WINCH in that window used to have no handler at all and was lost -
	# the first frame then rendered at whatever (possibly stale/pre-resize)
	# size term.size read here, with nothing to correct it until the NEXT
	# resize. tui.run's own loop applies the flag this sets before its own
	# first render (see _tui._apply_resize below).
	trap 'tui.on_resize' WINCH
	tui.config.apply # saved framework settings (theme overlay, default-key groups, input behaviour)
	_TUI_OLD_STTY=$(stty -g 2>/dev/null)
	# Every key belongs to the app, none is interpreted by the tty driver:
	#   -isig    ctrl+c / ctrl+z / ctrl+\ arrive as keys (copy, undo...) instead of SIGINT / SIGTSTP / SIGQUIT
	#   -ixon    ctrl+s / ctrl+q are not flow control        -iexten  ctrl+v / ctrl+o / ctrl+y are not "literal next" / discard / dsusp
	#   -echo -icanon  nothing is echoed to the screen, no line buffering: the shell never sees what was typed
	# (quit is q / ctrl+q; tui.cleanup drains unread input and restores the old settings)
	stty -echo -icanon -isig -ixon -iexten min 1 time 0 2>/dev/null

	term.alt_screen
	cur.hide
	erase.all

	mouse.any_on
	mouse.sgr_on
	printf '\e[?2004h' # bracketed paste: pastes arrive as one "paste" event, not fake keystrokes

	term.size _TUI_ROWS _TUI_COLS

	_ps.panes.set root row 1
	_ps.panes.set root col 1
	_ps.panes.set root h "$_TUI_ROWS"
	_ps.panes.set root w "$_TUI_COLS"
	_ps.panes.set root border "single"
	_ps.panes.set root title ""
	_TUI_P_LEAVES=(root)
	_TUI_P_ALL=(root)
	_tui_home.touch    # app.meta: last run, run count, versions
	tui.plugin.startup # discover and enable plugins (saved on/off state, else each plugin's default)
	tui.hook.fire init
}

# _tui_proc_running PID - rc 0 while PID is alive and not a zombie (a child we have not wait()ed for still answers
# `kill -0`). /proc where there is one, `kill -0` elsewhere.
_tui_proc_running() {
	local line st
	if [[ -r "/proc/$1/stat" ]]; then
		read -r line <"/proc/$1/stat" 2>/dev/null || return 1
		st="${line##*) }"
		[[ "${st:0:1}" != Z ]]
	else
		kill -0 "$1" 2>/dev/null
	fi
}

# _tui_proc_tree PID - appends PID's descendants, deepest first, then PID itself, to _TUI_PTREE
_tui_proc_tree() {
	local child kids=""
	# /proc/PID/task/PID/children where the kernel has it (no fork); pgrep scans all of /proc, ~25 ms here
	if [[ -r "/proc/$1/task/$1/children" ]]; then
		read -r kids <"/proc/$1/task/$1/children" 2>/dev/null
	else
		kids="$(pgrep -P "$1" 2>/dev/null)"
	fi
	for child in $kids; do
		_tui_proc_tree "$child"
	done
	_TUI_PTREE+=("$1")
}

# SIGTERM the whole tree (children first), wait once for all of it for up to 50 ms polled every 5 ms, then SIGKILL
# whatever is still running. It used to sleep a full 50 ms after every process: 150 ms for a three-level tree.
# An interactive shell ignores SIGTERM but exits on SIGHUP, so whatever survives the first poll gets a SIGHUP: leaving a
# page that runs a shell cost the full 50 ms wait plus the kill.
_kill_process_tree() {
	local -a _TUI_PTREE=()
	local p i left
	_tui_proc_tree "$1"
	for p in "${_TUI_PTREE[@]}"; do kill -TERM "$p" 2>/dev/null; done
	for i in 1 2 3 4 5 6 7 8 9 10; do
		left=0
		for p in "${_TUI_PTREE[@]}"; do _tui_proc_running "$p" && left=1 && break; done
		((left)) || return 0
		if ((i == 2)); then
			for p in "${_TUI_PTREE[@]}"; do _tui_proc_running "$p" && kill -HUP "$p" 2>/dev/null; done
		fi
		read -rt 0.005 <> <(:)
	done
	for p in "${_TUI_PTREE[@]}"; do _tui_proc_running "$p" && kill -KILL "$p" 2>/dev/null; done
	return 0
}

# _tui._drain_input : throw away bytes the terminal already sent (mouse reports, keys typed during shutdown) so they are not
# handed to the shell that starts next
_tui._drain_input() {
	local _d n=0
	[[ -t 0 ]] || return 0
	while ((n++ < 4096)) && IFS= read -rsn1 -t 0.02 _d; do :; done
}

# tui.cleanup : restore terminal state and clean up TUI environment
tui.cleanup() {
	mouse.any_off
	mouse.sgr_off
	printf '\e[?2004l'
	style.reset
	cur.show
	term.main_screen
	_tui._drain_input
	stty "$_TUI_OLD_STTY" 2>/dev/null
}

_master_cleanup() {
	_tui_store.exit 2>/dev/null    # persisted page state goes to disk
	tui.hook.fire exit 2>/dev/null # plugins give back what they changed (terminal shortcuts, files ...)
	tui.cache.cleanup 2>/dev/null
	_tui_api.shutdown 2>/dev/null
	_exec_cleanup_all 2>/dev/null
	tui.cleanup 2>/dev/null
	# Hard reset terminal state (ANSI resets + stty cooked mode)
	printf "\e[0m\e[?25h\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1049l\r\n"
	stty sane 2>/dev/null
	stty echo 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════
#  PANE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════

tui.hsplit() { _tui._split "h" "$@"; }
tui.vsplit() { _tui._split "v" "$@"; }

_tui._split() {
	local dir="$1" parent="$2"
	shift 2
	local names="" weights=""

	for spec in "$@"; do
		local n="${spec%%:*}" w=1
		[[ "$spec" == *:* ]] && w="${spec#*:}"
		names+="${names:+ }$n"
		weights+="${weights:+ }$w"
		_ps.panes.set "$n" border "single"
		_ps.panes.set "$n" title ""
	done

	_ps.panes.set "$parent" dir "$dir"
	_ps.panes.set "$parent" children "$names"
	_ps.panes.set "$parent" weights "$weights"
	_tui.layout_bump

	_tui._layout "$parent"

	_TUI_P_LEAVES=()
	_TUI_P_ALL=()
	_tui._collect_leaves "root"
}

# tui.fixed PARENT SIZE_W SIZE_H CHILD[:SPAN[:nl]]...
#   Fixed-size grid: every child is exactly SIZE_W x SIZE_H cells (times its
#   SPAN in width - a wide key is SPAN units wide), flowed left-to-right and
#   wrapped when the row is full or a child is marked "nl" (start a new row).
#   Children that don't fit get a 0x0 rect and are not drawn.
#   Unlike hsplit/vsplit/grid, sizes never stretch with the window - that is
#   the point: rows of identical, aligned elements (keyboards, tile walls).
tui.fixed() {
	local parent="$1" sw="$2" sh="$3"
	shift 3
	local names="" spec n rest span nl
	for spec in "$@"; do
		n="${spec%%:*}"
		rest=""
		[[ "$spec" == *:* ]] && rest="${spec#*:}"
		span="${rest%%:*}"
		nl=""
		[[ "$rest" == *:* ]] && nl="${rest#*:}"
		[[ "$span" =~ ^[0-9]+$ ]] || span=1
		names+="${names:+ }$n"
		_ps.panes.set "$n" span "$span"
		if [[ -n "$nl" ]]; then _TUI_P_NEWLINE[$n]=1; else unset '_TUI_P_NEWLINE[$n]'; fi
		_ps.panes.set "$n" border "none"
		_ps.panes.set "$n" title ""
	done

	_ps.panes.set "$parent" dir "f"
	_ps.panes.set "$parent" children "$names"
	_ps.panes.set "$parent" weights ""
	_ps.panes.set "$parent" cellw "$sw"
	_ps.panes.set "$parent" cellh "$sh"
	_tui.layout_bump

	_tui._layout "$parent"

	_TUI_P_LEAVES=()
	_TUI_P_ALL=()
	_tui._collect_leaves "root"
}

# state:direct
_tui._layout_fixed() {
	local p="$1" pr="$2" pc="$3" ph="$4" pw="$5"
	local cw=${_TUI_P_CELLW[$p]:-1} chh=${_TUI_P_CELLH[$p]:-1}
	local -a ch
	read -ra ch <<<"${_TUI_P_CHILDREN[$p]}"
	local x=0 y=0 name w
	for name in "${ch[@]}"; do
		w=$((${_TUI_P_SPAN[$name]:-1} * cw))
		if [[ -n "${_TUI_P_NEWLINE[$name]:-}" ]] || ((x > 0 && x + w > pw)); then
			((x > 0)) && {
				x=0
				((y += chh))
			}
		fi
		if ((w > pw || y + chh > ph)); then
			_ps.panes.set "$name" row "$pr"
			_ps.panes.set "$name" col "$pc"
			_ps.panes.set "$name" h 0
			_ps.panes.set "$name" w 0
		else
			_ps.panes.set "$name" row "$((pr + y))"
			_ps.panes.set "$name" col "$((pc + x))"
			_ps.panes.set "$name" h "$chh"
			_ps.panes.set "$name" w "$w"
			((x += w))
		fi
		[[ -n "${_TUI_P_CHILDREN[$name]:-}" ]] && _tui._layout_r "$name"
	done
}

# Smallest integer i such that i*i >= n (i.e. ceil(sqrt(n))), for picking a
# roughly-square grid shape when neither rows nor cols was specified. n is
# always a small cell count here, so a linear search is fine - this runs
# once per grid build, never per-frame.
_tui._ceil_sqrt() {
	local n="$1" i=1
	((n <= 1)) && {
		printf '1'
		return
	}
	while ((i * i < n)); do ((i++)); done
	printf '%s' "$i"
}

# tui.grid PARENT ROWS COLS FIT ROW_WEIGHTS COL_WEIGHTS NAME...
#
# Pure-geometry grid constructor, sitting alongside tui.hsplit/tui.vsplit:
# builds PARENT as a vsplit of ROWS row-panes, each an hsplit of COLS
# cell-panes, and assigns the given NAME... list to cells in row-major
# order (one name per cell; an empty string leaves that cell blank).
#
# ROWS and/or COLS may be passed as "" to size the grid from how many
# names were given: only COLS given -> ROWS = ceil(N/COLS); only ROWS
# given -> COLS = ceil(N/ROWS); neither given -> a roughly-square grid.
#
# FIT is "pack" (default: every row gets the full COLS cells, blanks
# render as empty placeholder panes) or "stretch" (a row's blank cells are
# dropped instead, so its populated cells expand to fill the row).
#
# This function does not know about "explicit vs. auto-flow placement" -
# callers (the markup parser's <pane split="grid"> handler, or
# tui.factory.grid) are responsible for resolving that into a flat,
# row-major NAME list before calling this, the same way callers of
# tui.hsplit/tui.vsplit are responsible for deciding their own name:weight
# lists.
declare -ga _TUI_LAST_GRID_ROWS=()  # row-wrapper pane ids from the most recent tui.grid call
declare -ga _TUI_LAST_GRID_CELLS=() # cell pane ids from it, row-major, blanks included

tui.grid() {
	local parent="$1" rows="$2" cols="$3" fit="${4:-pack}"
	local row_weights="$5" col_weights="$6"
	shift 6
	local -a names=("$@")
	local n=${#names[@]}

	if [[ -z "$cols" && -z "$rows" ]]; then
		cols=$(_tui._ceil_sqrt "$n")
		rows=$(((n + cols - 1) / cols))
	elif [[ -z "$cols" ]]; then
		cols=$(((n + rows - 1) / rows))
	elif [[ -z "$rows" ]]; then
		rows=$(((n + cols - 1) / cols))
	fi
	((rows < 1)) && rows=1
	((cols < 1)) && cols=1

	local -a rw cw
	read -ra rw <<<"${row_weights:-}"
	read -ra cw <<<"${col_weights:-}"

	local -a row_specs=()
	local r c
	for ((r = 0; r < rows; r++)); do
		row_specs+=("${parent}_row${r}:${rw[$r]:-1}")
	done
	tui.vsplit "$parent" "${row_specs[@]}"

	_TUI_LAST_GRID_ROWS=()
	_TUI_LAST_GRID_CELLS=()
	for ((r = 0; r < rows; r++)); do
		local rid="${parent}_row${r}"
		_TUI_LAST_GRID_ROWS+=("$rid")
		local -a cell_specs=()
		for ((c = 0; c < cols; c++)); do
			local ni=$((r * cols + c))
			local nm="${names[$ni]:-}"
			if [[ -z "$nm" ]]; then
				[[ "$fit" == "stretch" ]] && continue
				nm="${rid}_c${c}_blank"
			fi
			cell_specs+=("${nm}:${cw[$c]:-1}")
			_TUI_LAST_GRID_CELLS+=("$nm")
		done
		((${#cell_specs[@]} == 0)) && continue
		tui.hsplit "$rid" "${cell_specs[@]}"
	done
}

_tui._collect_leaves() {
	local id="$1"
	_TUI_P_ALL+=("$id")
	if [[ -z "${_TUI_P_CHILDREN[$id]:-}" ]]; then
		_TUI_P_LEAVES+=("$id")
	else
		local ch
		read -ra ch <<<"${_TUI_P_CHILDREN[$id]}"
		for c in "${ch[@]}"; do _tui._collect_leaves "$c"; done
	fi
}

# _tui._layout P - one full layout pass, timed as a single span even though
# _tui._layout_r below recurses into every descendant pane: only the
# top-level call is timed, so a span's begin/end pair is never clobbered by
# a nested begin overwriting the outer call's start time.
# state:direct
_tui._layout() {
	_TUI_HZ_DIRTY=1
	_tui_perf.begin layout
	_tui._layout_r "$1"
	# Settle scroll offsets for all leaf panes with vertical scroll after geometry is final
	local _lp
	for _lp in "${_TUI_P_LEAVES[@]}"; do
		[[ "${_TUI_P_SCROLL[$_lp]:-none}" == @(v|both) ]] && _tui_scroll.settle "$_lp"
	done
	_tui_perf.end layout
}

# state:direct
_tui._layout_r() {
	local p="$1"
	local dir="${_TUI_P_DIR[$p]:-}"
	[[ -z "$dir" ]] && return

	# Memoization (2A): a pane's whole subtree is safe to skip when its own
	# (row,col,h,w) match the last pass AND nothing layout-relevant has
	# mutated ANYWHERE since (the global _TUI_LY_GEN counter - see
	# lib/layout/tui_layout.sh's header comment). Coarser than per-subtree
	# dirty tracking but never stale: any split/gap/pad/border/max_* change,
	# or a cache-replay boundary (_tui_cache_relayout), bumps it. This is
	# what closes tools/bench/run.sh's resize_relayout back within G3 after
	# routing every split through the fr/clamp engine (2A) made the first
	# pass alone ~1.7x slower than the old inline arithmetic.
	_tui.layout_cache_hit "$p" "${_TUI_P_ROW[$p]} ${_TUI_P_COL[$p]} ${_TUI_P_H[$p]} ${_TUI_P_W[$p]}" && return

	# A parent's own border and vpad/hpad shrink the area its children
	# share; _tui._inset drops both when the parent is too small for them.
	_tui._inset "$p"
	local pr=$((${_TUI_P_ROW[$p]} + _IV)) pc=$((${_TUI_P_COL[$p]} + _IH))
	local ph=$((${_TUI_P_H[$p]} - 2 * _IV)) pw=$((${_TUI_P_W[$p]} - 2 * _IH))
	((ph < 1)) && ph=1
	((pw < 1)) && pw=1

	if [[ "$dir" == f ]]; then
		_tui._layout_fixed "$p" "$pr" "$pc" "$ph" "$pw"
		return
	fi

	local -a ch spec
	read -ra ch <<<"${_TUI_P_CHILDREN[$p]}"
	read -ra spec <<<"${_TUI_P_WEIGHTS[$p]}"
	local last=$((${#ch[@]} - 1))
	local gap=${_TUI_P_GAP[$p]:-0} avail
	((${#_TUI_P_FUSE[@]})) && _tui_frame.fused "$p" && gap=-1 # fused siblings overlap by one cell (tui_frame.sh)
	[[ "$dir" == "h" ]] && avail=$pw || avail=$ph

	# fast=1 while every child so far is a plain integer weight with no
	# max_width/max_height and gap=0 - today's overwhelmingly common case
	# (plain weight= splits). This first pass touches no _LY_* globals at
	# all, only local vars - tools/bench/run.sh's resize_relayout caught a
	# ~2.6x regression from unconditionally marshalling every split's specs
	# into _tui.layout_arrange's arrays even for this trivial case; a second
	# pass below builds those arrays and calls it, but only when this one
	# actually finds something the fast arithmetic can't handle (a unit
	# token, a max_width/max_height, or a gap).
	local i name s fast=1 total=0
	((gap != 0)) && fast=0
	if ((fast)); then
		for ((i = 0; i <= last; i++)); do
			name="${ch[$i]}"
			s="${spec[$i]:-1}"
			if [[ -n "$s" && "$s" != *[!0-9]* ]] &&
				{ [[ "$dir" == "h" ]] && [[ -z "${_TUI_P_MAXW[$name]:-}" ]] || [[ "$dir" != "h" && -z "${_TUI_P_MAXH[$name]:-}" ]]; }; then
				((total += s))
			else
				fast=0
				break
			fi
		done
	fi

	local -a sizes=()
	if ((fast)); then
		((total == 0)) && total=$((last + 1))
		local off=0
		for ((i = 0; i <= last; i++)); do
			s="${spec[$i]:-1}"
			if ((i == last)); then
				sizes[i]=$((avail - off))
			else
				sizes[i]=$((avail * s / total))
				((off += sizes[i]))
			fi
		done
	else
		# Per-child spec (plain weight, or a 2A unit token: N%, Nfr, auto,
		# fill, clamp(...)) plus its legacy max_width/max_height, now
		# correctly redistributed to siblings when it clamps (the old inline
		# loop just dropped the freed space). Legacy min_width/min_height
		# stay advisory-only (the "too small" warning) - real min
		# enforcement is opt-in via a clamp(...) spec itself, see
		# _tui.layout_arrange's own doc comment.
		_LY_SPECS=() _LY_MINS=() _LY_MAXS=()
		for ((i = 0; i <= last; i++)); do
			name="${ch[$i]}"
			_LY_SPECS[i]="${spec[$i]:-1}"
			_LY_MINS[i]=""
			[[ "$dir" == "h" ]] && _LY_MAXS[i]="${_TUI_P_MAXW[$name]:-}" || _LY_MAXS[i]="${_TUI_P_MAXH[$name]:-}"
		done
		_tui.layout_arrange "$avail" "$gap"
		sizes=("${_LY_SIZES[@]}") # local snapshot: recursing below overwrites the shared _LY_* globals
	fi

	local offset=0 size
	for ((i = 0; i <= last; i++)); do
		name="${ch[$i]}"
		size=${sizes[$i]:-0}

		if [[ "$dir" == "h" ]]; then
			_ps.panes.set "$name" row "$pr"
			_ps.panes.set "$name" col "$((pc + offset))"
			_ps.panes.set "$name" h "$ph"
			_ps.panes.set "$name" w "$size"
		else
			_ps.panes.set "$name" row "$((pr + offset))"
			_ps.panes.set "$name" col "$pc"
			_ps.panes.set "$name" h "$size"
			_ps.panes.set "$name" w "$pw"
		fi
		((offset += size))
		((i < last)) && ((offset += gap))

		[[ -n "${_TUI_P_CHILDREN[$name]:-}" ]] && _tui._layout_r "$name"
	done
}

tui.pane_title() { _TUI_P_TITLE[$1]="$2"; }
tui.pane_border() {
	_ps.panes.set "$1" border "$2"
	_ps.panes.set "$1" border_expl 1
	_tui.layout_bump # border changes _tui._inset, which shifts every child's rect
}
# tui.pane_pad ID HPAD VPAD - blank cols/rows on each side. Parent panes:
# gap between the frame and the children. Leaf panes: shrinks the area
# widgets and tui.output* may use.
tui.pane_pad() {
	[[ -n "$2" ]] && _TUI_P_HPAD[$1]="$2"
	[[ -n "$3" ]] && _TUI_P_VPAD[$1]="$3"
	_tui.layout_bump
}
tui.pad() {
	[[ -n "$2" ]] && _TUI_W_HPAD[$1]="$2"
	[[ -n "$3" ]] && _TUI_W_VPAD[$1]="$3"
}
# tui.pane_gap ID GAP - cells left blank between ID's children on its split axis (2A).
tui.pane_gap() {
	[[ -n "$2" ]] && _TUI_P_GAP[$1]="$2"
	_tui.layout_bump
}

# _tui._eff_border ID - sets _TB to the border style actually drawn.
# Parents only get a frame when border= was set explicitly. Any pane too
# small to keep >=1 content row/col inside its frame (and, for parents,
# room for bordered children) loses the frame, so nested borders collapse
# instead of eating the content.
# state:direct
_tui._eff_border() {
	local id="$1" b="${_TUI_P_BORDER[$1]:-single}"
	_TB=$b
	[[ "$b" == "none" ]] && return
	local h=${_TUI_P_H[$id]:-0} w=${_TUI_P_W[$id]:-0}
	if [[ -n "${_TUI_P_CHILDREN[$id]:-}" ]]; then
		if [[ -z "${_TUI_P_BORDER_EXPL[$id]:-}" ]] ||
			((h - 2 - 2 * ${_TUI_P_VPAD[$id]:-0} < 3 || w - 4 - 2 * ${_TUI_P_HPAD[$id]:-0} < 5)); then
			_TB=none
		fi
	elif ((h < 3 || w < 5)); then
		_TB=none
	fi
}

# _tui._inset ID - sets _IV/_IH: rows/cols taken on EACH side by border
# plus padding (pad clamped so >=1 row/col remains). Parents with no frame
# inset 0 border cols; leaves with no frame keep the legacy 1-col margin.
# state:direct
_tui._inset() {
	local id="$1" bv bh
	# _tui._eff_border inlined (one call fewer on every widget position and pane rect); keep the two in step
	local h=${_TUI_P_H[$id]:-0} w=${_TUI_P_W[$id]:-0} m
	_TB="${_TUI_P_BORDER[$id]:-single}"
	if [[ "$_TB" != none ]]; then
		if [[ -n "${_TUI_P_CHILDREN[$id]:-}" ]]; then
			if [[ -z "${_TUI_P_BORDER_EXPL[$id]:-}" ]] ||
				((h - 2 - 2 * ${_TUI_P_VPAD[$id]:-0} < 3 || w - 4 - 2 * ${_TUI_P_HPAD[$id]:-0} < 5)); then
				_TB=none
			fi
		elif ((h < 3 || w < 5)); then
			_TB=none
		fi
	fi
	if [[ "$_TB" != "none" ]]; then
		bv=1
		bh=2
	elif [[ -n "${_TUI_P_CHILDREN[$id]:-}" ]]; then
		bv=0
		bh=0
	else
		bv=0
		bh=1
	fi
	local vp=${_TUI_P_VPAD[$id]:-0} hp=${_TUI_P_HPAD[$id]:-0}
	m=$(((h - 1) / 2 - bv))
	((m < 0)) && m=0
	((vp > m)) && vp=$m
	m=$(((w - 1) / 2 - bh))
	((m < 0)) && m=0
	((hp > m)) && hp=$m
	_IV=$((bv + vp))
	_IH=$((bh + hp))
}

# _tui._content_rect ID - sets _CR_R/_CR_C/_CR_H/_CR_W (leaf output area).
_tui._content_rect() {
	_tui._inset "$1"
	_CR_R=$((${_TUI_P_ROW[$1]} + _IV))
	_CR_C=$((${_TUI_P_COL[$1]} + _IH))
	_CR_H=$((${_TUI_P_H[$1]} - 2 * _IV))
	_CR_W=$((${_TUI_P_W[$1]} - 2 * _IH))
	((_CR_H < 1)) && _CR_H=1
	((_CR_W < 1)) && _CR_W=1
}
tui.pane_align() { [[ -n "$2" ]] && _TUI_P_ALIGN[$1]="$2"; }
tui.pane_valign() { [[ -n "$2" ]] && _TUI_P_VALIGN[$1]="$2"; }
tui.pane_minsize() {
	[[ -n "$2" ]] && _TUI_P_MINW[$1]="$2"
	[[ -n "$3" ]] && _TUI_P_MINH[$1]="$3"
}
tui.pane_maxsize() {
	[[ -n "$2" ]] && _TUI_P_MAXW[$1]="$2"
	[[ -n "$3" ]] && _TUI_P_MAXH[$1]="$3"
	_tui.layout_bump # unlike min_*, max_* feeds real arrange math (fast-path check + _LY_MAXS)
}

tui.pane_scroll() {
	[[ -n "$2" ]] && _TUI_P_SCROLL[$1]="$2"
	_ps.panes.set "$1" soff_v 0
	_ps.panes.set "$1" soff_h 0
}

# tui.pane_scroll_into_view PANE true|false - sets whether focus scrolls vertically scrolling pane to reveal focused widget.
tui.pane_scroll_into_view() {
	local pane="$1" enable="$2"
	case "$enable" in
		false) _TUI_P_NOREVEAL[$pane]=1 ;;
		true | "") _TUI_P_NOREVEAL[$pane]=0 ;;
	esac
}

# ═══════════════════════════════════════════════════════════════════════
#  WIDGETS
# ═══════════════════════════════════════════════════════════════════════

tui.label() {
	local id="$1"
	if [[ -z "$id" || -z "$2" ]]; then
		echo "tui.label: missing id or pane, skipping widget" >&2
		return 1
	fi
	_ps.widgets.set "$id" type "label"
	_ps.widgets.set "$id" pane "$2"
	_ps.widgets.set "$id" row "$3"
	_ps.widgets.set "$id" label "$4"
	_ps.widgets.set "$id" value "$4"
	_TUI_W_ORDER+=("$id")
	_tui_w.changed
}

tui.button() {
	local id="$1"
	if [[ -z "$id" || -z "$2" ]]; then
		echo "tui.button: missing id or pane, skipping widget" >&2
		return 1
	fi
	_ps.widgets.set "$id" type "button"
	_ps.widgets.set "$id" pane "$2"
	_ps.widgets.set "$id" row "$3"
	_ps.widgets.set "$id" label "$4"
	_ps.widgets.set "$id" value ""
	_ps.widgets.set "$id" action "${5:-}"
	_TUI_W_ORDER+=("$id")
	_tui_w.changed
}

tui.input() {
	local id="$1"
	if [[ -z "$id" || -z "$2" ]]; then
		echo "tui.input: missing id or pane, skipping widget" >&2
		return 1
	fi
	local submit_fn="${6:-}"
	_ps.widgets.set "$id" type "input"
	_ps.widgets.set "$id" pane "$2"
	_ps.widgets.set "$id" row "$3"
	_ps.widgets.set "$id" ph "${4:-}"
	_ps.widgets.set "$id" label "${5:-}"
	_ps.widgets.set "$id" value ""
	_ps.widgets.set "$id" action ""
	_ps.widgets.set "$id" submit "${submit_fn}"
	_TUI_W_ORDER+=("$id")
	_tui_w.changed
}

tui.checkbox() {
	local id="$1"
	if [[ -z "$id" || -z "$2" ]]; then
		echo "tui.checkbox: missing id or pane, skipping widget" >&2
		return 1
	fi
	local checked="${5:-}"
	_ps.widgets.set "$id" type "checkbox"
	_ps.widgets.set "$id" pane "$2"
	_ps.widgets.set "$id" row "$3"
	_ps.widgets.set "$id" label "$4"
	case "$checked" in
		1 | true | yes) _TUI_W_VALUE[$id]="1" ;;
		*) _TUI_W_VALUE[$id]="0" ;;
	esac
	_ps.widgets.set "$id" action "${6:-}"
	_TUI_W_ORDER+=("$id")
	_tui_w.changed
}

# tui.checkbox.toggle ID - flips a checkbox's value, redraws it, and calls
# its action (if any) as ACTION ID VALUE (the id first, like every widget
# callback, then the new value "0"/"1"). The one place both
# activation paths (Enter on a focused checkbox, a mouse click on one)
# funnel through, so they can't drift out of sync with each other.
tui.checkbox.toggle() {
	local id="$1"
	[[ "${_TUI_W_TYPE[$id]:-}" == "checkbox" ]] || return
	local new="1"
	[[ "${_TUI_W_VALUE[$id]}" == "1" ]] && new="0"
	tui.update "$id" "$new"
	local action="${_TUI_W_ACTION[$id]:-}"
	[[ -n "$action" ]] && "$action" "$id" "$new"
}

# ═══════════════════════════════════════════════════════════════════════
#  TABS - a thin convenience layer over buttons + tui.grid, formalizing
#  the "row of header buttons that swap a content pane" pattern already
#  hand-rolled identically in more than one demo page. No new drawing or
#  hit-testing primitive: a tab header is an ordinary button living in an
#  ordinary tui.grid cell, and "active" reuses the widget focus this
#  framework already has rather than inventing a second notion of it.
# ═══════════════════════════════════════════════════════════════════════

declare -gA _TUI_TABS_ACTIVE=()       # tabs id -> currently active tab id
declare -gA _TUI_TABS_CONTENT_PANE=() # tabs id -> its content pane id
declare -gA _TUI_TABS_COMPACT=()      # tabs id -> "true" for the borderless header style
declare -gA _TUI_TAB_TEXT=()          # tab id -> header button text
declare -gA _TUI_TAB_ACTION=()        # tab id -> developer's on-activate callback
declare -gA _TUI_TAB_DEFAULT=()       # tab id -> "true" if it starts active
declare -gA _TUI_TAB_GROUP=()         # tab id -> owning tabs id

# tui.tabs.compact TABS_ID [true|false] - call before tui.tabs.build to pick
# the header style: framed (default) draws each header cell as its own
# bordered box, needing at least 3 rows (top border, label, bottom border).
# compact drops the frame entirely - each header is a borderless,
# background-color-filled cell needing only 1 row, with the active tab
# indicated by a bg color change (via the .tab_header_compact:focus class)
# instead of a border. Pick compact wherever the header's own pane doesn't
# have 3 rows to spare.
tui.tabs.compact() { _TUI_TABS_COMPACT[$1]="${2:-true}"; }

# tui.tabs.add TAB_ID TEXT ACTION [DEFAULT] - registers one tab's data
# ahead of tui.tabs.build, which needs the full set of tabs at once (to
# lay out the header row as a single tui.grid).
tui.tabs.add() {
	local tab_id="$1" text="$2" action="$3" is_default="${4:-}"
	_TUI_TAB_TEXT[$tab_id]="$text"
	_TUI_TAB_ACTION[$tab_id]="$action"
	_TUI_TAB_DEFAULT[$tab_id]="$is_default"
}

# tui.tabs.build TABS_ID HEADER_PANE CONTENT_PANE TAB_ID...
# Lays the header buttons out as a 1-row tui.grid across HEADER_PANE, then
# activates whichever tab was marked default (or the first one).
tui.tabs.build() {
	local tabs_id="$1" header_pane="$2" content_pane="$3"
	shift 3
	local -a tab_ids=("$@")
	((${#tab_ids[@]} == 0)) && return

	_TUI_TABS_CONTENT_PANE[$tabs_id]="$content_pane"

	local -a cell_names=()
	local tid
	for tid in "${tab_ids[@]}"; do
		cell_names+=("${header_pane}_${tid}_cell")
	done
	tui.grid "$header_pane" 1 "${#tab_ids[@]}" pack "" "" "${cell_names[@]}"

	# A tab header clipping its label when there isn't room is normal,
	# expected UI behavior (the same as nav sidebar buttons already do) -
	# not a real "this pane is broken" situation the content-fit checker
	# should flag, especially with more tabs than a header row has spare
	# width for. Opt every cell out of it.
	local cell
	for cell in "${cell_names[@]}"; do
		tui.pane_strict_fit "$cell" false
	done

	local compact=0
	[[ "${_TUI_TABS_COMPACT[$tabs_id]:-}" == "true" ]] && compact=1
	local cell_class="tab_header"
	if ((compact)); then
		cell_class="tab_header_compact"
		local cell
		for cell in "${cell_names[@]}"; do
			tui.pane_border "$cell" "none"
		done
	fi

	local default_tab=""
	for tid in "${tab_ids[@]}"; do
		_TUI_TAB_GROUP[$tid]="$tabs_id"
		tui.button "$tid" "${header_pane}_${tid}_cell" 0 "${_TUI_TAB_TEXT[$tid]:-$tid}" _tui._tab_activate
		tui.align "$tid" fill
		_tui_cache_class "$tid" "$cell_class"
		[[ "${_TUI_TAB_DEFAULT[$tid]:-}" == "true" ]] && default_tab="$tid"
	done
	[[ -z "$default_tab" ]] && default_tab="${tab_ids[0]}"
	tui.tabs.activate "$default_tab"
}

_tui._tab_activate() { tui.tabs.activate "$1"; }

# tui.tabs.activate TAB_ID - makes TAB_ID the active tab in its group:
# focuses its header button (reusing this framework's existing focus
# styling as the "active" indicator instead of a second style state) and
# calls the developer's own action, which is exactly the unchanged body
# of whatever callback already populates that content pane today.
tui.tabs.activate() {
	local tab_id="$1"
	local tabs_id="${_TUI_TAB_GROUP[$tab_id]:-}"
	[[ -z "$tabs_id" ]] && return
	_TUI_TABS_ACTIVE[$tabs_id]="$tab_id"
	tui.focus "$tab_id"
	local action="${_TUI_TAB_ACTION[$tab_id]:-}"
	[[ -n "$action" ]] && "$action" "$tab_id"
}

# tui.get ID [VAR] - the widget's value: printed, or (with VAR) stored in VAR, which costs no subshell
tui.get() {
	if [[ -n "${2:-}" ]]; then
		local -n _tg_out="$2"
		_tg_out="${_TUI_W_VALUE[$1]:-}"
	else
		printf '%s' "${_TUI_W_VALUE[$1]:-}"
	fi
}
tui.set() { _TUI_W_VALUE[$1]="$2"; }
tui.update() {
	if [[ -z "$1" || -z "${_TUI_W_TYPE[$1]:-}" ]]; then
		tui.notify "Cannot update widget '$1': it does not exist." error
		return 1
	fi

	_ps.widgets.set "$1" value "$2"
	_tui._draw_widget "$1"
}
tui.on_action() { _TUI_W_ACTION[$1]="$2"; }
tui.on_submit() { _TUI_W_SUBMIT[$1]="$2"; }
tui.align() { [[ -n "$2" ]] && _TUI_W_ALIGN[$1]="$2"; }
tui.valign() { [[ -n "$2" ]] && _TUI_W_VALIGN[$1]="$2"; }
tui.minsize() {
	[[ -n "$2" ]] && _TUI_W_MINW[$1]="$2"
	[[ -n "$3" ]] && _TUI_W_MINH[$1]="$3"
}
tui.maxsize() {
	[[ -n "$2" ]] && _TUI_W_MAXW[$1]="$2"
	[[ -n "$3" ]] && _TUI_W_MAXH[$1]="$3"
}
# tui.expand ID x|y|both - which dims _tui._widget_pos fills to the pane's content area (2A: the
# generic replacement for the old hardcoded textarea/list/table row-span case; see
# docs/api/widgets/tui.expand.md). list/table/textarea default to "y"; call this to override (e.g.
# opt a textarea back out to a fixed row count). "x" is currently a no-op (width already fills by
# default) - accepted for forward compatibility, per the doc.
tui.expand() { _TUI_W_EXPAND[$1]="$2"; }
# tui.pin ID VALUE - pin a widget to the top of its scrolling pane. When VALUE is "top", the widget
# scrolls with content until it would leave the viewport top, then stays pinned on the first viewport
# row (sticky header). Only "top" is recognized; other values are ignored. At most one pinned widget
# is stuck at a time; if multiple pass the scroll threshold, the one with the largest row wins.
tui.pin() { [[ "$2" == "top" ]] && _TUI_W_PIN[$1]="$2"; }
# tui.width/tui.height ID SPEC - an explicit 2A unit-token size (cells, %, clamp(...); auto/fill/fr
# resolve to the widget's default fill size) for _tui._widget_pos, resolved through the same
# _tui.layout_resolve panes use. Applied before min_*/max_* clamp further.
tui.width() { [[ -n "$2" ]] && _TUI_W_WIDTH[$1]="$2"; }
tui.height() { [[ -n "$2" ]] && _TUI_W_HEIGHT[$1]="$2"; }
tui.label_align() { [[ -n "$2" ]] && _TUI_W_LABEL_ALIGN[$1]="$2"; }
tui.label_width() { [[ -n "$2" ]] && _TUI_W_LABEL_WIDTH[$1]="$2"; }

# Focus policy for an input. By default an input KEEPS focus after Enter (a shell prompt
# or chat box stays live) and drops it only on Esc / Tab / clicking elsewhere.
#   tui.input.retain ID [true|false]    Retain Input On Submit: after Enter the cursor stays in the input and the
#                                        user keeps typing (default true; false = form style, Enter also leaves it)
#   tui.input.sticky ID [true]           clicking empty space does not blur it (Esc/Tab still do)
tui.input.retain() { [[ "${2:-true}" == true ]] && _TUI_W_RETAIN[$1]=1 || _TUI_W_RETAIN[$1]=0; }
tui.input.blur_on_submit() { tui.input.retain "$1" false; } # old name
tui.input.sticky() { if [[ "${2:-true}" == true ]]; then _TUI_W_STICKY[$1]=1; else unset '_TUI_W_STICKY[$1]'; fi; }

# ═══════════════════════════════════════════════════════════════════════
#  GEOMETRY & RENDERING
# ═══════════════════════════════════════════════════════════════════════

_tui._repeat() {
	local ch="$1" n="$2" out=""
	((n <= 0)) && return
	printf -v out '%*s' "$n" ""
	printf '%s' "${out// /$ch}"
}

# Safe pane lookup for a possibly-empty widget id. Subscripting an
# associative array with "" is a bash error ("bad array subscript"), not
# just an empty lookup - this matters here because callers routinely pass
# the previously-focused id, which is "" before anything has been focused.
_tui._widget_pane() {
	[[ -z "$1" ]] && return
	printf '%s' "${_TUI_W_PANE[$1]:-}"
}

_tui._widget_align() {
	local id="$1" pane="${_TUI_W_PANE[$1]}" default="left"
	[[ "${_TUI_W_TYPE[$1]}" == "button" ]] && default="center"
	printf '%s' "${_TUI_W_ALIGN[$id]:-${_TUI_P_ALIGN[$pane]:-$default}}"
}

# ── fork-free helper variants: they set _R instead of printing, so callers don't need $(...) ──
# (A command substitution is a fork. _tui._widget_pos alone ran one per widget on EVERY mouse-motion event.)
_tui._widget_valign_v() { _R="${_TUI_W_VALIGN[$1]:-${_TUI_P_VALIGN[${_TUI_W_PANE[$1]}]:-top}}"; }
_tui._widget_align_v() {
	local d=left
	[[ "${_TUI_W_TYPE[$1]}" == button ]] && d=center
	_R="${_TUI_W_ALIGN[$1]:-${_TUI_P_ALIGN[${_TUI_W_PANE[$1]}]:-$d}}"
}
_tui._align_pad_v() { # ALIGN CONTENT_LEN WIDTH
	case "$1" in
		center) _R=$((($3 - $2) / 2)) ;;
		right) _R=$(($3 - $2)) ;;
		*) _R=0 ;;
	esac
	((_R < 0)) && _R=0
}
_tui._repeat_v() { # CH N
	_R=""
	(($2 <= 0)) && return 0
	printf -v _R '%*s' "$2" ""
	_R="${_R// /$1}"
}
# Text with no ${...} expression is returned as is (the common case); only an expression needs a subshell.
_tui._resolve_text_v() {
	if [[ "$1" == *'${'*'}'* ]]; then _R="$(_tui._resolve_text "$1")"; else _R="$1"; fi
}

_tui._widget_valign() {
	local id="$1" pane="${_TUI_W_PANE[$1]}"
	printf '%s' "${_TUI_W_VALIGN[$id]:-${_TUI_P_VALIGN[$pane]:-top}}"
}

_tui._align_pad() {
	local align="$1" content_len="$2" width="$3" pad=0
	case "$align" in
		center) pad=$(((width - content_len) / 2)) ;;
		right) pad=$((width - content_len)) ;;
		*) pad=0 ;;
	esac
	((pad < 0)) && pad=0
	printf '%s' "$pad"
}

_tui._resolve_text() {
	local text="$1" out="" pre expr result
	local rest="$text"
	while [[ "$rest" == *'${'*'}'* ]]; do
		pre="${rest%%\$\{*}"
		rest="${rest#*\$\{}"
		expr="${rest%%\}*}"
		rest="${rest#*\}}"
		result="$(PATH="${SCRIPT_DIR:-.}:$PATH" eval "$expr" 2>/dev/null)"
		out+="${pre}${result}"
	done
	out+="$rest"
	printf '%s' "$out"
}

# Whether a leaf pane's content actually fits is normally inferred
# automatically (see _tui._pane_content_need) rather than requiring the
# author to precompute and declare min_width/min_height by hand. Set
# strict_fit="false" on a specific pane (tui.pane_strict_fit ID false) to
# opt back out and rely on explicit min_width/min_height only, the way
# every pane behaved before this check existed.
declare -gA _TUI_P_STRICT_FIT=()
tui.pane_strict_fit() { _TUI_P_STRICT_FIT[$1]="$2"; }

declare -g _TUI_CONTENT_NEED_W=0
declare -g _TUI_CONTENT_NEED_H=0

# _tui._pane_content_need ID - infers how much space a leaf pane's actual
# content needs, into _TUI_CONTENT_NEED_W/_H (0 when nothing applies).
# Two sources, each best-effort and consistent with this framework's
# existing "static declared text" warnings rather than attempting to
# re-resolve ${...} runtime template expressions:
#   - widgets placed in it: height from the furthest row used, width from
#     the longest label/value text among them;
#   - tui.output/tui.output_append content: reuses _TUI_P_LINES/_TUI_P_MAX_W
#     directly - _tui._calc_bounds already maintains these on every
#     tui.output call, so there's nothing new to measure here.
# A container pane (has children) or one with scroll enabled is exempt:
# a container's own children enforce their own fit, and a scrollable
# pane's whole purpose is holding content taller/wider than its viewport.
# One pass over every widget into per-pane maxima, for _tui._pane_content_need while _TUI_CN_ON=1 (tui.render's
# up-front refresh): the per-pane scan of all widgets made a full render cost panes x widgets.
declare -gA _TUI_CN_ROW=() _TUI_CN_LEN=()
declare -gi _TUI_CN_ON=0 _TUI_FIT_FRESH=0 # _TUI_FIT_FRESH: tui.render has just refreshed every leaf's content fit
# state:direct
_tui._content_need_index() {
	_TUI_CN_ROW=()
	_TUI_CN_LEN=()
	local wid p row txt
	for wid in "${_TUI_W_ORDER[@]}"; do
		p="${_TUI_W_PANE[$wid]:-}"
		[[ -n "$p" ]] || continue
		row=${_TUI_W_ROW[$wid]:-0}
		((row > ${_TUI_CN_ROW[$p]:--1})) && _TUI_CN_ROW[$p]=$row
		case "${_TUI_W_TYPE[$wid]:-}" in textarea | list | table | progress) txt="${_TUI_W_LABEL[$wid]:-}" ;; *) txt="${_TUI_W_LABEL[$wid]:-${_TUI_W_VALUE[$wid]:-}}" ;; esac
		((${#txt} > ${_TUI_CN_LEN[$p]:-0})) && _TUI_CN_LEN[$p]=${#txt}
	done
}

# state:direct
_tui._pane_content_need() {
	local id="$1"
	_TUI_CONTENT_NEED_W=0
	_TUI_CONTENT_NEED_H=0
	[[ -n "${_TUI_P_CHILDREN[$id]:-}" ]] && return
	[[ "${_TUI_P_SCROLL[$id]:-none}" != "none" ]] && return

	local wid maxrow=-1 maxlen=0 row txt
	if ((_TUI_CN_ON)); then
		maxrow=${_TUI_CN_ROW[$id]:--1}
		maxlen=${_TUI_CN_LEN[$id]:-0}
	else
		for wid in "${_TUI_W_ORDER[@]}"; do
			[[ "${_TUI_W_PANE[$wid]:-}" == "$id" ]] || continue
			row=${_TUI_W_ROW[$wid]:-0}
			((row > maxrow)) && maxrow=$row
			case "${_TUI_W_TYPE[$wid]:-}" in textarea | list | table | progress) txt="${_TUI_W_LABEL[$wid]:-}" ;; *) txt="${_TUI_W_LABEL[$wid]:-${_TUI_W_VALUE[$wid]:-}}" ;; esac
			((${#txt} > maxlen)) && maxlen=${#txt}
		done
	fi
	((maxrow >= 0)) && _TUI_CONTENT_NEED_H=$((maxrow + 1))
	((maxlen > _TUI_CONTENT_NEED_W)) && _TUI_CONTENT_NEED_W=$maxlen

	local lines=${_TUI_P_LINES[$id]:-0} maxw=${_TUI_P_MAX_W[$id]:-0}
	((lines > _TUI_CONTENT_NEED_H)) && _TUI_CONTENT_NEED_H=$lines
	((maxw > _TUI_CONTENT_NEED_W)) && _TUI_CONTENT_NEED_W=$maxw

	# Both sources above are content-AREA sizes; _tui._pane_too_small
	# compares against the pane's OUTER w/h (same as min_width/min_height
	# already do), so translate using the same border inset
	# tui.content_area uses in the other direction.
	local vp=${_TUI_P_VPAD[$id]:-0} hp=${_TUI_P_HPAD[$id]:-0}
	if [[ "${_TUI_P_BORDER[$id]:-single}" != "none" ]]; then
		((_TUI_CONTENT_NEED_W > 0)) && _TUI_CONTENT_NEED_W=$((_TUI_CONTENT_NEED_W + 4 + 2 * hp))
		((_TUI_CONTENT_NEED_H > 0)) && _TUI_CONTENT_NEED_H=$((_TUI_CONTENT_NEED_H + 2 + 2 * vp))
	else
		((_TUI_CONTENT_NEED_W > 0)) && _TUI_CONTENT_NEED_W=$((_TUI_CONTENT_NEED_W + 2 + 2 * hp))
		((_TUI_CONTENT_NEED_H > 0)) && _TUI_CONTENT_NEED_H=$((_TUI_CONTENT_NEED_H + 2 * vp))
	fi
}

declare -gA _TUI_P_EFFECTIVE_MINW=()
declare -gA _TUI_P_EFFECTIVE_MINH=()

# _tui._refresh_content_fit ID - recomputes and caches the effective
# min width/height (explicit min_width/min_height, or the pane's actual
# inferred content need, whichever is larger) for one pane. This is the
# only place that does the O(widgets-in-this-pane) work behind
# _tui._pane_content_need - deliberately called from just one place,
# _tui._draw_pane, which only ever runs on a full render (tui.render:
# once at startup, once per resize). _tui._pane_too_small itself stays a
# cheap cache read below, because it's also called from the per-event hot
# path (_tui._draw_widget, hit-tested and redrawn on every hover/focus
# change) and _tui._draw_pane_border (every focus change) - recomputing
# there would reintroduce exactly the kind of per-event cost this
# session spent most of its effort removing.
_tui._refresh_content_fit() {
	local id="$1"
	local minw="${_TUI_P_MINW[$id]:-0}" minh="${_TUI_P_MINH[$id]:-0}"
	if [[ "${_TUI_P_STRICT_FIT[$id]:-}" != "false" ]]; then
		_tui._pane_content_need "$id"
		((_TUI_CONTENT_NEED_W > minw)) && minw=$_TUI_CONTENT_NEED_W
		((_TUI_CONTENT_NEED_H > minh)) && minh=$_TUI_CONTENT_NEED_H
	fi
	_ps.panes.set "$id" effective_minw "$minw"
	_ps.panes.set "$id" effective_minh "$minh"
}

# state:direct
_tui._pane_too_small() {
	local id="$1"
	[[ -n "${_TUI_P_COLLAPSED[$id]:-}" ]] && return 1 # a collapsed pane is meant to be small (tui_collapse.sh)
	local minw="${_TUI_P_EFFECTIVE_MINW[$id]:-${_TUI_P_MINW[$id]:-0}}"
	local minh="${_TUI_P_EFFECTIVE_MINH[$id]:-${_TUI_P_MINH[$id]:-0}}"
	local w=${_TUI_P_W[$id]:-0} h=${_TUI_P_H[$id]:-0}
	((minw > 0 && w < minw)) && return 0
	((minh > 0 && h < minh)) && return 0
	return 1
}

# While _TUI_WP_REUSE=1 (set only around loops that touch no geometry: tui.render's widget pass, _tui_hit.rebuild)
# consecutive widgets of one pane share that pane's inset instead of recomputing it per widget.
declare -gi _TUI_WP_REUSE=0 _TUI_WP_IV=0 _TUI_WP_IH=0
declare -g _TUI_WP_LAST=""
declare -gA _TUI_WPC=()
declare -gi _TUI_WPC_N=0
# state:direct
_tui._widget_pos() {
	local pane="${_TUI_W_PANE[$1]}"
	local wrow="${_TUI_W_ROW[$1]}"
	local pr=${_TUI_P_ROW[$pane]} pc=${_TUI_P_COL[$pane]}
	local pw=${_TUI_P_W[$pane]} ph=${_TUI_P_H[$pane]}
	local content_top content_h
	local whp=${_TUI_W_HPAD[$1]:-0} wvp=${_TUI_W_VPAD[$1]:-0}

	if ((_TUI_WP_REUSE)) && [[ "$_TUI_WP_LAST" == "$pane" ]]; then
		_IV=$_TUI_WP_IV _IH=$_TUI_WP_IH
	else
		_tui._inset "$pane"
		_TUI_WP_LAST="$pane" _TUI_WP_IV=$_IV _TUI_WP_IH=$_IH
	fi
	# Content-addressed: the key holds every input the arithmetic below reads (pane rect and inset, the widget's
	# placement and size attributes, both valigns), so a changed attribute is a different key and nothing needs
	# invalidating. Equal keys recur across pages (the shared nav and header panes), not only across redraws.
	# For leaf panes with vertical scroll, include the offset in the key so changes to it invalidate the cache.
	local scroll_off="" stuck_id=""
	if [[ -z "${_TUI_P_CHILDREN[$pane]:-}" ]]; then
		local scroll="${_TUI_P_SCROLL[$pane]:-none}"
		if [[ "$scroll" == "v" || "$scroll" == "both" ]]; then
			scroll_off="|${_TUI_P_SOFF_V[$pane]:-0}"
			stuck_id="|${_TUI_P_STUCK[$pane]:-}"
		fi
	fi
	local _wk="$pr $pc $pw $ph $_IV $_IH $wrow $whp $wvp|${_TUI_W_WIDTH[$1]:-}|${_TUI_W_HEIGHT[$1]:-}|${_TUI_W_EXPAND[$1]:-}|${_TUI_W_ROWSPAN[$1]:-}|${_TUI_W_MAXH[$1]:-}|${_TUI_W_MINH[$1]:-}|${_TUI_W_MAXW[$1]:-}|${_TUI_W_MINW[$1]:-}|${_TUI_W_VALIGN[$1]:-}|${_TUI_P_VALIGN[$pane]:-}$scroll_off$stuck_id"
	if [[ -n "${_TUI_WPC[$_wk]+x}" ]]; then
		set -- "$1" ${_TUI_WPC[$_wk]}
		_WSR=$2 _WSC=$3 _WSW=$4 _WSH=$5 _WSW_AVAIL=$6
		return
	fi
	content_top=$((pr + _IV + wvp))
	content_h=$((ph - 2 * _IV - 2 * wvp))
	_WSC=$((pc + _IH + whp))
	_WSW=$((pw - 2 * _IH - 2 * whp))
	((_WSW < 1)) && _WSW=1
	((content_h < 1)) && content_h=1
	_WSW_AVAIL=$_WSW # true available width, captured before width=/max_width= shrink it (the min_width= advisory reads this)

	# width= (2A): an explicit unit-token size (cells, %, clamp(...); auto/fill/
	# fr all resolve to the default fill width computed above) overrides the
	# default before min_width=/max_width= clamp it further.
	local width_spec="${_TUI_W_WIDTH[$1]:-}"
	if [[ -n "$width_spec" ]]; then
		_tui.layout_resolve "$width_spec" "$_WSW"
		_WSW=$_LY_R
		((_WSW < 1)) && _WSW=1
	fi

	_tui._widget_valign_v "$1"
	case "$_R" in
		middle) _WSR=$((content_top + content_h / 2 + wrow)) ;;
		bottom) _WSR=$((content_top + content_h - 1 - wrow)) ;;
		*) _WSR=$((content_top + wrow)) ;;
	esac

	_WSH=1 # rows the widget occupies (expand=y widgets span several - see tui.expand)
	local expand="${_TUI_W_EXPAND[$1]:-}"
	local avail_h=1
	if [[ "$expand" == y || "$expand" == both ]]; then
		_WSR=$((content_top + wrow))
		avail_h=$((content_top + content_h - _WSR))
		((avail_h < 1)) && avail_h=1
		_WSH=${_TUI_W_ROWSPAN[$1]:-0}
		# rows= is a real height in a scrolling pane: the space left in the viewport does not cap it (the widget may sit below the fold)
		if [[ -z "${_TUI_P_CHILDREN[$pane]:-}" && "${_TUI_P_SCROLL[$pane]:-none}" == @(v|both) ]]; then
			((_WSH > 0)) && avail_h=$_WSH
		fi
		((_WSH <= 0 || _WSH > avail_h)) && _WSH=$avail_h
		((_WSH < 1)) && _WSH=1
	fi
	# height= (2A): same idea as width= above, resolved against the fill
	# height expand=y would use (1 row when there's no expand, since that's
	# the only "available" a non-expanding widget ever had).
	local height_spec="${_TUI_W_HEIGHT[$1]:-}"
	if [[ -n "$height_spec" ]]; then
		_tui.layout_resolve "$height_spec" "$avail_h"
		_WSH=$_LY_R
		((_WSH < 1)) && _WSH=1
	fi
	local _wt_measure="${_TUI_WT_MEASURE[${_TUI_W_TYPE[$1]}]-}" # contract types size themselves unless expand= / height= decided
	if [[ -n "$_wt_measure" && -z "$expand$height_spec" ]]; then
		"$_wt_measure" "$1" "$_WSW"
		_WSH=$_R
		((_WSH < 1)) && _WSH=1
	fi
	local maxh="${_TUI_W_MAXH[$1]:-}" minh="${_TUI_W_MINH[$1]:-}"
	if [[ -n "$maxh" ]] && ((_WSH > maxh)); then _WSH=$maxh; fi
	if [[ -n "$minh" ]] && ((_WSH < minh)); then _WSH=$minh; fi

	local maxw="${_TUI_W_MAXW[$1]:-}" minw="${_TUI_W_MINW[$1]:-}"
	if [[ -n "$maxw" ]] && ((_WSW > maxw)); then _WSW=$maxw; fi
	if [[ -n "$minw" ]] && ((_WSW < minw)); then _WSW=$minw; fi
	((_WSW < 1)) && _WSW=1
	# For leaf panes with vertical scroll, subtract the offset from the calculated screen row
	local first_viewport_row=""
	if [[ -z "${_TUI_P_CHILDREN[$pane]:-}" ]]; then
		local scroll="${_TUI_P_SCROLL[$pane]:-none}"
		if [[ "$scroll" == "v" || "$scroll" == "both" ]]; then
			_WSR=$(((_WSR) - ${_TUI_P_SOFF_V[$pane]:-0}))
			first_viewport_row=$((pr + _IV + wvp))
		fi
	fi
	# Handle pinned widgets: if this widget is stuck, place it at the first viewport row;
	# if another widget lands on that row, hide it by setting _WSR = -1
	if [[ -n "$first_viewport_row" && "${_TUI_P_STUCK[$pane]:-}" == "$1" ]]; then
		_WSR=$first_viewport_row
	elif [[ -n "$first_viewport_row" && -n "${_TUI_P_STUCK[$pane]:-}" && $_WSR -eq $first_viewport_row ]]; then
		_WSR=-1
	fi
	# a widget taller than what is left of the viewport is cut at its bottom edge, so it never paints over the border
	if [[ -n "$first_viewport_row" ]]; then
		local _vend=$((pr + ph - _IV))
		((_WSR >= 0 && _WSR < _vend && _WSR + _WSH > _vend)) && _WSH=$((_vend - _WSR))
	fi
	[[ -n "$_wt_measure" ]] && return # a measured height can change with the widget's content, which the key does not cover
	if ((_TUI_WPC_N >= 4096)); then _TUI_WPC=() _TUI_WPC_N=0; fi
	_TUI_WPC[$_wk]="$_WSR $_WSC $_WSW $_WSH $_WSW_AVAIL"
	_TUI_WPC_N+=1
}

tui.content_area() {
	local id="$1"
	_tui._content_rect "$id"
	echo "$_CR_R $_CR_C $_CR_H $_CR_W"
}

# _tui._draw_size_warning - appends to _TUI_FRAME; only called from
# _tui._draw_pane_buf.
_tui._draw_size_warning() {
	local r="$1" c="$2" h="$3" w="$4" minw="$5" minh="$6"
	((h < 1)) && h=1
	((w < 1)) && w=1

	_tui.emit_reset
	_tui.emit_sgr 1
	_tui.emit_fg_hex "FF3333"
	local blank
	printf -v blank '%*s' "$w" ""
	local row
	for ((row = 0; row < h; row++)); do
		_tui.emit_goto $((r + row)) "$c"
		_tui.emit "$blank"
	done

	local msg="min space = ${minw}x${minh}"
	local shown="${msg:0:$w}"
	local pad=$(((w - ${#shown}) / 2))
	((pad < 0)) && pad=0
	_tui.emit_goto $((r + h / 2)) $((c + pad))
	_tui.emit "$shown"
	_tui.emit_reset
}

# ── fork-free style -> SGR (used by hot render paths instead of `$(_tui._apply_style ...)`) ──
# _tui._style_v KEY [FALLBACK] [BGFALLBACK] -> _SGR  (the same fg/bg/mods resolution as _tui._apply_style, built with
# arithmetic and string ops only). A colour name it doesn't know falls back to the slow, capturing path.
declare -gA _TUI_SGR_NAMED=([black]=30 [red]=31 [green]=32 [yellow]=33 [blue]=34 [magenta]=35 [cyan]=36 [white]=37 [default]=39
	[br_black]=90 [br_red]=91 [br_green]=92 [br_yellow]=93 [br_blue]=94 [br_magenta]=95 [br_cyan]=96 [br_white]=97)
declare -gA _TUI_SGR_MOD=([bold]=1 [dim]=2 [italic]=3 [underline]=4 [blink]=5 [reverse]=7 [hidden]=8 [strike]=9)

declare -gA _TUI_SGR_MEMO=()
declare -gi _TUI_SGR_MEMO_N=0

# _tui._sgr_from FG BG MODS -> _SGR (pure; unknown colour names fall back to the slow capturing path)
# Memoised on "fg|bg|mods": the result depends only on those strings, so it never needs invalidating.
_tui._sgr_from() {
	local mk="$1|$2|$3"
	if [[ -n "${_TUI_SGR_MEMO[$mk]+x}" ]]; then
		_SGR="${_TUI_SGR_MEMO[$mk]}"
		return 0
	fi
	local fg="$1" bg="$2" mods="$3" m codes="" hx code
	_SGR=""
	if [[ -n "$fg" ]]; then
		if [[ "$fg" == \#* ]]; then
			hx="${fg#\#}"
			codes+="38;2;$((16#${hx:0:2}));$((16#${hx:2:2}));$((16#${hx:4:2}));"
		elif [[ -n "${_TUI_SGR_NAMED[$fg]:-}" ]]; then
			codes+="${_TUI_SGR_NAMED[$fg]};"
		else return 1; fi
	fi
	if [[ -n "$bg" ]]; then
		if [[ "$bg" == \#* ]]; then
			hx="${bg#\#}"
			codes+="48;2;$((16#${hx:0:2}));$((16#${hx:2:2}));$((16#${hx:4:2}));"
		elif [[ -n "${_TUI_SGR_NAMED[$bg]:-}" ]]; then
			codes+="$((${_TUI_SGR_NAMED[$bg]} + 10));"
		else return 1; fi
	fi
	for m in $mods; do
		code="${_TUI_SGR_MOD[$m]:-}"
		[[ -n "$code" ]] && codes+="$code;"
	done
	[[ -n "$codes" ]] && _SGR=$'\e['"${codes%;}m"
	# bounded: dynamic per-row colours (gradients, charts) must not grow the table without limit
	if ((_TUI_SGR_MEMO_N >= 4096)); then _TUI_SGR_MEMO=() _TUI_SGR_MEMO_N=0; fi
	_TUI_SGR_MEMO[$mk]="$_SGR"
	_TUI_SGR_MEMO_N+=1
	return 0
}

_tui._style_v() {
	local key="$1" fb="${2:-}" bgfb="${3:-}" fg bg mods
	fg="${_TUI_STYLE_FG[$key]:-}"
	bg="${_TUI_STYLE_BG[$key]:-}"
	mods="${_TUI_STYLE_MOD[$key]:-}"
	if [[ -n "$fb" ]]; then
		[[ -z "$fg" ]] && fg="${_TUI_STYLE_FG[$fb]:-}"
		[[ -z "$bg" ]] && bg="${_TUI_STYLE_BG[$fb]:-}"
		[[ -z "$mods" ]] && mods="${_TUI_STYLE_MOD[$fb]:-}"
	fi
	[[ -z "$bg" && -n "$bgfb" ]] && bg="${_TUI_STYLE_BG[$bgfb]:-}"
	_tui._sgr_from "$fg" "$bg" "$mods" || _SGR="$(_tui._apply_style "$key" "$fb" "$bgfb")"
	return 0
}

_tui._apply_style() {
	local key="$1" fallback="${2:-}"
	local bgfb="${3:-}" # optional key whose bg is used when neither KEY nor FALLBACK has one
	local fg="${_TUI_STYLE_FG[$key]:-}"
	local bg="${_TUI_STYLE_BG[$key]:-}"
	local mods="${_TUI_STYLE_MOD[$key]:-}"

	if [[ -n "$fallback" ]]; then
		[[ -z "$fg" ]] && fg="${_TUI_STYLE_FG[$fallback]:-}"
		[[ -z "$bg" ]] && bg="${_TUI_STYLE_BG[$fallback]:-}"
		[[ -z "$mods" ]] && mods="${_TUI_STYLE_MOD[$fallback]:-}"
	fi
	[[ -z "$bg" && -n "$bgfb" ]] && bg="${_TUI_STYLE_BG[$bgfb]:-}"

	if [[ -n "$fg" ]]; then
		if [[ "$fg" == \#* ]]; then fg.hex "$fg"; else "fg.$fg" 2>/dev/null; fi
	fi
	if [[ -n "$bg" ]]; then
		if [[ "$bg" == \#* ]]; then bg.hex "$bg"; else "bg.$bg" 2>/dev/null; fi
	fi
	if [[ -n "$mods" ]]; then
		for m in $mods; do "style.$m" 2>/dev/null; done
	fi
}

# _tui._fill_pane_bg ID ROW COL H W - appends to _TUI_FRAME; only called
# from draw paths that build a shared frame (tui.render, _tui._draw_pane_buf).
_tui._fill_pane_bg() {
	local id="$1" r="$2" c="$3" h="$4" w="$5"
	local key="${id}_normal"
	[[ -z "${_TUI_STYLE_FG[$key]:-}${_TUI_STYLE_BG[$key]:-}${_TUI_STYLE_MOD[$key]:-}" ]] && return
	((h < 1 || w < 1)) && return # hidden (tui.fixed overflow)
	local blank
	printf -v blank '%*s' "$w" ""
	_tui.emit_style "$key"
	local row
	for ((row = 0; row < h; row++)); do
		_tui.emit_goto $((r + row)) "$c"
		_tui.emit "$blank"
	done
	_tui.emit_reset
}

# _tui._draw_pane ID - draws one full pane (background/border/title),
# standalone: resets _TUI_FRAME, builds into it via _tui._draw_pane_buf,
# then prints the result directly and restores whatever _TUI_FRAME held
# before (tui_api.sh's standalone pane repaint calls this directly and
# expects an immediate write, no synchronized-flush wrapper). Aggregate
# render paths (tui.render) call _tui._draw_pane_buf themselves so every
# pane folds into one shared buffer and one flush.
_tui._draw_pane() {
	local _dp_saved="$_TUI_FRAME"
	_TUI_FRAME=""
	_tui._draw_pane_buf "$1"
	_tui_frame.junctions
	_tui_hit.overlay "$1"
	_tui_modal.base_fold "$_TUI_FRAME"
	((_TUI_FLUSH_GEN++))
	printf '%s' "$_TUI_FRAME"
	_TUI_FRAME="$_dp_saved"
}

# state:direct
_tui._draw_pane_buf() {
	local id="$1"
	local r=${_TUI_P_ROW[$id]} c=${_TUI_P_COL[$id]}
	local h=${_TUI_P_H[$id]} w=${_TUI_P_W[$id]}
	((h < 1 || w < 1)) && return
	_tui._eff_border "$id"
	local border=$_TB
	local title="${_TUI_P_TITLE[$id]:-}"

	# tui.render refreshed every leaf up front; containers (nothing to scan) still refresh here
	if ((! _TUI_FIT_FRESH)) || [[ -n "${_TUI_P_CHILDREN[$id]:-}" ]]; then _tui._refresh_content_fit "$id"; fi
	if _tui._pane_too_small "$id"; then
		_tui._draw_size_warning "$r" "$c" "$h" "$w" "${_TUI_P_EFFECTIVE_MINW[$id]:-0}" "${_TUI_P_EFFECTIVE_MINH[$id]:-0}"
		return
	fi

	if [[ "$border" == "none" ]]; then
		_tui_collapse.bar "$id" || _tui._fill_pane_bg "$id" "$r" "$c" "$h" "$w"
		return
	fi

	# every input of the bytes below: geometry, border, title and the style strings of the three styles it draws with. No
	# page, id or counter in the key, so identical panes (the menu, the header) hit across pages.
	local _rc_key="p|$r|$c|$h|$w|$border|$title|${_TUI_P_TITLE_POS[$id]:-}|${_TUI_P_TITLE_ALIGN[$id]:-}|${_TUI_STYLE_FG[${id}_border]:-}|${_TUI_STYLE_BG[${id}_border]:-}|${_TUI_STYLE_MOD[${id}_border]:-}|${_TUI_STYLE_FG[${id}_title]:-}|${_TUI_STYLE_BG[${id}_title]:-}|${_TUI_STYLE_MOD[${id}_title]:-}|${_TUI_STYLE_FG[${id}_normal]:-}|${_TUI_STYLE_BG[${id}_normal]:-}|${_TUI_STYLE_MOD[${id}_normal]:-}" _rc_from=${#_TUI_FRAME}
	_tui_rowcache.replay "$_rc_key" && return

	_tui_canvas.glyphs "$border"
	local tl=$_TC_TL tr=$_TC_TR bl=$_TC_BL br=$_TC_BR hz=$_TC_HZ vt=$_TC_VT

	local inner=$((w - 2))
	((inner < 1)) && inner=1

	_tui.emit_goto "$r" "$c"
	_tui_frame.edge "$id" top "$tl" "$tr" "$hz" "$inner" "$title" "${id}_border" ""

	# every interior row is the same bytes after its cursor move: build the row once, not h-2 times
	local blank rowbody _dp_saved="$_TUI_FRAME"
	printf -v blank '%*s' "$inner" ""
	_TUI_FRAME=""
	_tui.emit_ring "${id}_border" "${id}_border" "$id"
	_tui.emit "$vt"
	_tui.emit_reset
	_tui.emit_style "${id}_normal"
	_tui.emit "$blank"
	_tui.emit_reset
	_tui.emit_ring "${id}_border" "${id}_border" "$id"
	_tui.emit "$vt"
	_tui.emit_reset
	rowbody="$_TUI_FRAME"
	_TUI_FRAME="$_dp_saved"
	for ((row = 1; row < h - 1; row++)); do
		_tui.emit_goto $((r + row)) "$c"
		_tui.emit "$rowbody"
	done

	_tui.emit_goto $((r + h - 1)) "$c"
	_tui_frame.edge "$id" bottom "$bl" "$br" "$hz" "$inner" "$title" "${id}_border" ""
	_tui_rowcache.store "$_rc_key" "$_rc_from"
}

# Redraws only a pane's border ring (corners/edges/title), resolving its own
# style state: a pane containing the currently focused widget draws
# "${id}_focus" (falling back to "${id}_border" when the class has no
# :focus rule), otherwise "${id}_border". Hovering a pane has no effect on
# its border - only focus does; this keeps the same self-contained
# resolution _tui._draw_widget uses for its own focus/hover, just against
# _TUI_FOCUS_ID instead of _TUI_HOVERED_PANE. Never touches the pane's
# interior, so it's safe to call whenever focus moves without disturbing
# scrollback/tui.output content or child widgets - no awk, no subshell text
# processing, just a handful of builtin append calls. Its only caller is
# _tui._draw_pane_borders_now (via _tui._draw_ids_now), which owns the
# reset/flush of _TUI_FRAME, so this appends only - no standalone wrapper
# needed (unlike _tui._draw_pane, this one has no caller outside the render
# path).
# state:direct
_tui._draw_pane_border_buf() {
	local id="$1"
	local r=${_TUI_P_ROW[$id]} c=${_TUI_P_COL[$id]}
	local h=${_TUI_P_H[$id]} w=${_TUI_P_W[$id]}
	_tui._eff_border "$id"
	local border=$_TB
	local title="${_TUI_P_TITLE[$id]:-}"

	[[ "$border" == "none" ]] && return
	_tui._pane_too_small "$id" && return

	_tui_canvas.glyphs "$border"
	local tl=$_TC_TL tr=$_TC_TR bl=$_TC_BL br=$_TC_BR hz=$_TC_HZ vt=$_TC_VT

	local inner=$((w - 2))
	((inner < 1)) && inner=1
	local state="border"
	[[ -n "$_TUI_FOCUS_ID" && "${_TUI_W_PANE[$_TUI_FOCUS_ID]:-}" == "$id" ]] && state="focus"
	[[ "$_TUI_PANE_FOCUS" == "$id" ]] && state="focus" # keyboard-focused pane (f6 / alt+arrows) rings like a focused one
	local style_key="${id}_${state}"

	_tui.emit_goto "$r" "$c"
	_tui_frame.edge "$id" top "$tl" "$tr" "$hz" "$inner" "$title" "$style_key" "$style_key"

	local row
	for ((row = 1; row < h - 1; row++)); do
		_tui.emit_goto $((r + row)) "$c"
		_tui.emit_ring "$style_key" "${id}_border" "$id"
		_tui.emit "$vt"
		_tui.emit_reset
		_tui.emit_goto $((r + row)) $((c + w - 1))
		_tui.emit_ring "$style_key" "${id}_border" "$id"
		_tui.emit "$vt"
		_tui.emit_reset
	done

	_tui.emit_goto $((r + h - 1)) "$c"
	_tui_frame.edge "$id" bottom "$bl" "$br" "$hz" "$inner" "$title" "$style_key" "$style_key"
	_tui_frame.junctions
	_tui_hit.overlay "$id"

	# Redraw scrollbar for widget panes that need it (border overwrites the right column)
	local scroll="${_TUI_P_SCROLL[$id]:-none}"
	if [[ "$scroll" == "v" || "$scroll" == "both" ]]; then
		local content_h="${_TUI_P_CONTENT_H[$id]:-0}"
		_tui._content_rect "$id"
		if ((content_h > _CR_H)); then
			local soff="${_TUI_P_SOFF_V[$id]:-0}"
			_tui._style_v "${id}_normal"
			local sty="$_SGR"

			local _SC_BAR
			_tui_scroll.bar_v "$id" "$content_h" "$soff" "$sty"
			_TUI_FRAME+="$_SC_BAR"
		fi
	fi
}

# _tui._draw_widget ID - draws one widget, standalone (see _tui._draw_pane
# for the same reset/build/print/restore shape and why: many callers
# outside the render path - tui_api.sh, tui_input.sh, the widgets files -
# expect an immediate write). Aggregate render paths call
# _tui._draw_widget_buf directly so every widget folds into one shared
# buffer and one flush.
_tui._draw_widget() {
	local _dw_saved="$_TUI_FRAME"
	_TUI_FRAME=""
	_tui._draw_widget_buf "$1"
	_tui_modal.base_fold "$_TUI_FRAME" # painted outside _tui._flush
	((_TUI_FLUSH_GEN++))
	printf '%s' "$_TUI_FRAME"
	_TUI_FRAME="$_dw_saved"
}

# state:direct
_tui._draw_widget_buf() {
	local id="$1"
	local type="${_TUI_W_TYPE[$id]:-}"
	[[ -z "$type" ]] && return
	((_TUI_PERF_TRACKING)) && _tui_perf.count nodes_painted
	local focused=0
	[[ "$_TUI_FOCUS_ID" == "$id" ]] && focused=1
	local hovered=0
	[[ "$_TUI_HOVERED_WIDGET" == "$id" ]] && hovered=1

	local _wpane="${_TUI_W_PANE[$id]}"
	((${_TUI_P_H[$_wpane]:-0} < 1)) && return    # hidden / not on this page
	[[ -n "${_TUI_W_HIDDEN[$id]:-}" ]] && return # in a collapsed pane (tui_collapse.sh)
	_tui._pane_too_small "$_wpane" && return

	_tui._widget_pos "$id"
	local sr=$_WSR sc=$_WSC sw=$_WSW

	# clip: a row outside the pane's content area would spill over the border / neighbouring panes. _widget_pos just
	# left this pane's inset in _IV/_IH, so the content rect is two additions, not another _tui._inset call.
	local _clip_r=$((${_TUI_P_ROW[$_wpane]} + _IV)) _clip_h=$((${_TUI_P_H[$_wpane]} - 2 * _IV))
	((_clip_h < 1)) && _clip_h=1
	((sr < _clip_r || sr >= _clip_r + _clip_h)) && return

	# label/button/checkbox only: their bytes depend on nothing outside this key. A ${expr} text bypasses the cache.
	# The style strings of the keys the draw resolves (the widget's own state style and its pane's) are part of the key,
	# not a counter: the same widget on another page, or after a theme switch that did not touch it, still hits.
	local _rc_key="" _rc_from=0 _rc_sk _rc_pk
	case "$type" in
		label | button | checkbox)
			if [[ "${_TUI_W_VALUE[$id]:-}${_TUI_W_LABEL[$id]:-}" != *'${'* ]]; then
				_rc_sk="${id}_normal"
				if ((focused)); then _rc_sk="${id}_focus"; elif ((hovered)); then _rc_sk="${id}_hover"; fi
				_rc_pk="${_TUI_W_PANE[$id]}_normal"
				_rc_key="w|$type|$sr|$sc|$sw|$_WSW_AVAIL|${_TUI_W_MINW[$id]:-0}|$focused|$hovered|${_TUI_W_ALIGN[$id]:-${_TUI_P_ALIGN[${_TUI_W_PANE[$id]}]:-}}|${_TUI_W_VALUE[$id]:-}|${_TUI_W_LABEL[$id]:-}|${_TUI_STYLE_FG[$_rc_sk]:-}|${_TUI_STYLE_BG[$_rc_sk]:-}|${_TUI_STYLE_MOD[$_rc_sk]:-}|${_TUI_STYLE_FG[$_rc_pk]:-}|${_TUI_STYLE_BG[$_rc_pk]:-}|${_TUI_STYLE_MOD[$_rc_pk]:-}"
				if [[ "$type" == checkbox ]]; then # the :checked / :unchecked look and the normal style it falls back to
					_rc_key+="|${_TUI_STYLE_FG[${id}_checked]:-}|${_TUI_STYLE_BG[${id}_checked]:-}|${_TUI_STYLE_MOD[${id}_checked]:-}|${_TUI_STYLE_FG[${id}_unchecked]:-}|${_TUI_STYLE_BG[${id}_unchecked]:-}|${_TUI_STYLE_MOD[${id}_unchecked]:-}|${_TUI_STYLE_FG[${id}_normal]:-}|${_TUI_STYLE_BG[${id}_normal]:-}|${_TUI_STYLE_MOD[${id}_normal]:-}"
				fi
				_tui_rowcache.replay "$_rc_key" && return
				_rc_from=${#_TUI_FRAME}
			fi
			;;
	esac

	local minw="${_TUI_W_MINW[$id]:-0}"
	if ((minw > 0 && _WSW_AVAIL < minw)); then
		_tui.emit_goto "$sr" "$sc"
		_tui.emit_printf '%*s' "$_WSW_AVAIL" ""
		_tui.emit_goto "$sr" "$sc"
		_tui.emit_reset
		_tui.emit_sgr 1
		_tui.emit_fg_hex "FF3333"
		_tui.emit_printf '%.*s' "$_WSW_AVAIL" "min space = ${minw}"
		_tui.emit_reset
		return
	fi

	_tui.emit_goto "$sr" "$sc"
	_tui.emit_printf '%*s' "$sw" ""
	_tui.emit_goto "$sr" "$sc"

	local pane_id="${_TUI_W_PANE[$id]}"
	local pane_key="${pane_id}_normal"
	local style_key="${id}_normal"
	if ((focused)); then
		style_key="${id}_focus"
	elif ((hovered)); then
		style_key="${id}_hover"
	fi

	case "$type" in
		button)
			local calign
			_tui._widget_align_v "$id"
			calign="$_R"
			local lbl
			_tui._resolve_text_v "${_TUI_W_LABEL[$id]}"
			lbl="$_R"

			_tui.emit_style "$style_key" "$pane_key"
			if ((focused)); then
				[[ -z "${_TUI_STYLE_FG[$style_key]:-}" && -z "${_TUI_STYLE_BG[$style_key]:-}" ]] && _tui.emit_sgr 7
			else
				[[ -z "${_TUI_STYLE_FG[$style_key]:-}" ]] && _tui.emit_sgr 2
			fi

			if [[ "$calign" == "fill" ]]; then
				local pad=$(((sw - ${#lbl}) / 2))
				((pad < 0)) && pad=0
				local rem=$((sw - pad - ${#lbl}))
				((rem < 0)) && rem=0
				_tui.emit_goto "$sr" "$sc"
				_tui.emit_printf '%*s%s%*s' "$pad" "" "$lbl" "$rem" ""
			else
				_tui.emit_goto "$sr" "$sc"
				_tui.emit_printf '%*s' "$sw" ""
				local pad
				_tui._align_pad_v "$calign" "${#lbl}" "$sw"
				pad=$_R
				_tui.emit_goto "$sr" $((sc + pad))
				_tui.emit "$lbl"
			fi
			_tui.emit_reset
			;;
		checkbox)
			local calign
			_tui._widget_align_v "$id"
			calign="$_R"
			local mark="[ ]"
			[[ "${_TUI_W_VALUE[$id]}" == "1" ]] && mark="[x]"
			local lbl
			_tui._resolve_text_v "${_TUI_W_LABEL[$id]}"
			lbl="${mark} $_R"

			# :checked / :unchecked replace the normal look (focus and hover still win); fields they leave out fall back to normal
			local ck_fb="$pane_key" ck_bgfb="" ck_st=unchecked
			if ((! focused && ! hovered)); then
				[[ "${_TUI_W_VALUE[$id]}" == "1" ]] && ck_st=checked
				if [[ -n "${_TUI_STYLE_FG[${id}_$ck_st]:-}${_TUI_STYLE_BG[${id}_$ck_st]:-}${_TUI_STYLE_MOD[${id}_$ck_st]:-}" ]]; then
					style_key="${id}_$ck_st"
					ck_fb="${id}_normal"
					ck_bgfb="$pane_key"
				fi
			fi
			_tui.emit_style "$style_key" "$ck_fb" "$ck_bgfb"
			if ((focused)); then
				[[ -z "${_TUI_STYLE_FG[$style_key]:-}" && -z "${_TUI_STYLE_BG[$style_key]:-}" ]] && _tui.emit_sgr 7
			else
				[[ -z "${_TUI_STYLE_FG[$style_key]:-}" ]] && _tui.emit_sgr 2
			fi

			if [[ "$calign" == "fill" ]]; then
				local pad=$(((sw - ${#lbl}) / 2))
				((pad < 0)) && pad=0
				local rem=$((sw - pad - ${#lbl}))
				((rem < 0)) && rem=0
				_tui.emit_goto "$sr" "$sc"
				_tui.emit_printf '%*s%s%*s' "$pad" "" "$lbl" "$rem" ""
			else
				_tui.emit_goto "$sr" "$sc"
				_tui.emit_printf '%*s' "$sw" ""
				local pad
				_tui._align_pad_v "$calign" "${#lbl}" "$sw"
				pad=$_R
				_tui.emit_goto "$sr" $((sc + pad))
				_tui.emit "$lbl"
			fi
			_tui.emit_reset
			;;
		input | password | textarea | list | table | select | progress)
			_tui_wx.draw_buf "$id" "$type" "$sr" "$sc" "$sw" "$_WSH" "$focused" "$hovered" "$style_key" "$pane_key"
			;;
		*) # a type registered on the widget contract (tui_widget_contract.sh)
			local _wt_draw="${_TUI_WT_DRAW[$type]-}"
			[[ -n "$_wt_draw" ]] && "$_wt_draw" "$id" "$sr" "$sc" "$sw" "$_WSH" "$focused" "$hovered" "$style_key" "$pane_key"
			;;
	esac
	[[ -n "$_rc_key" ]] && _tui_rowcache.store "$_rc_key" "$_rc_from"
}

# ═══════════════════════════════════════════════════════════════════════
#  PERFORMANCE TRACKING - opt-in, off by default. When on, every frame
#  written through _tui._flush (the single choke point every synchronized
#  write in this file goes through) is timestamped, so tui.perf.mean_render_ms
#  can answer "how expensive has rendering actually been lately" from
#  inside a running page - see docs/guide/markup.md.
# ═══════════════════════════════════════════════════════════════════════
# _TUI_PERF_TRACKING itself now lives in lib/perf.sh (stage 0.2), which owns
# spans/counters/tui.perf.report; this section keeps the render-timing log
# tui.perf.mean_render_ms reads.

declare -ga _TUI_RENDER_LOG_T=()  # integer microseconds-since-epoch per tracked flush
declare -ga _TUI_RENDER_LOG_MS=() # that flush's duration, integer ms
declare -g _TUI_NOW_US=0

# _tui._now_us - sets _TUI_NOW_US to the current time in integer
# microseconds. Fork-free via bash 5's $EPOCHREALTIME (plain integer
# arithmetic on its two halves) when available; falls back to a forking
# `date` call on older bash. Only ever called while _TUI_PERF_TRACKING is
# on, so this cost is opt-in, never paid by a page that doesn't ask for it.
#
# $EPOCHREALTIME's decimal separator follows LC_NUMERIC, not always a
# literal "." (e.g. de_DE.UTF-8 uses ","), so splitting on "." silently
# failed under that locale - both halves came back as the whole,
# unsplit string, and `10#` on a comma-containing value crashed with
# "value too great for base". Splitting on the first/last NON-DIGIT
# character instead works regardless of what that separator is.
_tui._now_us() {
	if [[ -n "${EPOCHREALTIME:-}" ]]; then
		local s="${EPOCHREALTIME%%[^0-9]*}" us="${EPOCHREALTIME##*[^0-9]}"
		_TUI_NOW_US=$((10#$s * 1000000 + 10#$us))
	else
		_TUI_NOW_US=$(($(date +%s%N) / 1000))
	fi
}

# _tui._flush BUF - the one place a fully-composed frame actually reaches
# the terminal: wraps it in DEC synchronized-output mode and prints it in
# a single write, exactly as every call site here already did before this
# existed - consolidated so there's one place to add instrumentation
# instead of five near-identical copies of the same three lines. Timing
# only happens while _TUI_PERF_TRACKING is on.
_tui._flush() {
	local buf="$1" out="${2-$1}" # OUT: the part of BUF that must reach the terminal (tui_paint.sh drops unchanged rows)
	((_TUI_OVL_FLUSHING)) || _tui_modal.base_fold "$buf"
	((_TUI_FLUSH_GEN++))
	if ((! _TUI_PERF_TRACKING)); then
		[[ -z "$out" ]] && return
		mode.sync_start
		printf '%s' "$out"
		mode.sync_end
		return
	fi

	_tui_perf.begin flush
	_tui_perf.count bytes_flushed "${#out}"
	_tui_perf.count bytes_suppressed "$((${#buf} - ${#out}))"
	_tui._now_us
	local t0=$_TUI_NOW_US
	[[ -n "$out" ]] && {
		mode.sync_start
		printf '%s' "$out"
		mode.sync_end
	}
	_tui._now_us
	local t1=$_TUI_NOW_US
	_tui_perf.end flush

	_TUI_RENDER_LOG_T+=("$t1")
	_TUI_RENDER_LOG_MS+=("$(((t1 - t0) / 1000))")
	if ((${#_TUI_RENDER_LOG_T[@]} > 2000)); then
		_TUI_RENDER_LOG_T=("${_TUI_RENDER_LOG_T[@]: -1000}")
		_TUI_RENDER_LOG_MS=("${_TUI_RENDER_LOG_MS[@]: -1000}")
	fi
}

# tui.perf.mean_render_ms SECONDS - mean duration (ms) of every tracked
# frame flushed within the trailing SECONDS window. Empty string if
# tracking is off or nothing fell in the window (a caller can treat that
# the same as "no data yet").
tui.perf.mean_render_ms() {
	local window="$1"
	((_TUI_PERF_TRACKING)) || return
	local n=${#_TUI_RENDER_LOG_T[@]}
	((n == 0)) && return

	_tui._now_us
	local cutoff=$((_TUI_NOW_US - window * 1000000))
	local i sum=0 count=0
	for ((i = n - 1; i >= 0; i--)); do
		((_TUI_RENDER_LOG_T[i] < cutoff)) && break
		((sum += _TUI_RENDER_LOG_MS[i]))
		((count++))
	done
	((count == 0)) && return
	printf '%s' "$((sum / count))"
}

# tui.frame.request - asks for a full relayout + repaint at the end of the current
# main-loop iteration. Any number of requests inside one event collapse into one frame;
# tui.render (an immediate frame) satisfies a pending request.
declare -gi _TUI_FRAME_REQ=0
tui.frame.request() { _TUI_FRAME_REQ=1; }

# _tui.frame_present - the main loop's end-of-iteration hook: the requested frame, once.
_tui.frame_present() {
	((_TUI_FRAME_REQ)) || return 0
	_TUI_FRAME_REQ=0
	tui.relayout
}

# state:direct
tui.render() {
	((_TUI_DEFER_RENDER)) && return 0
	_TUI_FRAME_REQ=0
	_TUI_HZ_DIRTY=1
	((_TUI_FOCUS_AUTO)) && _tui_focus.autofocus
	_tui_perf.begin render
	_tui_perf.count full_renders
	# Refresh every leaf pane's content-fit cache up front: _tui._draw_pane_buf
	# only refreshes the pane it's currently drawing, and skips even that when
	# the pane's own h/w is 0 (its very first check, before the refresh) - a
	# pane too small to draw its own border can still be "too small" for the
	# widgets sitting in it, and that check (_tui._pane_too_small, run from the
	# widget loop below) needs every pane's effective min already known, not
	# just the ones with room to draw.
	local pane
	_tui._content_need_index
	_TUI_CN_ON=1
	for pane in "${_TUI_P_ALL[@]}"; do
		[[ -z "${_TUI_P_CHILDREN[$pane]:-}" ]] && _tui._refresh_content_fit "$pane"
	done
	_TUI_CN_ON=0
	_TUI_FIT_FRESH=1 # _tui._draw_pane_buf below need not refresh a leaf again

	_TUI_FRAME=""
	for pane in "${_TUI_P_ALL[@]}"; do
		_tui._eff_border "$pane"
		if [[ -n "${_TUI_P_CHILDREN[$pane]:-}" && "$_TB" == "none" ]]; then
			_tui._fill_pane_bg "$pane" "${_TUI_P_ROW[$pane]}" "${_TUI_P_COL[$pane]}" "${_TUI_P_H[$pane]}" "${_TUI_P_W[$pane]}"
		else
			_tui._draw_pane_buf "$pane"
		fi
	done
	_tui_frame.junctions
	_tui_hit.overlay
	_TUI_FIT_FRESH=0
	_TUI_WP_LAST=""
	_TUI_WP_REUSE=1
	for wid in "${_TUI_W_ORDER[@]}"; do
		_tui._draw_widget_buf "$wid"
	done
	_TUI_WP_REUSE=0
	_tui_scroll.bars_buf
	for _oid in "${!_TUI_PANE_CONTENT[@]}"; do
		[[ -n "${_TUI_PANE_CONTENT[$_oid]}" ]] && _tui._render_output_buf "$_oid"
	done
	# Not diffed: tui.render only runs for full transitions (init, resize, page switch),
	# where almost every row differs and the split costs more than it saves (+41% measured).
	# Targeted redraws (_tui._draw_ids_now) go through _tui_paint.flush instead.
	_TUI_BASE_FRAME="$_TUI_FRAME"
	_TUI_BASE_GEN=-1 # this flush is the base itself: no fold
	_tui._flush "$_TUI_FRAME"
	_TUI_BASE_GEN=$_TUI_FLUSH_GEN _TUI_OVL_FLUSHES=0 _TUI_BASE_EPOCH=$_TUI_RC_EPOCH _TUI_BASE_ROWS=$_TUI_ROWS _TUI_BASE_COLS=$_TUI_COLS
	((_TUI_KEYS_SUSPENDED)) && _tui_input.draw_overlay
	((${#_TUI_OVERLAY_FNS[@]})) && _tui_overlay.draw_all
	_tui_perf.end render
}

tui.redraw() { tui.render; }

tui.clear_pane() {
	local id="$1"
	local r=${_TUI_P_ROW[$id]} c=${_TUI_P_COL[$id]}
	local h=${_TUI_P_H[$id]} w=${_TUI_P_W[$id]}

	_tui._content_rect "$id"
	local sr=$_CR_R sc=$_CR_C sh=$_CR_H sw=$_CR_W

	local blank
	printf -v blank '%*s' "$sw" ""
	for ((row = 0; row < sh; row++)); do
		cur.goto $((sr + row)) "$sc"
		echo -n "$blank"
	done
}

# ═══════════════════════════════════════════════════════════════════════
#  Scrolling
# ═══════════════════════════════════════════════════════════════════════

# state:direct
_tui._scroll_kb() {
	local dir="$1"
	local p="${_TUI_HOVERED_PANE:-}"

	[[ -z "$p" && -n "$_TUI_FOCUS_ID" ]] && p="${_TUI_W_PANE[$_TUI_FOCUS_ID]}"

	if [[ -z "$p" || "${_TUI_P_SCROLL[$p]:-none}" == "none" ]]; then
		for target in "${_TUI_P_ALL[@]}"; do
			if [[ "${_TUI_P_SCROLL[$target]:-none}" != "none" ]]; then
				p="$target"
				break
			fi
		done
	fi

	[[ -z "$p" || "${_TUI_P_SCROLL[$p]:-none}" == "none" ]] && return

	case "$dir" in
		up) ((_TUI_P_SOFF_V[$p] -= 3)) ;;
		down) ((_TUI_P_SOFF_V[$p] += 3)) ;;
		left) ((_TUI_P_SOFF_H[$p] -= 5)) ;;
		right) ((_TUI_P_SOFF_H[$p] += 5)) ;;
	esac

	_tui._queue_render "$p"
}

# _tui._queue_render PANE - marks a pane's content dirty and arms the
# shared debounce countdown if it isn't already running. The actual AWK
# render is deferred to _tui._flush_pending_render, so a burst of scroll
# events (wheel spin, drag-jump) collapses into one redraw of wherever the
# viewport ends up, not one redraw per event.
_tui._queue_render() {
	local pane="$1"
	[[ -z "$pane" ]] && return
	_TUI_PENDING_OUTPUT[$pane]=1
	[[ $_TUI_RENDER_TIMEOUT -lt 0 ]] && _TUI_RENDER_TIMEOUT=3
}

# _tui._flush_pending_render - the single writer for debounced pane-content
# redraws. Builds every pending pane's AWK-rendered frame into ONE buffer
# and emits it as one synchronized write.
_tui._flush_pending_render() {
	((${#_TUI_PENDING_OUTPUT[@]} == 0)) && return

	local id buf
	_TUI_FRAME=""
	for id in "${!_TUI_PENDING_OUTPUT[@]}"; do _tui._render_output_buf "$id"; done
	buf="$_TUI_FRAME"
	_TUI_PENDING_OUTPUT=()

	_tui._flush "$buf"
}

# _tui._draw_ids_now DRAW_FN ID… - calls DRAW_FN once per unique, non-empty
# id, capturing all of it in ONE command substitution and emitting ONE
# synchronized write. This is the "batch, don't debounce" half of the
# picture: for a discrete action (focus moving, a status line updating)
# there's no burst to collapse, just no reason to split one logical update
# across N separate writes to the terminal.
_tui._draw_ids_now() {
	local draw_fn="$1"
	shift
	local id seen=" "
	local _din_saved="$_TUI_FRAME"
	_TUI_FRAME=""
	for id in "$@"; do
		[[ -z "$id" || "$seen" == *" $id "* ]] && continue
		seen+="$id "
		"$draw_fn" "$id"
	done
	local buf="$_TUI_FRAME"
	_TUI_FRAME="$_din_saved"
	[[ -z "$buf" ]] && return
	_tui_paint.flush "$buf"
}

# DRAW_FN passed to _tui._draw_ids_now must append to _TUI_FRAME (the _buf
# variants), not print directly - _tui._draw_ids_now resets/flushes
# _TUI_FRAME itself, once, for every id.
_tui._draw_widgets_now() { _tui._draw_ids_now _tui._draw_widget_buf "$@"; }
_tui._draw_pane_borders_now() { _tui._draw_ids_now _tui._draw_pane_border_buf "$@"; }

# _tui._draw_pane_full_buf PANE - appends to _TUI_FRAME a full redraw of the
# pane's border, all its widgets, and its scrollbar. Used by scroll_into_view
# to redraw everything after an offset change from reveal.
# state:direct
_tui._draw_pane_full_buf() {
	local pane="$1" wid
	# the whole pane (border and a blank interior), so rows a scroll moved away from are not left behind
	_tui._draw_pane_buf "$pane"
	_tui_frame.junctions
	_tui_hit.overlay "$pane"
	# Redraw all widgets in this pane
	for wid in "${_TUI_W_ORDER[@]}"; do
		[[ "${_TUI_W_PANE[$wid]:-}" == "$pane" ]] && _tui._draw_widget_buf "$wid"
	done
	# Redraw scrollbar for this pane
	local scroll="${_TUI_P_SCROLL[$pane]:-none}"
	if [[ "$scroll" != "v" && "$scroll" != "both" ]]; then
		return
	fi
	local content_h="${_TUI_P_CONTENT_H[$pane]:-0}"
	_tui._content_rect "$pane"
	if ((content_h > _CR_H)); then
		local soff="${_TUI_P_SOFF_V[$pane]:-0}"
		_tui._style_v "${pane}_normal"
		local sty="$_SGR"
		local _SC_BAR
		_tui_scroll.bar_v "$pane" "$content_h" "$soff" "$sty"
		_TUI_FRAME+="$_SC_BAR"
	fi
}

# _tui._vwidth_v LINE -> _VW: the display width of LINE with CSI, OSC and two-character escape sequences removed (what the awk
# pass here used to measure). Pure in LINE, so memoised on it; bounded like _TUI_SGR_MEMO.
declare -gA _TUI_VW_MEMO=()
declare -gi _TUI_VW_MEMO_N=0
declare -g _TUI_VW_CSI=$'\e\\[[0-9;?]*[A-Za-z]' _TUI_VW_OSC=$'\e\\][^\a\e]*(\a|\e\\\\)' _TUI_VW_ESC2=$'\e[@A-Z\\\\_-]'
# Three global removal passes in the order the awk gsubs ran (CSI, then OSC, then two-character escapes), each scanning the text
# once and not re-examining what a removal joined together.
_tui._vwidth_v() {
	local s="$1" rest out m re
	if [[ -n "${_TUI_VW_MEMO[$s]+x}" ]]; then
		_VW=${_TUI_VW_MEMO[$s]}
		return
	fi
	for re in "$_TUI_VW_CSI" "$_TUI_VW_OSC" "$_TUI_VW_ESC2"; do
		[[ "$s" == *$'\e'* ]] || break
		out=""
		rest="$s"
		while [[ "$rest" =~ $re ]]; do
			m="${BASH_REMATCH[0]}"
			out+="${rest%%"$m"*}"
			rest="${rest#*"$m"}"
		done
		s="$out$rest"
	done
	_VW=${#s}
	if ((_TUI_VW_MEMO_N >= 4096)); then _TUI_VW_MEMO=() _TUI_VW_MEMO_N=0; fi
	_TUI_VW_MEMO[$1]=$_VW
	_TUI_VW_MEMO_N+=1
}

_tui._calc_bounds() {
	local pane="$1"
	declare -n arr="_TUI_PANE_CONTENT_${pane}"
	local total=${#arr[@]}
	_ps.panes.set "$pane" lines "$total"

	if ((total == 0)); then
		_ps.panes.set "$pane" max_w 0
		return
	fi

	# Plain lines: the widest is just ${#line}. Lines carrying ANSI are measured without their escape codes.
	local _l max_w=0
	for _l in "${arr[@]}"; do
		if [[ "$_l" == *$'\e'* ]]; then
			_tui._vwidth_v "$_l"
			((_VW > max_w)) && max_w=$_VW
		else
			((${#_l} > max_w)) && max_w=${#_l}
		fi
	done
	_ps.panes.set "$pane" max_w "$max_w"
}

# ═══════════════════════════════════════════════════════════════════════
#  FOCUS & INPUT MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════

_tui._unfocus() {
	local old="$_TUI_FOCUS_ID"
	_TUI_FOCUS_ID=""
	_TUI_FOCUS_IDX=-1
	_tui._draw_widgets_now "$old"
	local oldpane=""
	[[ -n "$old" ]] && oldpane="${_TUI_W_PANE[$old]:-}"
	_tui._draw_pane_borders_now "$oldpane"
}

_tui._input_key() {
	local id="$1" key="$2"
	local value="${_TUI_W_VALUE[$id]}"

	case "$key" in
		$'\x7f' | $'\b')
			if ((_TUI_CURSOR > 0)); then
				_ps.widgets.set "$id" value "${value:0:$((_TUI_CURSOR - 1))}${value:$_TUI_CURSOR}"
				((_TUI_CURSOR--))
			fi
			;;
		*)
			if [[ ${#key} -eq 1 && "$key" =~ [[:print:]] ]]; then
				_ps.widgets.set "$id" value "${value:0:$_TUI_CURSOR}${key}${value:$_TUI_CURSOR}"
				((_TUI_CURSOR++))
			fi
			;;
	esac
	_tui._draw_widget "$id"
}

_tui._input_seq() {
	local id="$1" seq="$2"
	local value="${_TUI_W_VALUE[$id]}"

	case "$seq" in
		"[D") ((_TUI_CURSOR > 0)) && ((_TUI_CURSOR--)) ;;
		"[C") ((_TUI_CURSOR < ${#value})) && ((_TUI_CURSOR++)) ;;
		"[H" | "[1~") _TUI_CURSOR=0 ;;
		"[F" | "[4~") _TUI_CURSOR=${#value} ;;
		"[3~")
			if ((_TUI_CURSOR < ${#value})); then
				_ps.widgets.set "$id" value "${value:0:$_TUI_CURSOR}${value:$((_TUI_CURSOR + 1))}"
			fi
			;;
		*) return ;;
	esac
	_tui._draw_widget "$id"
}

# _tui._next_byte VARNAME TIMEOUT - reads one byte into VARNAME, like
# `read -rsn1 -t TIMEOUT VARNAME`, except it drains _TUI_PENDING_INPUT
# first if anything was stashed there. Every "give me the next input byte"
# read in tui.run goes through this, so a rewind from the mouse-motion
# coalescer is invisible to the rest of the loop.
_tui._next_byte() {
	local __outvar="$1" __timeout="$2"
	if [[ -n "$_TUI_PENDING_INPUT" ]]; then
		printf -v "$__outvar" '%s' "${_TUI_PENDING_INPUT:0:1}"
		_TUI_PENDING_INPUT="${_TUI_PENDING_INPUT:1}"
		return 0
	fi
	IFS= read -rsn1 -t "$__timeout" "$__outvar"
}

# _tui._read_escape_seq - assembles the rest of an escape sequence (the
# part after ESC) one byte at a time until a terminator or the per-byte
# timeout, leaving the result in _TUI_SEQ_BUF. A `case` terminator check
# instead of a regex match keeps the per-byte cost as low as bash allows;
# it's still one read() per byte, which is exactly what the mouse-motion
# coalescer below exists to stop paying for on events nobody will ever see.
# Goes through _tui._next_byte (not a raw `read`) so that bytes rewound
# into _TUI_PENDING_INPUT by the coalescer are consumed here first, before
# falling through to the real fd - otherwise a rewound sequence would never
# be seen.
_tui._read_escape_seq() {
	_TUI_SEQ_BUF=""
	local c
	local t="$TUI_ESCSEQ_BYTE_TIMEOUT"
	# An SGR mouse report (ESC [ <) is always sent whole; on a laggy link or SSH its
	# tail can trail the head by more than the normal per-byte timeout. A split report
	# would leak its tail into the key stream as typed characters ("35;12;4M" landing
	# in a focused input), so once we know it is a mouse report, wait longer per byte.
	while _tui._next_byte c "$t"; do
		[[ "$_TUI_SEQ_BUF" == "[" && "$c" == "<" ]] && t="$TUI_ESCSEQ_MOUSE_TIMEOUT"
		_TUI_SEQ_BUF+="$c"
		if [[ "$_TUI_SEQ_BUF" == "O" ]]; then
			# ESC O X is an SS3 key (F1-F4, application-mode arrows), not alt+O
			if _tui._next_byte c "$TUI_ESCSEQ_BYTE_TIMEOUT"; then
				case "$c" in [PQRSABCDHFabcd])
					_TUI_SEQ_BUF+="$c"
					break
					;;
				*)
					_TUI_PENDING_INPUT="$c$_TUI_PENDING_INPUT"
					break
					;;
				esac
			fi
			break
		fi
		case "$c" in
			[A-Za-z~Mm]) break ;;
		esac
	done
}

# ═══════════════════════════════════════════════════════════════════════
#  PANE OUTPUT - render arbitrary multi-line content into a pane
# ═══════════════════════════════════════════════════════════════════════

tui.output() {
	local pane="$1"
	shift
	_TUI_PANE_CONTENT[$pane]=1
	declare -g -a "_TUI_PANE_CONTENT_${pane}"
	declare -n pane_arr="_TUI_PANE_CONTENT_${pane}"

	pane_arr=()
	if [[ $# -gt 0 ]]; then
		# here-string, not < <(printf ...): a process substitution is a fork per call (dozens per page load)
		local _t="$*"
		[[ -n "$_t" ]] && mapfile -t pane_arr <<<"${_t%$'\n'}"
	else
		mapfile -t pane_arr
	fi
	_tui._calc_bounds "$pane"
	((_TUI_RUNNING)) && _tui._queue_render "$pane"
}

tui.output_append() {
	local pane="$1"
	shift
	_TUI_PANE_CONTENT[$pane]=1
	declare -g -a "_TUI_PANE_CONTENT_${pane}"
	declare -n pane_arr="_TUI_PANE_CONTENT_${pane}"

	if [[ $# -gt 0 ]]; then
		local -a new_lines
		local _t="$*"
		[[ -n "$_t" ]] && mapfile -t new_lines <<<"${_t%$'\n'}"
		pane_arr+=("${new_lines[@]}")
	else
		local -a new_lines
		mapfile -t new_lines
		pane_arr+=("${new_lines[@]}")
	fi
	_tui._calc_bounds "$pane"
	((_TUI_RUNNING)) && _tui._queue_render "$pane"
}

tui.output_clear() {
	local pane="$1"
	_TUI_PANE_CONTENT[$pane]=""
	declare -g -a "_TUI_PANE_CONTENT_${pane}"
	declare -n pane_arr="_TUI_PANE_CONTENT_${pane}"
	pane_arr=()

	if ((_TUI_RUNNING)); then
		tui.clear_pane "$pane"
		_tui._draw_pane "$pane"
	fi
}

# _tui._render_output PANE - renders PANE's content, standalone (see
# _tui._draw_pane for the reset/build/print/restore shape and why:
# tui_api.sh's repaint calls this directly and expects an immediate
# write). Aggregate render paths call _tui._render_output_buf directly so
# every pane's content folds into one shared buffer and one flush.
_tui._render_output() {
	local _ro_saved="$_TUI_FRAME"
	_TUI_FRAME=""
	_tui._render_output_buf "$1"
	_tui._flush "$_TUI_FRAME"
	_TUI_FRAME="$_ro_saved"
}

# _tui._vslice LINE OFF MAX -> _VS: the MAX visible columns of LINE after skipping OFF, CSI sequences kept
# (they take no width), a reset appended. Pure bash: this used to be an awk fork on every coloured or scrolled pane.
# Pure in (LINE, OFF, MAX), so the result is memoised on exactly that triple: a scrolled-back or re-rendered line costs one
# lookup. Bounded: streamed output must not grow it without limit.
declare -gA _TUI_VS_MEMO=()
declare -gi _TUI_VS_MEMO_N=0
_tui._vslice() {
	local _vk="$2|$3|$1"
	if [[ -n "${_TUI_VS_MEMO[$_vk]+x}" ]]; then
		_VS="${_TUI_VS_MEMO[$_vk]}"
		return
	fi
	local s="$1" out="" chunk seq
	local -i off="$2" max="$3" vis=0 skipped=0 clen remain
	while [[ -n "$s" ]] && ((vis < max)); do
		if [[ "$s" == *$'\e'* ]]; then
			chunk="${s%%$'\e'*}"
			s="${s:${#chunk}}"
		else
			chunk="$s"
			s=""
		fi
		if ((skipped < off)); then
			clen=${#chunk}
			if ((skipped + clen <= off)); then
				skipped+=clen
				chunk=""
			else
				chunk="${chunk:off-skipped}"
				skipped=off
			fi
		fi
		if [[ -n "$chunk" ]]; then
			remain=$((max - vis))
			((${#chunk} > remain)) && chunk="${chunk:0:remain}"
			out+="$chunk"
			vis+=${#chunk}
		fi
		[[ -z "$s" ]] && break
		((vis >= max)) && break
		if [[ "$s" =~ ^$'\e'\[[0-9\;?]*[a-zA-Z] ]]; then
			seq="${BASH_REMATCH[0]}"
			out+="$seq"
			s="${s:${#seq}}"
		elif ((${#s} >= 2)); then
			s="${s:2}"
		else
			break
		fi
	done
	_VS="$out"$'\e[0m'
	if ((_TUI_VS_MEMO_N >= 4096)); then _TUI_VS_MEMO=() _TUI_VS_MEMO_N=0; fi
	_TUI_VS_MEMO[$_vk]="$_VS"
	_TUI_VS_MEMO_N+=1
}

# state:direct
_tui._render_output_buf() {
	local pane="$1" i
	((${_TUI_P_H[$pane]:-0} < 1 || ${_TUI_P_W[$pane]:-0} < 1)) && return # hidden, or no geometry (pane not on this page)
	declare -n lines="_TUI_PANE_CONTENT_${pane}"
	local scroll="${_TUI_P_SCROLL[$pane]:-none}"

	local pr=${_TUI_P_ROW[$pane]} pc=${_TUI_P_COL[$pane]}
	local ph=${_TUI_P_H[$pane]} pw=${_TUI_P_W[$pane]}
	local border="${_TUI_P_BORDER[$pane]:-single}"

	_tui._content_rect "$pane"
	local ct_row=$_CR_R ct_col=$_CR_C ct_w=$_CR_W ct_h=$_CR_H

	local total_lines=${_TUI_P_LINES[$pane]:-0}
	local max_w=${_TUI_P_MAX_W[$pane]:-0}

	# 1. Enforce Offset Clamping
	local v_off=${_TUI_P_SOFF_V[$pane]:-0}
	local h_off=${_TUI_P_SOFF_H[$pane]:-0}

	((total_lines <= ct_h)) && v_off=0
	((v_off > total_lines - ct_h && total_lines > ct_h)) && v_off=$((total_lines - ct_h))
	((v_off < 0)) && v_off=0
	_ps.panes.set "$pane" soff_v "$v_off"

	((max_w <= ct_w)) && h_off=0
	((h_off > max_w - ct_w && max_w > ct_w)) && h_off=$((max_w - ct_w))
	((h_off < 0)) && h_off=0
	_ps.panes.set "$pane" soff_h "$h_off"

	# Collect visible slice directly from memory
	local -a view_lines=()
	local start_idx=$v_off
	local end_idx=$((v_off + ct_h))
	((end_idx > total_lines)) && end_idx=$total_lines

	for ((i = start_idx; i < end_idx; i++)); do
		view_lines+=("${lines[$i]:-}")
	done

	_tui._style_v "${pane}_normal"
	local sty="$_SGR" res=$'\e[0m'

	# 2a. FAST PATH: no scrolling, everything fits, no escape codes -> plain padded lines.
	# (A screen of keycaps / labels / short status text is dozens of these per render.)
	local frame_buf="" fast=0 seg
	if [[ "$scroll" == none ]] && ((total_lines <= ct_h && max_w <= ct_w)); then
		fast=1
		for ((i = 0; i < total_lines; i++)); do [[ "${lines[i]:-}" == *$'\e'* ]] && {
			fast=0
			break
		}; done
	fi
	if ((fast)); then
		local ln sp seg
		for ((i = 0; i < ct_h; i++)); do
			ln="${lines[i]:-}"
			ln="${ln:0:ct_w}"
			printf -v sp '%*s' "$((ct_w - ${#ln}))" ''
			printf -v seg '\033[%d;%dH%s%s%s%s' $((ct_row + i)) "$ct_col" "$sty" "$ln" "$sp" "$res"
			frame_buf+="$seg"
		done
	fi
	# 2b. General path (escape codes, scrolling, overflow): slice each line in bash, no fork
	if ((! fast && ct_h > 0)); then
		local clr n=${#view_lines[@]}
		printf -v clr '%*s' "$ct_w" ''
		for ((i = 0; i < ct_h; i++)); do
			if ((i < n)); then
				# sty again before the text: the clear is followed by a reset, so without it the text
				# (and any centering spaces in it) is drawn in the terminal default, not the pane style
				_tui._vslice "${view_lines[i]}" "$h_off" "$ct_w"
				printf -v seg '\033[%d;%dH%s%s%s\033[%d;%dH%s%s' $((ct_row + i)) "$ct_col" "$sty" "$clr" "$res" \
					$((ct_row + i)) "$ct_col" "$sty" "$_VS"
			else
				printf -v seg '\033[%d;%dH%s%s%s' $((ct_row + i)) "$ct_col" "$sty" "$clr" "$res"
			fi
			frame_buf+="$seg"
		done
	fi

	# 3. Draw Scrollbars - printf -v into frame_buf (no command substitution, so no fork per cell).
	if [[ "$scroll" == "v" || "$scroll" == "both" ]] && ((total_lines > ct_h)); then
		local _SC_BAR
		_tui_scroll.bar_v "$pane" "$total_lines" "$v_off" "$sty"
		frame_buf+="$_SC_BAR"
	fi

	if [[ "$scroll" == "h" || "$scroll" == "both" ]] && ((max_w > ct_w)); then
		local track_y=$((pr + ph - 1))
		local thumb_w=$((ct_w * ct_w / max_w))
		((thumb_w < 1)) && thumb_w=1
		local thumb_x=$((ct_col + (h_off * (ct_w - thumb_w) / (max_w - ct_w))))

		for ((i = 0; i < ct_w; i++)); do
			if ((ct_col + i >= thumb_x && ct_col + i < thumb_x + thumb_w)); then
				printf -v seg '\033[%d;%dH%s\033[7m \033[0m' "$track_y" $((ct_col + i)) "$sty"
			else
				printf -v seg '\033[%d;%dH%s\033[2m─\033[0m' "$track_y" $((ct_col + i)) "$sty"
			fi
			frame_buf+="$seg"
		done
	fi

	_tui.emit "$frame_buf"
}
