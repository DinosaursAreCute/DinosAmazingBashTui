#!/usr/bin/env bash
# tui_devtools.sh - the dev-tools dock for `dabt --debug`: a panel docked above the debug strip, the app stays visible above it.
#
#   tui.debug.devtools [open|close|toggle|focus|blur]   show, hide or move the keyboard to the dock (default toggle)
#   F11 (bound by tui.debug.init): closed -> open and focused -> closed; open but not focused -> focused
#
# Tabs: Events (live event log), Pages (page cache and loads), Perf (spans), Counters (perf counters and event totals).
# While the dock has focus these keys are its own (bound on focus, unbound on blur; every other key still reaches the app):
#   left right | 1-4   tab            up down pgup pgdn   scroll (Events: back in time)      home end   top / follow
#   p   pause or resume the Events tab     c   clear events     f   cycle the Events category filter
#   m   maximise or restore the dock        esc  give the keyboard back to the app (the dock stays open)
# Style: theme classes .devtools (body), .devtools_head, .devtools_tab, .devtools_tab_active, .devtools_warn, .devtools_dim;
# built-in colours when absent.
# The dock is an ambient layer like the footer and the strip: its rows are reserved from the page (_tui._root_h), it is only
# written when its content stamp changes, and a 4 Hz tick keeps it live while the app is idle.
# requires: debug

declare -gi _TUI_DTL_ON=0 _TUI_DTL_FOCUS=0 _TUI_DTL_MAX=0 _TUI_DTL_PAUSED=0 _TUI_DTL_SCROLL=0 _TUI_DTL_TAB=0 _TUI_DTL_TOTAL=0
declare -g _TUI_DTL_FILTER="" _TUI_DTL_PAINTED="" _TUI_DTL_STAMP="" _TUI_DTL_OUT=""
declare -ga _TUI_DTL_LINES=() _TUI_DTL_SEV=() _TUI_DTL_FROZEN=() _TUI_DTL_KEYS=() _TUI_DTL_CATS=()
declare -ga _TUI_DTL_TABS=(Events Pages Perf Counters)
declare -gi _TUI_DTL_TICK_US=0
declare -g _TUI_DTL_KEYLIST="left right up down pgup pgdn home end p c f m esc 1 2 3 4"

# ── open / close / focus ──────────────────────────────────────────────────

# tui.debug.devtools [open|close|toggle|focus|blur] - shows or hides the dock and moves the keyboard to or from it.
tui.debug.devtools() {
	case "${1:-toggle}" in
		toggle) ((_TUI_DTL_ON)) && set -- close || set -- open ;;
	esac
	case "$1" in
		open)
			if ((! _TUI_DTL_ON)); then
				_TUI_DTL_ON=1
				_tui_devtools.fit
				tui.layer.fn_add _tui_devtools.draw ambient
				tui.tick.add _tui_devtools.tick
				_tui_devtools.relayout
			fi
			_tui_devtools.focus 1
			;;
		close)
			((_TUI_DTL_ON)) || return 0
			_tui_devtools.focus 0
			_TUI_DTL_ON=0 _TUI_DBG_DOCK=0
			_tui_debug.reserve
			tui.layer.fn_remove _tui_devtools.draw
			tui.tick.remove _tui_devtools.tick
			_TUI_DTL_PAINTED="" _TUI_DTL_STAMP=""
			_tui_devtools.relayout
			;;
		focus) ((_TUI_DTL_ON)) && _tui_devtools.focus 1 ;;
		blur) _tui_devtools.focus 0 ;;
	esac
	return 0
}

# _tui_devtools.f11 - closed -> open and focused; open and focused -> closed; open but blurred -> focused.
_tui_devtools.f11() {
	if ((_TUI_DTL_ON && ! _TUI_DTL_FOCUS)); then tui.debug.devtools focus; else tui.debug.devtools toggle; fi
}

# _tui_devtools.focus 0|1 - binds or unbinds the dock's keys: only while it has focus do they shadow the app's.
_tui_devtools.focus() {
	local k
	((_TUI_DTL_FOCUS == $1)) && return 0
	_TUI_DTL_FOCUS=$1
	for k in $_TUI_DTL_KEYLIST; do
		if (($1)); then tui.bind "$k" "_tui_devtools.key $k" --always; else tui.unbind "$k"; fi
	done
	_TUI_DTL_STAMP=""
	_tui_devtools.refresh
}

_tui_devtools.relayout() {
	if ((_TUI_RUNNING)); then
		_tui._root_w
		_tui._root_h
		tui.frame.request
	fi
}

