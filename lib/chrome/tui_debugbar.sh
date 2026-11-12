#!/usr/bin/env bash
# tui_debugbar.sh - the debug status strip (like an editor's status bar): one row above the footer while `dabt --debug` runs.
#
#   tui.debug.bar [on|off|toggle]            show or hide the strip (it relayouts); default toggle
#   tui.debug.segment ID FN [left|right]     register a segment; FN sets _DBG_SEG to its text (empty = hidden)
#   tui.debug.segment.toggle ID              switch a segment on or off
#   tui.debug.init                           bind F12 (strip) and F11 (dev tools) and their palette commands; tui.init calls it under --debug
#
# Segments: pages (cached/known), build (pool building / re-fitting), visit (last page load), ready (first visits found
# cached), switch (total time of the last tui.goto), input (last key/click until its frame is out), render (frame write ms), cache (row-cache hit rate), miss (cache misses), boot (disk/stale at start, off by
# default), last (newest event, right side). Left segments that do not fit are dropped from the end.
# Style: theme classes .debugbar (the bar), .debugbar_chip (the DEBUG chip), .debugbar_warn (misses); built-in colours when absent.
# The strip is an ambient layer like the footer: only written when its text changes, and the row is reserved from the page
# (_tui._root_h) so it never covers content.
# requires: debug

declare -ga _TUI_DBG_SEG_IDS=()
declare -gA _TUI_DBG_SEG_FN=() _TUI_DBG_SEG_SIDE=() _TUI_DBG_SEG_OFF=()
declare -g _TUI_DBG_STR="" _TUI_DBG_PAINTED="" _DBG_SEG=""

# tui.debug.segment ID FN [left|right] - registers (or replaces) a segment; order of registration is the display order.
tui.debug.segment() {
	local id="$1" known=0 i
	for i in "${_TUI_DBG_SEG_IDS[@]}"; do [[ "$i" == "$id" ]] && known=1; done
	((known)) || _TUI_DBG_SEG_IDS+=("$id")
	_TUI_DBG_SEG_FN[$id]="$2"
	_TUI_DBG_SEG_SIDE[$id]="${3:-left}"
}

tui.debug.segment.toggle() {
	if [[ -n "${_TUI_DBG_SEG_OFF[$1]:-}" ]]; then unset '_TUI_DBG_SEG_OFF[$1]'; else _TUI_DBG_SEG_OFF[$1]=1; fi
	_TUI_DBG_PAINTED=""
	((_TUI_RUNNING)) && tui.frame.request
	return 0
}

# tui.debug.bar [on|off|toggle] - shows or hides the strip and gives the row back to / takes it from the page.
tui.debug.bar() {
	local want="${1:-toggle}"
	[[ "$want" == toggle ]] && { ((_TUI_DBG_BAR)) && want=off || want=on; }
	if [[ "$want" == on ]]; then
		((_TUI_DBG_BAR)) && return 0
		_TUI_DBG_BAR=1
		tui.layer.fn_add _tui_debugbar.draw ambient
		_tui_debug.reserve
	else
		((_TUI_DBG_BAR)) || return 0
		_TUI_DBG_BAR=0
		tui.layer.fn_remove _tui_debugbar.draw
		_tui_debug.reserve
	fi
	_TUI_DBG_PAINTED=""
	if ((_TUI_RUNNING)); then
		_tui._root_w
		_tui._root_h
		tui.frame.request
	fi
	return 0
}

# tui.debug.init - the F12 toggle and a palette command; the strip itself starts on.
tui.debug.init() {
	tui.bind f12 "tui.debug.bar toggle" --always --desc "Toggle the debug bar"
	tui.cmd.add debug.bar "Toggle the debug bar" "tui.debug.bar toggle" --group Debug
	tui.bind f11 "_tui_devtools.f11" --always --desc "Dev tools: open, focus or close"
	tui.cmd.add debug.devtools "Toggle the dev tools" "tui.debug.devtools toggle" --group Debug
	tui.debug.bar on
}

# ── built-in segments: each sets _DBG_SEG ─────────────────────────────────

