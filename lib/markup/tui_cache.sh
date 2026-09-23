#!/usr/bin/env bash
# tui_cache.sh - page-load caching.
#
# tui_markup.sh's tui.load spends most of its time re-parsing a page's XML
# text (regex attribute extraction, per-tag dispatch) on every single visit,
# even though the resulting sequence of tui.* builder calls (tui.hsplit,
# tui.label, tui.button, ...) is identical every time for a page's *static*
# structure. This records that call sequence once and replays it later by
# eval-ing the (already-quoted) saved lines - no markup re-parsing at all.
#
# Dynamic content stays dynamic: a page's <script src> sourcing and its
# on_visit handler are themselves recorded as single calls (see
# _tui_cache_source / _tui_cache_run_on_visit below), so replaying a cached
# page still re-sources what it needs and always reruns on_visit fresh -
# only the static pane/widget build is skipped on a cache hit.
#
# Fallback contract: tui.load_cached is a drop-in replacement for tui.load.
# A cache miss (first visit, or a page never warmed) does a completely
# normal tui.load and records it for next time - never a behavior
# difference, purely a speed difference.
#
# <script src> is deliberately re-sourced on every replay too, cache hit or
# not - several pages (monitor_callbacks.sh, debug_callbacks.sh,
# terminal_init.sh) do real per-visit work as plain top-level code at the
# bottom of the callback file, not inside on_visit. Skipping that on a
# cache hit silently drops it. Re-declaring already-identical functions is
# cheap; only the markup parse is what's actually worth caching.

declare -g _TUI_CACHE_RECORDING=0
declare -g _TUI_CACHE_DEPTH=0
declare -ga _TUI_CACHE_BUF=()
declare -gA _TUI_CACHE_PAGE=() # resolved page path -> newline-joined recorded commands
declare -gA _TUI_CACHE_SIG=()  # resolved page path -> "dep=mtime dep=mtime ..." signature

# ── stylesheet memoization ──────────────────────────────────────────────
# The page cache above replays a page's recorded `tui.load_theme FILE` call on every visit, and
# tui_style.sh's parse of that file used to run again each time (~250 ms for theme.css, doubled
# with a theme overlay). This REDEFINES tui_style.sh's _tui.theme_load_file so each stylesheet is
# parsed ONCE per process, then re-applied from memory (a handful of array assignments, no file
# read, no forks).
#
# Freshness is fork-free too: after a parse we `: > STAMP` (a builtin redirect = touch), and a file
# is stale when it is newer than its stamp (`[[ FILE -nt STAMP ]]` - no stat, no subshell). So
# editing theme.css still takes effect on the next page visit, like the page cache itself.
declare -gA _TUI_THEME_MEMO=() _TUI_THEME_STAMP=() # file -> "class<US>fg<US>bg<US>mods\n..." / stamp path
declare -g _TUI_THEME_STAMP_DIR="" _TUI_THEME_STAMP_N=0

_tui_cache_theme_stamp() { # FILE -> sets _TS to a fresh stamp path (creates the dir lazily, once)
	if [[ -z "$_TUI_THEME_STAMP_DIR" || ! -d "$_TUI_THEME_STAMP_DIR" ]]; then
		_TUI_THEME_STAMP_DIR="${TMPDIR:-/tmp}/tui_theme_stamps.$$"
		mkdir -p "$_TUI_THEME_STAMP_DIR"
	fi
	_TS="${_TUI_THEME_STAMP[$1]:-$_TUI_THEME_STAMP_DIR/$((++_TUI_THEME_STAMP_N))}"
	: >"$_TS"
	_TUI_THEME_STAMP[$1]="$_TS"
}