# _tui_devtools.fit - the dock's height from the terminal: 30% (at least 8 rows), or everything but 3 page rows when maximised.
_tui_devtools.fit() {
	local avail=$((_TUI_ROWS - _TUI_FOOTER_ON - _TUI_DBG_BAR)) h
	if ((_TUI_DTL_MAX)); then h=$((avail - 3)); else h=$((_TUI_ROWS * 3 / 10)); fi
	((h < 8 && ! _TUI_DTL_MAX)) && h=8
	((h > avail - 3)) && h=$((avail - 3))
	((h < 3)) && h=0
	_TUI_DBG_DOCK=$h
	_tui_debug.reserve
}

# ── keys ──────────────────────────────────────────────────────────────────

# _tui_devtools.key NAME - a bound dock key.
_tui_devtools.key() {
	local page=$((_TUI_DBG_DOCK - 2))
	((page < 1)) && page=1
	case "$1" in
		left) _tui_devtools.tab $((_TUI_DTL_TAB - 1)) ;;
		right) _tui_devtools.tab $((_TUI_DTL_TAB + 1)) ;;
		[1-4]) _tui_devtools.tab $(($1 - 1)) ;;
		up) _tui_devtools.scroll -1 ;;
		down) _tui_devtools.scroll 1 ;;
		pgup) _tui_devtools.scroll $((-page)) ;;
		pgdn) _tui_devtools.scroll "$page" ;;
		home) _TUI_DTL_SCROLL=$((_TUI_DTL_TAB == 0 ? 1000000 : 0)) ;;
		end) _TUI_DTL_SCROLL=$((_TUI_DTL_TAB == 0 ? 0 : 1000000)) ;;
		p) _tui_devtools.pause ;;
		c) _TUI_DBG_RING=() _TUI_DBG_COUNT=() _TUI_DTL_FROZEN=() _TUI_DTL_SCROLL=0 ;;
		f) _tui_devtools.next_filter ;;
		m)
			_TUI_DTL_MAX=$((! _TUI_DTL_MAX))
			_tui_devtools.fit
			_tui_devtools.relayout
			;;
		esc)
			tui.debug.devtools blur
			return 0
			;;
	esac
	_TUI_DTL_STAMP=""
	_tui_devtools.refresh
}