_tui_debugbar.seg_render() {
	local ms
	tui.perf.mean_render_ms 5 ms
	if [[ -n "$ms" ]]; then _DBG_SEG="render ${ms}ms"; else _DBG_SEG="render n/a"; fi
}

_tui_debugbar.seg_cache() {
	local hit="${_TUI_PERF_COUNTERS[rowcache_hit]:-0}" miss="${_TUI_PERF_COUNTERS[rowcache_miss]:-0}"
	((hit + miss)) || {
		_DBG_SEG=""
		return
	}
	_DBG_SEG="cache $((hit * 100 / (hit + miss)))%"
}

_tui_debugbar.seg_miss() {
	local name total=0
	for name in "${!_TUI_DBG_COUNT[@]}"; do [[ "$name" == *.miss ]] && ((total += _TUI_DBG_COUNT[$name])); done
	((total)) || {
		_DBG_SEG=""
		return
	}
	_DBG_SEG="⚠ $total miss"
}

# the key to the dev tools; first on the right so a tight row cuts the newest-event text instead
_tui_debugbar.seg_hint() { if ((_TUI_DTL_ON)); then _DBG_SEG="F11 close"; else _DBG_SEG="F11 dev tools"; fi; }

_tui_debugbar.seg_last() {
	local n=${#_TUI_DBG_RING[@]}
	((n)) || {
		_DBG_SEG=""
		return
	}
	local ev="${_TUI_DBG_RING[n - 1]}"
	_DBG_SEG="${ev#* }"
}

# pages cached in memory of the pages the app knows (tui.start_cached); shell and template pages (_NAME.xml) are not counted:
# they are cached too but are not among the known pages
_tui_debugbar.seg_pages() {
	((_TUI_CACHE_TOTAL)) || {
		_DBG_SEG=""
		return
	}
	local page cached=0
	for page in "${!_TUI_CACHE_PAGE[@]}"; do [[ "${page##*/}" == _* ]] || ((cached++)); done
	_DBG_SEG="pages $cached/$_TUI_CACHE_TOTAL"
}

# the background pool: pages still being built from scratch, and cached ones being re-fitted to a new terminal size
_tui_debugbar.seg_build() {
	local page building=0 refit=0
	for page in "${_TUI_LAZY_PENDING[@]}"; do
		if [[ -n "${_TUI_LAZY_REFRESH[$page]+x}" ]]; then ((refit++)); else ((building++)); fi
	done
	_DBG_SEG=""
	((building)) && _DBG_SEG="⟳ building $building"
	((refit)) && _DBG_SEG+="${_DBG_SEG:+ }refit $refit"
}

# the latest page load: which page, whether it came from the cache, how long it took
_tui_debugbar.seg_visit() { _DBG_SEG="${_TUI_DBG_LAST_VISIT:+visit $_TUI_DBG_LAST_VISIT}"; }

# first visits that found their page already cached ("ready") of all first visits
_tui_debugbar.seg_ready() {
	((_TUI_DBG_FIRST_N)) || {
		_DBG_SEG=""
		return
	}
	_DBG_SEG="ready $_TUI_DBG_FIRST_HIT/$_TUI_DBG_FIRST_N"
}

# total time of the last page switch (tui.goto: reset, load or replay, focus, repaint)
_tui_debugbar.seg_switch() { _DBG_SEG="${_TUI_DBG_LAST_SWITCH:+switch ${_TUI_DBG_LAST_SWITCH#* }}"; }

# the last interaction: event received until its frame is out
_tui_debugbar.seg_input() { _DBG_SEG="${_TUI_DBG_LAST_INPUT:+input $_TUI_DBG_LAST_INPUT}"; }

# this start: pages found valid on disk and pages that had to be built
_tui_debugbar.seg_boot() {
	((_TUI_CACHE_TOTAL)) || {
		_DBG_SEG=""
		return
	}
	_DBG_SEG="disk $_TUI_CACHE_ON_DISK stale $_TUI_CACHE_STALE"
}

tui.debug.segment pages _tui_debugbar.seg_pages left
tui.debug.segment build _tui_debugbar.seg_build left
tui.debug.segment visit _tui_debugbar.seg_visit left
tui.debug.segment ready _tui_debugbar.seg_ready left
tui.debug.segment switch _tui_debugbar.seg_switch left
tui.debug.segment input _tui_debugbar.seg_input left
tui.debug.segment render _tui_debugbar.seg_render left
tui.debug.segment cache _tui_debugbar.seg_cache left
tui.debug.segment miss _tui_debugbar.seg_miss left
tui.debug.segment boot _tui_debugbar.seg_boot left
tui.debug.segment hint _tui_debugbar.seg_hint right
tui.debug.segment last _tui_debugbar.seg_last right
_TUI_DBG_SEG_OFF[boot]=1 # off until asked for: it only matters at startup

# _tui_debugbar.build - composes _TUI_DBG_STR: left segments, then the right ones flush to the edge; the right side drops
# first, then left segments, so the row never exceeds the terminal width.
_tui_debugbar.build() {
	local id s_bar s_chip s_warn left="" right="" lplain=" DEBUG " rplain="" w=$_TUI_COLS seg
	tui.class.sgr debugbar
	s_bar="${TUI_SGR:-$'\e[0;37;48;2;40;44;52m'}"
	tui.class.sgr debugbar_chip
	s_chip="${TUI_SGR:-$'\e[1;30;48;2;229;192;123m'}"
	tui.class.sgr debugbar_warn
	s_warn="${TUI_SGR:-$'\e[1;38;2;229;192;123;48;2;40;44;52m'}"
	left="${s_chip} DEBUG ${s_bar}"
	for id in "${_TUI_DBG_SEG_IDS[@]}"; do
		[[ -n "${_TUI_DBG_SEG_OFF[$id]:-}" ]] && continue
		_DBG_SEG=""
		"${_TUI_DBG_SEG_FN[$id]}"
		[[ -z "$_DBG_SEG" ]] && continue
		seg=" ${_DBG_SEG} "
		if [[ "${_TUI_DBG_SEG_SIDE[$id]}" == right ]]; then
			right+="$seg"
			rplain+="$seg"
		else
			((${#lplain} + ${#seg} + 1 > w)) && continue
			[[ "$id" == miss ]] && left+="${s_warn}${seg}${s_bar}" || left+="$seg"
			lplain+="$seg"
		fi
	done
	local room=$((w - 1 - ${#lplain}))
	if ((${#rplain} > room)); then # cut the right text to fit, or drop it when almost nothing is left
		((room > 4)) && {
			right=" ${rplain:1:room-2}… "
			rplain="$right"
		} || {
			right=""
			rplain=""
		}
	fi
	local pad
	printf -v pad '%*s' "$((w - 1 - ${#lplain} - ${#rplain}))" ''
	_TUI_DBG_STR="${s_bar}${left}${pad}${right} "$'\e[0m'
}

# _tui_debugbar.refresh - writes the strip row now when its text changed. Ambient layers only paint inside a flush, and the
# interaction and switch timings are known after the frame is out: without this the strip would show them one frame late.
_tui_debugbar.refresh() {
	((_TUI_DBG_BAR && _TUI_RUNNING)) || return 0
	local saved_frame="$_TUI_FRAME"
	_TUI_FRAME=""
	_tui_debugbar.draw
	[[ -n "$_TUI_FRAME" ]] && _tui.write "$_TUI_FRAME"
	_TUI_FRAME="$saved_frame"
}

# overlay DRAWFN: appends to _TUI_FRAME, an ambient function layer (tui_layer.sh).
_tui_debugbar.draw() {
	((_TUI_DBG_BAR)) || return 0
	_tui_debugbar.build
	local row=$((_TUI_ROWS - _TUI_FOOTER_ON)) painted
	painted="$row:$_TUI_DBG_STR"
	[[ "$painted" == "$_TUI_DBG_PAINTED" ]] && return 0
	_TUI_DBG_PAINTED="$painted"
	_tui.emit_printf '\e7\e[?7l\e[%d;1H%s\e[K\e[?7h\e8' "$row" "$_TUI_DBG_STR"
}