_tui.theme_load_file() {
	local file="$1" cls fg bg mods out=""
	if [[ -n "${_TUI_THEME_MEMO[$file]+x}" && ! "$file" -nt "${_TUI_THEME_STAMP[$file]}" ]]; then
		while IFS=$'\x1f' read -r cls fg bg mods; do # hit: re-apply, nothing is parsed
			[[ -z "$cls" ]] && continue
			[[ -n "$fg" ]] && _TUI_CLASS_FG[$cls]="$fg"
			[[ -n "$bg" ]] && _TUI_CLASS_BG[$cls]="$bg"
			[[ -n "$mods" ]] && _TUI_CLASS_MOD[$cls]="$mods"
		done <<<"${_TUI_THEME_MEMO[$file]}"
		return 0
	fi

	_tui.theme_parse "$file" || return 1
	_tui.theme_commit
	for cls in "${_TP_ORDER[@]}"; do
		out+="$cls"$'\x1f'"${_TP_FG[$cls]:-}"$'\x1f'"${_TP_BG[$cls]:-}"$'\x1f'"${_TP_MOD[$cls]:-}"$'\n'
	done
	_TUI_THEME_MEMO[$file]="$out"
	_tui_cache_theme_stamp "$file"
	_tui.theme_check "$file"
}

# Forget every memoized stylesheet (tests, or after changing files in a way mtimes can't show).
tui.cache.theme_clear() {
	_TUI_THEME_MEMO=()
	_TUI_THEME_STAMP=()
}

# Removes the stamp directory; called from _master_cleanup.
tui.cache.cleanup() {
	[[ -n "$_TUI_THEME_STAMP_DIR" && -d "$_TUI_THEME_STAMP_DIR" ]] && rm -rf "$_TUI_THEME_STAMP_DIR"
	_TUI_THEME_STAMP_DIR=""
}

# Stands in for a raw `source` on <script src> so the call is recordable
# (see the wrap list below) and thus replayed on a cache hit exactly like
# any other builder call. Deliberately NOT idempotent/skip-if-already-
# sourced: several pages' callback files do real, meaningful, per-visit
# work as plain top-level code (not inside a function), e.g.
# monitor_callbacks.sh's trailing `_mon_refresh_all`, debug_callbacks.sh's
# trailing `_debug_build_grid 6`, terminal_init.sh's `tui.exec` launch -
# skipping re-source on a cache hit silently drops that per-visit setup.
# Re-sourcing (re-declaring already-identical functions) is cheap; it was
# never the expensive part tui.load_cached is caching around.
_tui_cache_source() {
	# shellcheck disable=SC1090
	source "$1"
}

# Runs a page's on_visit, if it has one. Recorded/replayed like any other
# builder call (one line: "call this function") so a cached page still gets
# fresh dynamic content on every visit - the function body itself runs live,
# never from a cache.
_tui_cache_run_on_visit() {
	# not recorded: widgets an on_visit builds are rebuilt by it on every visit, so recording them would replay stale copies
	local rec=$_TUI_CACHE_RECORDING
	_TUI_CACHE_RECORDING=0
	[[ -n "$1" ]] && "$1"
	_TUI_CACHE_RECORDING=$rec
	return 0 # no on_visit is not a load failure (tui.start treats rc != 0 as one)
}

# Defines a <button page="…"> click handler, standing in for the raw
# `eval` that used to do this directly in tui_markup.sh's button handler.
# That eval was a side effect of parsing, outside any wrapped call - on a
# cache-hit replay (which skips parsing entirely) it would never run, so
# the button's handler function would simply not exist to call. Recording
# this call, like _tui_cache_source, fixes that: replay redefines it fresh.
_tui_cache_define_goto() {
	local fn="$1" page="$2" title="${3:-}"
	title="${title#"${title%%[![:space:]]*}"}"
	title="${title%"${title##*[![:space:]]}"}"
	[[ -n "$page" ]] && _TUI_PAGES[$page]="$title" # page registry (tui.get.pages): palette / help / goto binds
	local def
	printf -v def '%s() { tui.goto %q; }' "$fn" "$page" # printf -v: no command-substitution fork per nav button
	eval "$def"
}

_tui_cache_record() {
	((_TUI_CACHE_RECORDING)) || return 0
	local fn="$1"
	shift
	local q="$fn" a
	for a in "$@"; do q+="$(printf ' %q' "$a")"; done
	_TUI_CACHE_BUF+=("$q")
}

# Renames the real implementation of $1 to _tui_cache_orig.$1, then
# redefines $1 to record itself - only at nesting depth 0, see
# _TUI_CACHE_DEPTH below - and call through. Every call site anywhere
# (tui_markup.sh's dispatch, tui.grid's own internal tui.vsplit/hsplit
# calls, on_visit's own widget calls) is covered automatically without
# touching their code.
#
# The depth guard matters for correctness, not just to avoid redundant
# recording: tui.grid calls tui.vsplit/tui.hsplit internally to build
# itself. Without the guard, recording would capture *both* the outer
# tui.grid call and its inner vsplit/hsplit calls, and replaying both would
# split the same panes twice. Recording only the outermost call in any
# nested chain mirrors exactly what tui_markup.sh's dispatch loop itself
# called - replay reproduces that, and nothing more.
_tui_cache_wrap() {
	local fn="$1" orig="_tui_cache_orig.${1}"
	if ! declare -F "$fn" >/dev/null; then
		echo "tui_cache: cannot wrap undefined function '$fn'" >&2
		return 1
	fi
	local body
	body="$(declare -f "$fn")"
	eval "${orig}${body#"$fn"}"
	eval "$fn() {
        local _tui_cache_top=0
        if (( _TUI_CACHE_DEPTH == 0 )); then
            _tui_cache_top=1
            _tui_cache_record '$fn' \"\$@\"
        fi
        (( _TUI_CACHE_DEPTH++ ))
        $orig \"\$@\"
        local _tui_cache_rc=\$?
        (( _TUI_CACHE_DEPTH-- ))
        return \$_tui_cache_rc
    }"
}