_tui_devtools.tab() {
	local n=${#_TUI_DTL_TABS[@]}
	_TUI_DTL_TAB=$((((($1 % n) + n) % n)))
	_TUI_DTL_SCROLL=0
}

# _tui_devtools.scroll DELTA - DELTA rows down the list; on the Events tab "down" is toward the newest event (scroll counts rows back from it).
_tui_devtools.scroll() {
	if ((_TUI_DTL_TAB == 0)); then _TUI_DTL_SCROLL=$((_TUI_DTL_SCROLL - $1)); else _TUI_DTL_SCROLL=$((_TUI_DTL_SCROLL + $1)); fi
	((_TUI_DTL_SCROLL < 0)) && _TUI_DTL_SCROLL=0
}

# pausing freezes a copy of the event ring: the live one keeps filling
_tui_devtools.pause() {
	if ((_TUI_DTL_PAUSED)); then
		_TUI_DTL_PAUSED=0
		_TUI_DTL_FROZEN=()
	else
		_TUI_DTL_PAUSED=1
		_TUI_DTL_FROZEN=("${_TUI_DBG_RING[@]}")
	fi
}

# the filter cycles through "" (all) and every category seen so far, in order of first appearance
_tui_devtools.next_filter() {
	local name cat seen=" "
	_TUI_DTL_CATS=("")
	for name in "${_TUI_DBG_RING[@]}"; do
		name="${name#* }"
		cat="${name%%[ .]*}"
		[[ "$seen" == *" $cat "* ]] && continue
		seen+="$cat "
		_TUI_DTL_CATS+=("$cat")
	done
	local i next=0
	for i in "${!_TUI_DTL_CATS[@]}"; do [[ "${_TUI_DTL_CATS[i]}" == "$_TUI_DTL_FILTER" ]] && next=$((i + 1)); done
	_TUI_DTL_FILTER="${_TUI_DTL_CATS[next % ${#_TUI_DTL_CATS[@]}]}"
	_TUI_DTL_SCROLL=0
}

# ── tab contents: each fills _TUI_DTL_LINES (one string per row) and _TUI_DTL_SEV (0 normal, 1 warning, 2 dim) ──────────

# _tui_devtools.sort ARRAY_NAME - _TUI_DTL_KEYS = the keys of the associative array, sorted (insertion sort: lists are short).
_tui_devtools.sort() {
	local -n _src="$1"
	local k j
	_TUI_DTL_KEYS=()
	for k in "${!_src[@]}"; do
		_TUI_DTL_KEYS+=("$k")
		for ((j = ${#_TUI_DTL_KEYS[@]} - 1; j > 0; j--)); do
			[[ "${_TUI_DTL_KEYS[j - 1]}" > "${_TUI_DTL_KEYS[j]}" ]] || break
			k="${_TUI_DTL_KEYS[j - 1]}"
			_TUI_DTL_KEYS[j - 1]="${_TUI_DTL_KEYS[j]}"
			_TUI_DTL_KEYS[j]="$k"
		done
	done
}

# _tui_devtools.fmt_us MICROSECONDS -> _R ("12.3" ms)
_tui_devtools.fmt_us() { _R="$(($1 / 1000)).$((($1 % 1000) / 100))"; }

# Events: the newest events at the bottom; _TUI_DTL_SCROLL counts rows back from the newest. Only the visible window is formatted.
_tui_devtools.build_events() {
	local rows=$1 entry name rest us rel n=0 start end i ts line
	local -a sel=()
	local source=_TUI_DBG_RING
	((_TUI_DTL_PAUSED)) && source=_TUI_DTL_FROZEN
	local -n ring="$source"
	for entry in "${ring[@]}"; do
		rest="${entry#* }"
		[[ -z "$_TUI_DTL_FILTER" || "$rest" == "$_TUI_DTL_FILTER"[.\ ]* ]] && sel+=("$entry")
	done
	n=${#sel[@]}
	_TUI_DTL_TOTAL=$n
	((_TUI_DTL_SCROLL > n - rows)) && _TUI_DTL_SCROLL=$((n - rows > 0 ? n - rows : 0))
	end=$((n - _TUI_DTL_SCROLL))
	start=$((end - rows))
	((start < 0)) && start=0
	_TUI_DTL_LINES=() _TUI_DTL_SEV=()
	for ((i = start; i < end; i++)); do
		entry="${sel[i]}"
		us="${entry%% *}"
		rest="${entry#* }"
		name="${rest%% *}"
		rel=$((us - _TUI_DBG_T0))
		printf -v ts '+%d.%03d' $((rel / 1000000)) $(((rel / 1000) % 1000))
		printf -v line '%9s  %-22s %s' "$ts" "$name" "${rest#"$name"}"
		_TUI_DTL_LINES+=("$line")
		[[ "$name" == *.miss || "$name" == error* ]] && _TUI_DTL_SEV+=(1) || _TUI_DTL_SEV+=(0)
	done
	((n)) || {
		_TUI_DTL_LINES=("  no events yet")
		_TUI_DTL_SEV=(2)
	}
}

# Pages: the page cache at a glance, then one row per page.
_tui_devtools.build_pages() {
	local page name state size visits last cached=0 building=0 refit=0
	local -A all=()
	for page in "${!_TUI_CACHE_PAGE[@]}"; do
		all[$page]=cached
		[[ "${page##*/}" == _* ]] || ((cached++))
	done
	for page in "${_TUI_LAZY_PENDING[@]}"; do
		if [[ -n "${_TUI_LAZY_REFRESH[$page]+x}" ]]; then ((refit++)); else
			((building++))
			all[$page]=building
		fi
	done
	local line
	_TUI_DTL_LINES=("  cached $cached/$_TUI_CACHE_TOTAL   on disk at start $_TUI_CACHE_ON_DISK   built this start $_TUI_CACHE_STALE   building $building   re-fitting $refit   first visits ready $_TUI_DBG_FIRST_HIT/$_TUI_DBG_FIRST_N")
	_TUI_DTL_SEV=(0)
	printf -v line '  %-26s %-9s %7s %7s  %s' page state size loads last
	_TUI_DTL_LINES+=("$line")
	_TUI_DTL_SEV+=(2)
	_tui_devtools.sort all
	for page in "${_TUI_DTL_KEYS[@]}"; do
		name="${page##*/}"
		state="${all[$page]}"
		size="$((${#_TUI_CACHE_PAGE[$page]} / 1024))K"
		visits="${_TUI_DBG_VISITS[$page]:-0}"
		last="${_TUI_DBG_PAGE_LAST[$page]:--}"
		printf -v line '  %-26s %-9s %7s %7s  %s' "${name%.xml}" "$state" "$size" "$visits" "$last"
		_TUI_DTL_LINES+=("$line")
		[[ "$state" == building ]] && _TUI_DTL_SEV+=(1) || _TUI_DTL_SEV+=(0)
	done
}

# Perf: one row per tracked span from the perf ring (needs _TUI_PERF_TRACKING, which --debug turns on).
_tui_devtools.build_perf() {
	local span v sum max last n
	local -a vals
	local line
	printf -v line '  %-18s %9s %9s %9s %7s' span 'last ms' 'mean ms' 'max ms' count
	_TUI_DTL_LINES=("$line")
	_TUI_DTL_SEV=(2)
	_tui_devtools.sort _TUI_PERF_LOG
	for span in "${_TUI_DTL_KEYS[@]}"; do
		vals=(${_TUI_PERF_LOG[$span]})
		n=${#vals[@]}
		((n)) || continue
		sum=0 max=0 last=${vals[n - 1]}
		for v in "${vals[@]}"; do
			((sum += v))
			((v > max)) && max=$v
		done
		local f_last f_mean f_max
		_tui_devtools.fmt_us "$last"
		f_last=$_R
		_tui_devtools.fmt_us $((sum / n))
		f_mean=$_R
		_tui_devtools.fmt_us "$max"
		f_max=$_R
		printf -v line '  %-18s %9s %9s %9s %7d' "$span" "$f_last" "$f_mean" "$f_max" "$n"
		_TUI_DTL_LINES+=("$line")
		_TUI_DTL_SEV+=(0)
	done
	((${#_TUI_DTL_LINES[@]} > 1)) || {
		_TUI_DTL_LINES+=("  no spans recorded yet")
		_TUI_DTL_SEV+=(2)
	}
}

# Counters: the perf counters, then how many times each debug event fired.
_tui_devtools.build_counters() {
	local k line
	_TUI_DTL_LINES=("  perf counters") _TUI_DTL_SEV=(2)
	_tui_devtools.sort _TUI_PERF_COUNTERS
	for k in "${_TUI_DTL_KEYS[@]}"; do
		printf -v line '  %-28s %10d' "$k" "${_TUI_PERF_COUNTERS[$k]}"
		_TUI_DTL_LINES+=("$line")
		_TUI_DTL_SEV+=(0)
	done
	_TUI_DTL_LINES+=("  events") _TUI_DTL_SEV+=(2)
	_tui_devtools.sort _TUI_DBG_COUNT
	for k in "${_TUI_DTL_KEYS[@]}"; do
		printf -v line '  %-28s %10d' "$k" "${_TUI_DBG_COUNT[$k]}"
		_TUI_DTL_LINES+=("$line")
		[[ "$k" == *.miss || "$k" == error* ]] && _TUI_DTL_SEV+=(1) || _TUI_DTL_SEV+=(0)
	done
}

# _tui_devtools.build ROWS - fills _TUI_DTL_LINES/_TUI_DTL_SEV for the current tab, clipped to the ROWS visible.
_tui_devtools.build() {
	local rows=$1 max
	case $_TUI_DTL_TAB in
		0)
			_tui_devtools.build_events "$rows"
			return
			;;
		1) _tui_devtools.build_pages ;;
		2) _tui_devtools.build_perf ;;
		3) _tui_devtools.build_counters ;;
	esac
	_TUI_DTL_TOTAL=${#_TUI_DTL_LINES[@]}
	max=$((_TUI_DTL_TOTAL - rows))
	((max < 0)) && max=0
	((_TUI_DTL_SCROLL > max)) && _TUI_DTL_SCROLL=$max
	_TUI_DTL_SEV=("${_TUI_DTL_SEV[@]:_TUI_DTL_SCROLL:rows}")
	_TUI_DTL_LINES=("${_TUI_DTL_LINES[@]:_TUI_DTL_SCROLL:rows}")
}

# ── drawing ───────────────────────────────────────────────────────────────

# _tui_devtools.compose - _TUI_DTL_OUT = the dock as absolute-positioned rows.
_tui_devtools.compose() {
	local E=$'\e' w=$_TUI_COLS rows=$((_TUI_DBG_DOCK - 1)) top i label tabs="" plain=" " right="" s_body s_head s_tab s_on s_warn s_dim line sev
	top=$((_TUI_ROWS - _TUI_FOOTER_ON - _TUI_DBG_BAR - _TUI_DBG_DOCK + 1))
	tui.class.sgr devtools
	s_body="${TUI_SGR:-$'\e[0;37;48;2;30;34;42m'}"
	tui.class.sgr devtools_head
	s_head="${TUI_SGR:-$'\e[0;37;48;2;44;49;60m'}"
	tui.class.sgr devtools_tab
	s_tab="${TUI_SGR:-$s_head}"
	tui.class.sgr devtools_tab_active
	s_on="${TUI_SGR:-$'\e[1;30;48;2;97;175;239m'}"
	tui.class.sgr devtools_warn
	s_warn="${TUI_SGR:-$'\e[0;38;2;229;192;123;48;2;30;34;42m'}"
	tui.class.sgr devtools_dim
	s_dim="${TUI_SGR:-$'\e[0;38;2;120;126;138;48;2;30;34;42m'}"

	for i in "${!_TUI_DTL_TABS[@]}"; do
		label=" $((i + 1)) ${_TUI_DTL_TABS[i]} "
		plain+="$label "
		if ((i == _TUI_DTL_TAB)); then tabs+="${s_on}${label}${s_head} "; else tabs+="${s_tab}${label}${s_head} "; fi
	done
	((_TUI_DTL_TAB == 0)) && {
		((_TUI_DTL_PAUSED)) && right+="paused  "
		[[ -n "$_TUI_DTL_FILTER" ]] && right+="filter:$_TUI_DTL_FILTER  "
		right+="${_TUI_DTL_TOTAL} events  "
		((_TUI_DTL_SCROLL)) && right+="(-$_TUI_DTL_SCROLL)  " || right+="follow  "
	}
	if ((_TUI_DTL_FOCUS)); then right+="←→ tab  p pause  f filter  c clear  m max  esc leave "; else right+="F11 focus "; fi
	local pad=$((w - ${#plain} - ${#right}))
	((pad < 0)) && {
		right="${right:0:w-${#plain}>0?w-${#plain}:0}"
		pad=0
	}
	printf -v pad '%*s' "$pad" ''
	_TUI_DTL_OUT="${E}7${E}[?7l${E}[${top};1H${s_head} ${tabs}${pad}${right}${E}[K"

	_tui_devtools.build "$rows"
	for ((i = 0; i < rows; i++)); do
		line="${_TUI_DTL_LINES[i]:-}"
		sev="${_TUI_DTL_SEV[i]:-0}"
		case $sev in
			1) label="$s_warn" ;;
			2) label="$s_dim" ;;
			*) label="$s_body" ;;
		esac
		_TUI_DTL_OUT+="${E}[$((top + 1 + i));1H${label}${line:0:w-1}${E}[K"
	done
	_TUI_DTL_OUT+="${E}[0m${E}[?7h${E}8"
}

# overlay DRAWFN: appends to _TUI_FRAME, an ambient function layer (tui_layer.sh).
_tui_devtools.draw() {
	((_TUI_DTL_ON && _TUI_DBG_DOCK)) || return 0
	local stamp now=${EPOCHREALTIME//[!0-9]/}
	stamp="$_TUI_DTL_TAB:$_TUI_DTL_SCROLL:$_TUI_DTL_PAUSED:$_TUI_DTL_FILTER:$_TUI_DBG_SEQ:$_TUI_DBG_DOCK:$_TUI_ROWS:$_TUI_COLS:$_TUI_DTL_FOCUS:$_TUI_FOOTER_ON:$_TUI_DBG_BAR"
	((_TUI_DTL_TAB)) && stamp+=":$((now / 500000))" # the other tabs read live state: rebuilt at most twice a second
	[[ "$stamp" == "$_TUI_DTL_STAMP" && -n "$_TUI_DTL_PAINTED" ]] && return 0
	_TUI_DTL_STAMP="$stamp"
	_tui_devtools.compose
	[[ "$_TUI_DTL_OUT" == "$_TUI_DTL_PAINTED" ]] && return 0
	_TUI_DTL_PAINTED="$_TUI_DTL_OUT"
	_tui.emit "$_TUI_DTL_OUT"
}

# _tui_devtools.refresh - writes the dock now when it changed (ambient layers only paint inside a flush).
_tui_devtools.refresh() {
	((_TUI_DTL_ON && _TUI_RUNNING)) || return 0
	local saved_frame="$_TUI_FRAME"
	_TUI_FRAME=""
	_tui_devtools.draw
	[[ -n "$_TUI_FRAME" ]] && _tui.write "$_TUI_FRAME"
	_TUI_FRAME="$saved_frame"
}

# tick listener: keeps the dock and the strip live while the app is idle (events from the cache pool, ticks, ...)
_tui_devtools.tick() {
	local now=${EPOCHREALTIME//[!0-9]/}
	((now - _TUI_DTL_TICK_US < 250000)) && return 0
	_TUI_DTL_TICK_US=$now
	_tui_debugbar.refresh
	_tui_devtools.refresh
}