_TUI_CACHE_WRAPPED_FNS=(
	tui.load_theme
	tui.pane_align tui.pane_valign tui.pane_minsize tui.pane_maxsize
	tui.pane_scroll tui.pane_strict_fit tui.pane_title tui.pane_border tui.pane_pad tui.pad _tui_cache_relayout tui.bind
	tui.class
	tui.hsplit tui.vsplit tui.grid tui.fixed
	tui.label tui.align tui.valign tui.minsize tui.maxsize
	tui.input tui.label_align tui.label_width
	tui.password tui.textarea tui.list tui.table tui.select tui.progress tui.list.set tui.table.set tui.select.set tui.on_change tui.set
	tui.button tui.checkbox tui.input.retain tui.input.blur_on_submit tui.input.sticky tui.defaults.off tui.footer.set
	tui.tabs.compact tui.tabs.add tui.tabs.build
	_tui_cache_source _tui_cache_run_on_visit _tui_cache_define_goto
)

# tui.cache.init - wraps every builder function this module records.
# Call once, after tui_markup.sh (which defines them) is sourced and
# before the first tui.load/tui.load_cached.
tui.cache.init() {
	local fn
	for fn in "${_TUI_CACHE_WRAPPED_FNS[@]}"; do
		_tui_cache_wrap "$fn"
	done
}

# File mtime, GNU or BSD stat, 0 if the file's gone - used purely as a
# cheap "has this changed" signal, not for display.
_tui_cache_mtime() {
	stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0'
}

# tui.cache.signature FILE... - a deterministic "path=mtime;path=mtime;..."
# string covering every given file, sorted so the same file set always
# produces the same string regardless of iteration order.
tui.cache.signature() {
	local f sig=""
	for f in $(printf '%s\n' "$@" | sort); do
		sig+="${f}=$(_tui_cache_mtime "$f");"
	done
	printf '%s' "$sig"
}

# tui.cache.deps_of FILE ARRAYNAME - appends FILE, and every file its
# <include src> tags (recursively) pull in, into the array named by
# ARRAYNAME (a nameref), skipping anything already present (cycle guard).
#
# This is a deliberately separate, lightweight re-walk rather than reusing
# tui.load's own _TUI_MARKUP_SEEN (which tracks exactly this same set) -
# _markup_expand populates that array from inside `<(_markup_expand ...)`,
# a process-substitution *subshell*, so it's always empty again by the time
# tui.load returns to this (parent) shell. Running entirely in the caller's
# own shell instead, with a nameref, is what makes the result readable
# here at all.
tui.cache.deps_of() {
	local file="$1" _deps_arrname="$2"
	local -n _deps="$_deps_arrname"
	local key
	key="$(cd "$(dirname "$file")" 2>/dev/null && pwd)/$(basename "$file")" || return
	local d
	for d in "${_deps[@]}"; do [[ "$d" == "$key" ]] && return; done
	[[ -r "$key" ]] || return
	_deps+=("$key")

	local dir line src resolved
	dir="$(dirname "$key")"
	while IFS= read -r line; do
		[[ "$line" == *"<include"* ]] || continue
		src="$(_markup_attr "$line" src)"
		[[ -z "$src" ]] && continue
		resolved="$src"
		[[ "$resolved" != /* ]] && resolved="${dir}/${src}"
		tui.cache.deps_of "$resolved" "$_deps_arrname"
	done <"$key"
}

# tui.cache.record FILE - runs a real tui.load for the already-resolved
# absolute FILE path with recording on, and stores the resulting call log
# plus a signature covering FILE and every <include> it pulled in.
tui.cache.record() {
	local file="$1"
	_TUI_CACHE_BUF=()
	_TUI_CACHE_RECORDING=1
	tui.load "$file"
	_TUI_CACHE_RECORDING=0
	_TUI_CACHE_PAGE["$file"]="$(printf '%s\n' "${_TUI_CACHE_BUF[@]}")"

	local -a deps=()
	tui.cache.deps_of "$file" deps
	_TUI_CACHE_SIG["$file"]="$(tui.cache.signature "${deps[@]}")"
}

# tui.cache.valid FILE - true if FILE has a cached page AND every
# dependency file its signature covers (the page itself plus every
# <include> it pulled in at record time) still has the exact mtime it had
# then, i.e. neither the page nor anything it includes has changed since.
tui.cache.valid() {
	local file="$1"
	local sig="${_TUI_CACHE_SIG[$file]:-}"
	[[ -n "${_TUI_CACHE_PAGE[$file]:-}" && -n "$sig" ]] || return 1
	local -a parts
	IFS=';' read -ra parts <<<"$sig"
	local pair path want_mtime
	for pair in "${parts[@]}"; do
		[[ -z "$pair" ]] && continue
		path="${pair%=*}"
		want_mtime="${pair##*=}"
		[[ "$want_mtime" == "$(_tui_cache_mtime "$path")" ]] || return 1
	done
	return 0
}

# tui.cache.replay FILE - true and rebuilds the page from its cached call
# log if one exists for the already-resolved absolute FILE path, false
# otherwise. Never touches markup on a hit.
tui.cache.replay() {
	local file="$1" cmd
	[[ -n "${_TUI_CACHE_PAGE[$file]:-}" ]] || return 1
	while IFS= read -r cmd; do
		[[ -z "$cmd" ]] && continue
		eval "$cmd"
	done <<<"${_TUI_CACHE_PAGE[$file]}"
	return 0
}

# tui.load_cached FILE - drop-in replacement for tui.load: replays a cached
# page if one's available and still valid (see tui.cache.valid - a page or
# include edited since it was recorded self-heals here, not just via the
# disk-cache path), otherwise does a normal tui.load and records it fresh.
tui.load_cached() {
	local file="$1" resolved dir
	resolved="$file"
	[[ "$resolved" != /* ]] && resolved="${_TUI_MARKUP_DIR:-.}/${file}"
	_tui_path_canon "$resolved"
	resolved="$_CANON"
	dir="${resolved%/*}"
	[[ -d "$dir" ]] || {
		tui.load "$file"
		return
	}
	_TUI_MARKUP_DIR="$dir"
	_TUI_MARKUP_FILE="$resolved"

	tui.cache.valid "$resolved" && tui.cache.replay "$resolved" && return 0
	tui.cache.record "$resolved"
}

# ── cache (de)serialization - crosses the precompute worker's process
# boundary, since a background process can't share bash memory with the
# foreground one it's warming a cache for. ──────────────────────────────

# tui.cache.dump_dir DIR - writes every currently-recorded page out as one
# file set each (.key/.cache/.sig), named by a filesystem-safe encoding of
# its cache key. Also usable as a persistent on-disk cache, not just to
# cross the precompute worker's process boundary - see tui.cache.disk_dir.
tui.cache.dump_dir() {
	local dir="$1" key fname
	mkdir -p "$dir"
	for key in "${!_TUI_CACHE_PAGE[@]}"; do
		fname="${key//\//_}"
		printf '%s' "$key" >"$dir/${fname}.key"
		printf '%s' "${_TUI_CACHE_PAGE[$key]}" >"$dir/${fname}.cache"
		printf '%s' "${_TUI_CACHE_SIG[$key]:-}" >"$dir/${fname}.sig"
	done
}

# tui.cache.load_dir DIR - reads cache files written by tui.cache.dump_dir
# into this process's own _TUI_CACHE_PAGE, dropping (not just leaving
# stale) any entry that fails tui.cache.valid against the current
# filesystem - callers can assume everything left in _TUI_CACHE_PAGE after
# this call is actually usable, no separate check needed.
tui.cache.load_dir() {
	local dir="$1" f key
	[[ -d "$dir" ]] || return 0
	for f in "$dir"/*.key; do
		[[ -e "$f" ]] || continue
		key="$(<"$f")"
		_TUI_CACHE_PAGE["$key"]="$(<"${f%.key}.cache")"
		_TUI_CACHE_SIG["$key"]="$([[ -f "${f%.key}.sig" ]] && cat "${f%.key}.sig")"
		tui.cache.valid "$key" || { unset '_TUI_CACHE_PAGE[$key]' '_TUI_CACHE_SIG[$key]'; }
	done
}

# tui.cache.disk_dir - the persistent, cross-run on-disk cache location:
# $TUI_HOME/cache/pages/ (in the DABT config home, not in the program folder).
tui.cache.disk_dir() {
	printf '%s' "$TUI_HOME/cache/pages"
}

_tui_cache_now_us() { printf '%s' "${EPOCHREALTIME//[^0-9]/}"; }

# tui.cache.warm_with_spinner PAGE... - pre-warms the cache for every given
# page, showing a D.A.B.T banner + progress bar while it works. Same shape
# as tools/legacy/bench_page_switch.sh's worker (proven there): an isolated
# background subshell does the real work - stdin -> /dev/null so its own
# tui.init can't put the *real* terminal in raw mode, stdout -> /dev/null
# so its screen paints never hit it either - and reports one line per page
# down a fifo the foreground reads with a timeout, so it never blocks and
# Ctrl-C always reaches it. A background bash subshell can't share memory
# with this process, so the worker dumps its cache to disk and this
# function loads it back in once the worker signals done.
tui.cache.warm_with_spinner() {
	local -a _tcw_pages=("$@")
	((${#_tcw_pages[@]} > 0)) || return 0

	local _tcw_root _tcw_cache_dir _tcw_fifo
	_tcw_root="$(mktemp -d "${TMPDIR:-/tmp}/tui_cache_warm.XXXXXX")" || return 1
	_tcw_cache_dir="$_tcw_root/cache"
	_tcw_fifo="$_tcw_root/progress.fifo"
	mkdir -p "$_tcw_cache_dir"
	mkfifo "$_tcw_fifo"

	_tui_cache_warm_worker() {
		exec </dev/null
		exec 6>"$_tcw_fifo"
		exec 3>&1 1>/dev/null 2>"$_tcw_root/worker.stderr.log"

		tui.init

		local _tcw_page _tcw_total=${#_tcw_pages[@]} _tcw_n=0
		for _tcw_page in "${_tcw_pages[@]}"; do
			tui.reset_ui
			tui.cache.record "$_tcw_page"
			((_tcw_n++))
			printf 'PROGRESS %d %d %s\n' "$_tcw_n" "$_tcw_total" "$(basename "$_tcw_page")" >&6
		done

		tui.cache.dump_dir "$_tcw_cache_dir"
		exec 1>&3 3>&-
		printf 'DONE\n' >&6
		exec 6>&-
		_master_cleanup 2>/dev/null
	}

	exec 5<>"$_tcw_fifo"
	_tui_cache_warm_worker &
	local _tcw_worker_pid=$!

	# Not part of tui.sh's normal load chain (it's meant to be usable
	# standalone) - sourced here just for the block5 font.
	# shellcheck disable=SC1091
	source "${SCRIPT_DIR}/terminal_renderer.sh"

	cur.hide
	erase.all

	# Center the whole block (banner + 2-row gap + bar + note) as one unit
	# on the current screen.
	local _tcw_term_rows _tcw_term_cols
	term.size _tcw_term_rows _tcw_term_cols

	# The logo: D A B T in block5 glyphs, colored per letter with the pastels of assets/logo.svg. The colors rotate
	# through the letters every _tcw_cycle_us while caching runs. Each frame is one absolute-positioned write
	# (cursor addressing, wrapped in a synchronized-update block) - the screen is never cleared, so nothing flickers.
	_banner_font_init
	local -a _tcw_glyphs=() _tcw_rgb=("255;140;191" "168;216;255" "255;243;168" "255;158;158") _tcw_256=(212 153 229 217) _tcw_pal=()
	local _tcw_ch _tcw_gr _tcw_r _tcw_i _tcw_banner_w=$((4 + 4 + 4 + 5 + 3)) _tcw_banner_h=5 _tcw_offset=0 _tcw_cycle_us=400000
	for _tcw_ch in D A B T; do
		IFS='|' read -ra _tcw_gr <<<"${_BANNER_FONT[$_tcw_ch]}"
		_tcw_glyphs+=("${_tcw_gr[@]:0:5}")
	done
	for _tcw_i in 0 1 2 3; do
		if [[ "${COLORTERM:-}" == *truecolor* || "${COLORTERM:-}" == *24bit* ]]; then
			_tcw_pal+=($'\e[38;2;'"${_tcw_rgb[_tcw_i]}m")
		else _tcw_pal+=($'\e[38;5;'"${_tcw_256[_tcw_i]}m"); fi
	done
	_tcw_paint() { # ROW0 COL0 : draws the logo with the current _tcw_offset
		local out=$'\e[?2026h' r i rst=$'\e[0m'
		for ((r = 0; r < 5; r++)); do
			out+=$'\e['"$(($1 + r));$2H"
			for ((i = 0; i < 4; i++)); do
				((i > 0)) && out+=" "
				out+="${_tcw_pal[(i + 4 - _tcw_offset) % 4]}${_tcw_glyphs[i * 5 + r]}${rst}"
			done
		done
		printf '%s\e[?2026l' "$out"
	}

	local _tcw_block_h=$((_tcw_banner_h + 2 + 1 + 1)) # banner + gap + bar row + note row
	local _tcw_row0=$(((_tcw_term_rows - _tcw_block_h) / 2))
	((_tcw_row0 < 1)) && _tcw_row0=1
	local _tcw_col0=$(((_tcw_term_cols - _tcw_banner_w) / 2))
	((_tcw_col0 < 1)) && _tcw_col0=1

	_tcw_paint "$_tcw_row0" "$_tcw_col0"

	local _tcw_bar_row=$((_tcw_row0 + _tcw_banner_h + 2))
	local _tcw_note_row=$((_tcw_bar_row + 1))
	printat "$_tcw_note_row" "$((_tcw_col0 - 6))" "${DIM_WHITE}Startup will be faster in the future${RESET}"

	local _tcw_start_us _tcw_last_progress_us _tcw_now
	local _tcw_current=0 _tcw_done=0 _tcw_line2
	_tcw_start_us=$(_tui_cache_now_us)
	_tcw_last_progress_us=$_tcw_start_us
	local _tcw_last_cycle_us=$_tcw_start_us

	local _tcw_bar_width=30
	local _tcw_last_pct=-1
	while ((! _tcw_done)); do
		if IFS= read -r -t 0.2 -u 5 _tcw_line2; then
			case "$_tcw_line2" in
				"PROGRESS "*)
					read -r _ _tcw_current _ _ <<<"$_tcw_line2"
					_tcw_last_progress_us=$(_tui_cache_now_us)
					;;
				"DONE") _tcw_done=1 ;;
			esac
		fi
		if ((! _tcw_done)) && ! kill -0 "$_tcw_worker_pid" 2>/dev/null; then
			_tcw_done=1
		fi
		((_tcw_done)) && break
		_tcw_now=$(_tui_cache_now_us)
		if ((_tcw_now - _tcw_last_cycle_us >= _tcw_cycle_us)); then
			_tcw_last_cycle_us=$_tcw_now
			_tcw_offset=$(((_tcw_offset + 1) % 4))
			_tcw_paint "$_tcw_row0" "$_tcw_col0"
		fi

		local _tcw_pct=0
		((${#_tcw_pages[@]} > 0)) && _tcw_pct=$((100 * _tcw_current / ${#_tcw_pages[@]}))
		((_tcw_pct > 100)) && _tcw_pct=100
		local _tcw_filled=$((_tcw_pct * _tcw_bar_width / 100))
		if ((_tcw_pct != _tcw_last_pct)); then # the bar only changes with progress: repaint in place, one write
			_tcw_last_pct=$_tcw_pct
			local _tcw_bar="" _tcw_c
			for ((_tcw_c = 0; _tcw_c < _tcw_bar_width; _tcw_c++)); do
				if ((_tcw_c < _tcw_filled)); then
					_tcw_bar+="${_tcw_pal[_tcw_c * 4 / _tcw_bar_width]}█" # pink -> blue -> yellow -> red along the bar
				else _tcw_bar+=$'\e[38;5;238m░'; fi
			done
			printf '\e[%d;%dH\e[38;5;250mcaching sites \e[38;5;245m▕%s\e[38;5;245m▏ \e[38;5;250m%3d%%\e[0m' \
				"$_tcw_bar_row" "$((_tcw_col0 - _tcw_bar_width / 2 + 2))" "$_tcw_bar" "$_tcw_pct"
		fi
	done

	wait "$_tcw_worker_pid" 2>/dev/null
	{ exec 5>&-; } 2>/dev/null

	tui.cache.load_dir "$_tcw_cache_dir"
	rm -rf "$_tcw_root" 2>/dev/null
	erase.all
	cur.show
}

# tui.start_cached FIRST_PAGE - like tui.start, but first pre-warms the
# cache for every config/*.xml sibling of FIRST_PAGE (every page a nav bar
# in the same directory would ever link to), plus the shipped default pages
# (share/defaults/pages/ - Settings, Keybinds, Plugins - reachable from any
# app through the command palette, tui.action.goto_default) behind a
# D.A.B.T spinner, then serves FIRST_PAGE - and every later tui.goto to one
# of those siblings or defaults - from that warm cache.
tui.start_cached() {
	local file="$1"
	[[ -r "$file" ]] || {
		echo "tui.start_cached: cannot read '$file'" >&2
		return 1
	}

	local dir
	dir="$(cd "$(dirname "$file")" && pwd)"
	_TUI_APP_DIR="$dir"
	[[ -z "${TUI_THEMES_DIR:-}" && -d "$dir/themes" ]] && TUI_THEMES_DIR="$dir/themes"
	[[ -z "${TUI_THEMES_DIR:-}" && -d "$TUI_DEFAULTS_DIR/themes" ]] && TUI_THEMES_DIR="$TUI_DEFAULTS_DIR/themes"
	local -a pages=()
	while IFS= read -r f; do
		[[ "$(basename "$f")" == _* ]] && continue
		pages+=("$f")
	done < <(find "$dir" -maxdepth 1 -name '*.xml' | sort)
	while IFS= read -r f; do
		[[ "$(basename "$f")" == _* ]] && continue
		pages+=("$f")
	done < <(find "$TUI_DEFAULTS_DIR/pages" -maxdepth 1 -name '*.xml' 2>/dev/null | sort)

	# Load whatever's already on disk from a previous run - load_dir
	# itself drops anything whose page (or an include it pulled in) has
	# since changed, so only genuinely-still-valid entries survive.
	local disk_dir
	disk_dir="$(tui.cache.disk_dir)"
	tui.cache.load_dir "$disk_dir"

	# Warm only what's actually missing or stale, not every page every
	# launch - the whole point of persisting the cache.
	local -a stale=() p
	for p in "${pages[@]}"; do
		tui.cache.valid "$p" || stale+=("$p")
	done
	if ((${#stale[@]} > 0)); then
		tui.cache.warm_with_spinner "${stale[@]}"
		tui.cache.dump_dir "$disk_dir"
	fi

	tui.init
	if ! tui.load_cached "$file"; then
		_master_cleanup
		return 1
	fi
	tui.run
}
