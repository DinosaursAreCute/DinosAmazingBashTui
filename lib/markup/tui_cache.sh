#!/usr/bin/env bash
# tui_cache.sh - page-load caching.
#
# tui_markup.sh's tui.load spends most of its time tokenizing a page's XML
# and dispatching every tag to a builder call (tui.hsplit, tui.label, ...),
# even though the resulting engine state is identical every time for a
# page's *static* structure. This records that state once, as a `declare -p`
# snapshot of every pane/widget array tui.reset_ui clears, and restores it
# later with one `source`-style eval - no re-tokenizing, no per-tag dispatch,
# no per-call eval replay (markup-v2 stage 1.3: replaces the old wrapped-
# builder-function call log with this).
#
# Dynamic content stays dynamic: a page's <script src> sourcing, its
# <button page="…"> nav handlers and its on_visit handler are themselves
# recorded as small, individually-replayed calls (see _tui_cache_source /
# _tui_cache_define_goto / _tui_cache_run_on_visit below), so replaying a
# cached page still re-sources what it needs, re-defines nav buttons and
# always reruns on_visit fresh - only the static pane/widget build itself is
# skipped on a cache hit.
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
# cheap; only the markup parse+build is what's actually worth caching.

declare -gA _TUI_CACHE_PAGE=()     # resolved page path -> declare -p snapshot of its built engine state
declare -gA _TUI_CACHE_SIG=()      # resolved page path -> "dep=mtime dep=mtime ..." signature
declare -gA _TUI_CACHE_SCRIPTS=()  # resolved page path -> space-joined <script src> paths, re-sourced on every replay
declare -gA _TUI_CACHE_ON_VISIT=() # resolved page path -> on_visit function name, rerun on every replay
declare -gA _TUI_CACHE_GOTOS=()    # resolved page path -> newline-joined "_tui_cache_define_goto ..." calls
declare -gA _TUI_CACHE_THEME=()    # resolved page path -> its <theme src> file, reloaded on every replay
declare -gA _TUI_CACHE_CLASSES=()  # resolved page path -> newline-joined "id\tclass" pairs, re-applied on every replay
# Theme overlay the page's baked _TUI_STYLE_* were built under. The _TUI_STYLE_ prefix puts it in the page
# snapshot (see _TUI_CACHE_STATE_REGEX), so a replay reads back the record-time value: equal to the current
# overlay means the restored styles are already current and the per-widget tui.class re-bake can be skipped.
declare -g _TUI_STYLE_SIG=""

# Populated by _tui_cache_source/_tui_cache_define_goto/_tui_cache_theme/
# _tui_cache_class below while tui.cache.record's tui.load runs, then
# captured into the maps above - scratch, not meant to be read outside that
# one call.
declare -ga _TUI_CACHE_REC_SCRIPTS=()
declare -ga _TUI_CACHE_REC_GOTOS=()
declare -g _TUI_CACHE_REC_THEME=""
declare -ga _TUI_CACHE_REC_CLASSES=()

# Node names a fresh page's build actually touches (exactly tui.reset_ui's
# own reset list, plus lib/widgets/tui_widgets.sh's _tui_wx.reset list) -
# what tui.cache.record snapshots and tui.cache.replay restores. A prefix
# match (compgen, fork-free... `<()` itself forks once per record, same as
# every other one-shot build-time cost this stage already pays) so a new
# widget's own `_TUI_W_*`/`_WX*`/`_TX*` array is covered automatically.
declare -g _TUI_CACHE_STATE_REGEX='^(_TUI_P_|_TUI_W_|_TUI_PANE_CONTENT$|_TUI_PANE_FOCUS$|_TUI_PANE_LAST_WIDGET$|_TUI_FACTORY_|_TUI_TABS_|_TUI_TAB_|_TUI_FOCUSABLE$|_TUI_FOCUS_ID$|_TUI_FOCUS_IDX$|_TUI_CURSOR$|_TUI_HOVERED_|_TUI_PENDING_OUTPUT$|_TUI_RENDER_TIMEOUT$|_TUI_TICK_FN$|_TUI_ON_RESIZE_FN$|_TUI_ON_INPUT_EVENT$|_TUI_ON_KEY_EVENT$|_TUI_STYLE_|_TUI_FOOTER_|_WX|_TX)'

# _tui_cache_snapshot -> stdout : a `declare -p` dump of every currently
# live variable tui.reset_ui/_tui_wx.reset would clear - the built page's
# whole engine-visible state, replayable with one eval.
_tui_cache_snapshot() {
	local -a names=()
	# grep -E in one batch over compgen's whole list, not a bash [[ =~ ]]
	# loop per variable - bash has hundreds to thousands of variables in
	# scope (env, framework globals, ...); looping that many regex matches
	# in-shell measured slower than the one extra fork this pipe costs.
	while IFS= read -r v; do names+=("$v"); done < <(compgen -A variable | grep -E "$_TUI_CACHE_STATE_REGEX")
	((${#names[@]} > 0)) && declare -p "${names[@]}"
}

# _tui_cache_restore DUMP - restores a _tui_cache_snapshot dump. Run inside
# a function: declare -p's own output has no -g, so every "declare -X"
# becomes "declare -gX" before eval to land at global scope (same fix as
# tui_node.sh's load, stage 0.5) - line by line, since a plain scalar's
# "declare -- NAME=…" would otherwise collide with a blind `declare -`
# string replace (it turns "-- " into "-g- ", an invalid option).
_tui_cache_restore() {
	local dump="$1" out="" line
	# fd 8, not stdin: this loop's body is self-contained today (no nested
	# tui.goto/term.size), but every stdin-bound while-read in this file
	# keeps fd 0 free for the tty on principle - see tui.cache.replay's own
	# fd-9 goto/on_visit loop, the historical bug that pattern fixed.
	while IFS= read -r -u 8 line; do
		if [[ "$line" == "declare --"* ]]; then
			line="declare -g${line#declare --}"
		elif [[ "$line" == "declare -"* ]]; then
			line="declare -g${line#declare -}"
		fi
		out+="$line"$'\n'
	done 8<<<"$dump"
	eval "$out"
}

# ── stylesheet memoization ──────────────────────────────────────────────
# The page cache above replays a page's recorded `tui.load_theme FILE` call on every visit, and
# tui_style.sh's parse of that file used to run again each time (~250 ms for theme.css, doubled
# with a theme overlay). This REDEFINES tui_style.sh's _tui.theme_load_file so each stylesheet is
# parsed ONCE per process, then re-applied from memory (a handful of array assignments, no file
# read, no forks).
#
# Freshness is fork-free too: after a parse we `: > STAMP` (a builtin redirect = touch), and a file
# is stale when it is newer than its stamp (`[[ FILE -nt STAMP ]]` - no stat, no subshell). While the cache is not
# yet trusted (see _TUI_CACHE_TRUSTED), editing theme.css takes effect on the next page visit, like the page cache.
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
	if [[ -n "${_TUI_THEME_MEMO[$file]+x}" ]] && { ((_TUI_CACHE_TRUSTED)) || [[ ! "$file" -nt "${_TUI_THEME_STAMP[$file]}" ]]; }; then
		tui.log.debug "_tui.theme_load_file: memo HIT for $file, re-applying from memory"
		# fd 7, not stdin: tui.load_theme runs mid-build (from a <theme> tag
		# handler); keep fd 0 free for the tty the same way tui.cache.replay's
		# fd-9 goto/on_visit loop does.
		while IFS=$'\x1f' read -r -u 7 cls fg bg mods; do # hit: re-apply, nothing is parsed
			[[ -z "$cls" ]] && continue
			[[ -n "$fg" ]] && _TUI_CLASS_FG[$cls]="$fg"
			[[ -n "$bg" ]] && _TUI_CLASS_BG[$cls]="$bg"
			[[ -n "$mods" ]] && _TUI_CLASS_MOD[$cls]="$mods"
		done 7<<<"${_TUI_THEME_MEMO[$file]}"
		return 0
	fi

	tui.log.debug "_tui.theme_load_file: memo MISS for $file, parsing from disk"
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

# Stands in for a raw `source` on <script src>. Deliberately NOT idempotent/
# skip-if-already-sourced: several pages' callback files do real, meaningful,
# per-visit work as plain top-level code (not inside a function), e.g.
# monitor_callbacks.sh's trailing `_mon_refresh_all`, debug_callbacks.sh's
# trailing `_debug_build_grid 6`, terminal_init.sh's `tui.exec` launch -
# skipping re-source on a cache hit silently drops that per-visit setup.
# Re-sourcing (re-declaring already-identical functions) is cheap; it was
# never the expensive part tui.load_cached is caching around. Every call is
# remembered in _TUI_CACHE_REC_SCRIPTS so tui.cache.record can capture which
# scripts a page's build sourced, to re-source them on every future replay.
_tui_cache_source() {
	_TUI_CACHE_REC_SCRIPTS+=("$1")
	# shellcheck disable=SC1090
	source "$1"
}

# Stands in for tui_build.sh's <theme src> handler's tui.load_theme call.
# Recording just the resolved file isn't enough to skip on a cache hit: the
# app-wide overlay (tui.theme.set/tui.theme.pick, _TUI_THEME_OVERLAY in
# tui_style.sh) is re-applied on top of it INSIDE tui.load_theme, live, every
# time it runs - a page built once under one overlay would otherwise stay
# frozen on it forever, since tui.cache.replay skips the whole build (and
# thus this call) on every later hit. Re-running it on replay costs nothing:
# _tui.theme_load_file below memoizes the parse per file+mtime, so this is a
# handful of array re-assignments, not a re-parse.
_tui_cache_theme() {
	_TUI_CACHE_REC_THEME="$1"
	tui.log.debug "_tui_cache_theme: recording <theme src>=$1 for replay"
	tui.load_theme "$1"
}

# Stands in for every build-time "tui.class ID CLASS" call (tui_build.sh's
# pane/widget/button/label/key tag handlers, tui_widgets.sh's own). tui.class
# resolves CLASS against the (by-then current) _TUI_CLASS_* table and bakes
# the result into _TUI_STYLE_*[ID_state] - the table tui.sh's draw code
# actually reads. _TUI_STYLE_* matches _TUI_CACHE_STATE_REGEX, so it's part
# of the page snapshot: a cache HIT restores it as it was at record time and
# never calls tui.class again, so a theme switch that only refreshes
# _TUI_CLASS_* (see _tui_cache_theme above) never reaches an already-cached
# page's actual widget colors. Recording every (id, class) pair here lets
# tui.cache.replay re-run tui.class for each one after the theme reload, the
# same "dynamic bits replay individually" pattern as scripts/gotos/on_visit.
_tui_cache_class() {
	local id="$1" cls="$2"
	[[ -n "$cls" ]] && _TUI_CACHE_REC_CLASSES+=("$id"$'\t'"$cls")
	tui.class "$id" "$cls"
}

# Runs a page's on_visit, if it has one - the function body itself runs
# live, never from a cache, on both a cache miss (tui.cache.record) and a
# cache hit (tui.cache.replay).
_tui_cache_run_on_visit() {
	[[ -n "$1" ]] && "$1"
	return 0 # no on_visit is not a load failure (tui.start treats rc != 0 as one)
}

# Defines a <button page="…"> click handler. On a cache MISS this also runs
# during the real tui.load that tui.cache.record wraps; every call is
# remembered in _TUI_CACHE_REC_GOTOS (as a ready-to-eval call, see
# tui.cache.record) so a future cache HIT - which skips the build entirely -
# still re-defines every nav button's handler fresh, the same as
# _tui_cache_source's scripts and on_visit above.
_tui_cache_define_goto() {
	local fn="$1" page="$2" title="${3:-}"
	title="${title#"${title%%[![:space:]]*}"}"
	title="${title%"${title##*[![:space:]]}"}"
	[[ -n "$page" ]] && _TUI_PAGES[$page]="$title" # page registry (tui.get.pages): palette / help / goto binds
	local def
	printf -v def '%s() { tui.goto %q; }' "$fn" "$page" # printf -v: no command-substitution fork per nav button
	eval "$def"
	local rec
	printf -v rec '_tui_cache_define_goto %q %q %q' "$fn" "$page" "$title"
	_TUI_CACHE_REC_GOTOS+=("$rec")
}

# _tui_cache_dir FILE -> _CANON: FILE's absolute directory (no fork: was `$(cd "$(dirname FILE)" && pwd)`); rc 1 if it is missing
_tui_cache_dir() {
	local d=.
	[[ "$1" == */* ]] && d="${1%/*}"
	[[ -n "$d" ]] || d=/
	[[ -d "$d" ]] || return 1
	_tui_path_canon "$d"
}

# File mtime, GNU or BSD stat, 0 if the file's gone - used purely as a
# cheap "has this changed" signal, not for display.
_tui_cache_mtime() {
	stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0'
}

# _tui_cache_slurp FILE - _SLURP = FILE's contents without trailing newlines (what "$(<FILE)" or "$(cat FILE)"
# gives), empty if FILE is missing. A builtin read: the command substitutions it replaces were 8 forks per cached page.
declare -g _SLURP=""
_tui_cache_slurp() {
	_SLURP=""
	[[ -f "$1" ]] || return 0
	IFS= read -r -d '' _SLURP <"$1" || true
	while [[ "$_SLURP" == *$'\n' ]]; do _SLURP="${_SLURP%$'\n'}"; done
}

# _tui_cache_stat_many PATH... - mtimes of all PATHs in ONE stat call, into _TUI_CACHE_MTIME[path] (0 = gone).
# One fork for any number of files: a page check used to fork once per dependency, a start-up ~120 times.
declare -gA _TUI_CACHE_MTIME=()
# 1 while _TUI_CACHE_MTIME holds a just-taken snapshot that tui.cache.valid may trust instead of stat-ing again:
# set by tui.cache.load_dir, cleared by tui.cache.start_cached once its start-up check is done.
declare -g _TUI_CACHE_MTIME_FRESH=0
_tui_cache_stat_many() {
	(($#)) || return 0
	local out line path
	out="$(stat -c '%Y %n' -- "$@" 2>/dev/null)" || true
	[[ -n "$out" ]] || out="$(stat -f '%m %N' -- "$@" 2>/dev/null)" || true
	for path in "$@"; do _TUI_CACHE_MTIME[$path]=0; done
	while IFS= read -r line; do
		[[ -n "$line" ]] && _TUI_CACHE_MTIME[${line#* }]="${line%% *}"
	done <<<"$out"
}

# tui.cache.signature FILE... - a deterministic "path=mtime;path=mtime;..."
# string covering every given file, sorted so the same file set always
# produces the same string regardless of iteration order.
tui.cache.signature() {
	local f sig="" i j t
	local -a sorted=("$@")
	_tui_cache_stat_many "$@"
	# insertion sort in bash: a handful of paths, and `printf | sort` was two forks per page
	for ((i = 1; i < ${#sorted[@]}; i++)); do
		t="${sorted[i]}"
		for ((j = i - 1; j >= 0; j--)); do
			[[ "${sorted[j]}" > "$t" ]] || break
			sorted[j + 1]="${sorted[j]}"
		done
		sorted[j + 1]="$t"
	done
	for f in "${sorted[@]}"; do
		sig+="${f}=${_TUI_CACHE_MTIME[$f]:-0};"
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
	_tui_cache_dir "$file" || return
	key="${_CANON%/}/${file##*/}"
	local d
	for d in "${_deps[@]}"; do [[ "$d" == "$key" ]] && return; done
	[[ -r "$key" ]] || return
	_deps+=("$key")

	local dir line src resolved
	dir="${key%/*}"
	dir="${dir:-/}"
	# fd 8, not stdin: the loop body recurses into tui.cache.deps_of, which
	# can be reached from the same cache/build chain a <script>'s top-level
	# code runs in - keep fd 0 free for the tty like every other stdin-bound
	# while-read in this file.
	while IFS= read -r -u 8 line; do
		[[ "$line" == *"<include"* ]] || continue
		src="$(_markup_attr "$line" src)"
		[[ -z "$src" ]] && continue
		resolved="$src"
		[[ "$resolved" != /* ]] && resolved="${dir}/${src}"
		tui.cache.deps_of "$resolved" "$_deps_arrname"
	done 8<"$key"
}

# tui.cache.record FILE - runs a real tui.load for the already-resolved
# absolute FILE path, then stores a snapshot of the engine state it built
# (see _tui_cache_snapshot), the scripts it sourced, its on_visit function
# and its nav-button definitions (all three replayed fresh on every future
# hit, see tui.cache.replay), plus a signature covering FILE and every
# <include> it pulled in.
tui.cache.record() {
	local file="$1" _rec_join
	tui.log.debug "tui.cache.record: building $file fresh (cache miss)"
	_TUI_CACHE_REC_SCRIPTS=()
	_TUI_CACHE_REC_GOTOS=()
	_TUI_CACHE_REC_THEME=""
	_TUI_CACHE_REC_CLASSES=()
	tui.load "$file" || return 1 # a worker (1.4) checks this: no snapshot, page falls back to an uncached load
	_TUI_STYLE_SIG="${_TUI_THEME_OVERLAY:-}"
	_TUI_CACHE_PAGE["$file"]="$(_tui_cache_snapshot)"
	_TUI_CACHE_SCRIPTS["$file"]="${_TUI_CACHE_REC_SCRIPTS[*]}"
	_TUI_CACHE_ON_VISIT["$file"]="${_TUI_BUILD_ON_VISIT:-}"
	printf -v _rec_join '%s\n' "${_TUI_CACHE_REC_GOTOS[@]}"
	while [[ "$_rec_join" == *$'\n' ]]; do _rec_join="${_rec_join%$'\n'}"; done # what "$(printf ...)" gave
	_TUI_CACHE_GOTOS["$file"]="$_rec_join"
	_TUI_CACHE_THEME["$file"]="$_TUI_CACHE_REC_THEME"
	printf -v _rec_join '%s\n' "${_TUI_CACHE_REC_CLASSES[@]}"
	while [[ "$_rec_join" == *$'\n' ]]; do _rec_join="${_rec_join%$'\n'}"; done
	_TUI_CACHE_CLASSES["$file"]="$_rec_join"
	tui.log.debug "tui.cache.record: recorded theme=${_TUI_CACHE_REC_THEME:-<none>} classes=${#_TUI_CACHE_REC_CLASSES[@]} for $file"

	local -a deps=()
	tui.cache.deps_of "$file" deps
	_TUI_CACHE_SIG["$file"]="$(tui.cache.signature "${deps[@]}")"
}

# 1 once tui.start_cached has validated and warmed every page: source files are then assumed not to change while the
# app runs, so tui.cache.valid and the theme memo stop checking mtimes (one stat call per page switch gone). Edits made
# while the app runs take effect on the next start. TUI_CACHE_TRUST=0 keeps the live checks (developing a page).
declare -gi _TUI_CACHE_TRUSTED=0
declare -gi TUI_CACHE_TRUST="${TUI_CACHE_TRUST:-1}"

# tui.cache.valid FILE - true if FILE has a cached page AND every
# dependency file its signature covers (the page itself plus every
# <include> it pulled in at record time) still has the exact mtime it had
# then, i.e. neither the page nor anything it includes has changed since.
# Once the cache is trusted (_TUI_CACHE_TRUSTED) a recorded page is simply valid: no stat.
tui.cache.valid() {
	local file="$1"
	local sig="${_TUI_CACHE_SIG[$file]:-}"
	[[ -n "${_TUI_CACHE_PAGE[$file]:-}" && -n "$sig" ]] || return 1
	((_TUI_CACHE_TRUSTED)) && return 0
	local -a parts paths=() wants=()
	IFS=';' read -ra parts <<<"$sig"
	local pair i
	for pair in "${parts[@]}"; do
		[[ -z "$pair" ]] && continue
		paths+=("${pair%=*}")
		wants+=("${pair##*=}")
	done
	((${#paths[@]})) || return 0
	# one stat for every dependency (none at all while a fresh prefetch covers them)
	if ((_TUI_CACHE_MTIME_FRESH)); then
		for i in "${!paths[@]}"; do
			[[ -n "${_TUI_CACHE_MTIME[${paths[i]}]+x}" ]] || {
				_tui_cache_stat_many "${paths[@]}"
				break
			}
		done
	else
		_tui_cache_stat_many "${paths[@]}"
	fi
	for i in "${!paths[@]}"; do
		[[ "${wants[i]}" == "${_TUI_CACHE_MTIME[${paths[i]}]:-0}" ]] || return 1
	done
	return 0
}

# tui.cache.replay FILE - true and restores the page from its cached
# snapshot if one exists for the already-resolved absolute FILE path, false
# otherwise. No markup parse, no tag dispatch on a hit - one eval restores
# every pane/widget array, then scripts, nav buttons and on_visit rerun
# fresh (see tui.cache.record's doc comment for why those three stay live).
tui.cache.replay() {
	local file="$1" rec
	[[ -n "${_TUI_CACHE_PAGE[$file]:-}" ]] || return 1
	tui.log.debug "tui.cache.replay: replaying $file from snapshot (cache hit)"
	_TUI_STYLE_SIG="?" # a snapshot recorded before the signature existed leaves it at "?": never equal, so it re-bakes
	_tui_cache_restore "${_TUI_CACHE_PAGE[$file]}"
	# Re-applies the page's <theme> plus whatever app-wide overlay is
	# currently set (tui.load_theme itself layers _TUI_THEME_OVERLAY on top,
	# see tui_style.sh) - skipped by the restore above since the whole build
	# is skipped on a hit; see _tui_cache_theme's comment for why this must
	# run on every replay, not just at record time.
	#
	if [[ -n "${_TUI_CACHE_THEME[$file]:-}" ]]; then
		tui.log.debug "tui.cache.replay: re-applying theme ${_TUI_CACHE_THEME[$file]} for $file"
		tui.load_theme "${_TUI_CACHE_THEME[$file]}"
	else
		tui.log.debug "tui.cache.replay: no recorded theme for $file, nothing to re-apply"
	fi
	# Re-bakes every widget/pane's _TUI_STYLE_* entry from the now-current
	# _TUI_CLASS_* table (see _tui_cache_class's comment) - the theme reload
	# above only refreshes the class table itself; without this, a switched
	# theme never reaches an already-cached page's actual rendered colors.
	# Skipped when the snapshot was baked under the overlay that is active now: the restored _TUI_STYLE_*
	# already are what this loop would produce (an overlay file edited in place is not noticed until the
	# page is recorded again).
	if [[ "$_TUI_STYLE_SIG" != "${_TUI_THEME_OVERLAY:-}" ]]; then
		local _rc_id _rc_cls
		# fd 6, not stdin: kept free for the tty on the same principle as this
		# file's other stdin-bound while-read loops (fd 7/8/9 above).
		while IFS=$'\t' read -r -u 6 _rc_id _rc_cls; do
			[[ -z "$_rc_id" ]] && continue
			tui.class "$_rc_id" "$_rc_cls"
		done 6<<<"${_TUI_CACHE_CLASSES[$file]:-}"
	fi
	# _TUI_OVERLAY_FNS (lib/chrome/tui_modal.sh) isn't page state, so it isn't in the
	# snapshot: tui.reset_ui's _tui_footer.reset always removes _tui_footer.draw from it,
	# and restoring _TUI_FOOTER_ON=1 alone wouldn't re-add it without this.
	((_TUI_FOOTER_ON)) && tui.overlay.add _tui_footer.draw
	local s
	for s in ${_TUI_CACHE_SCRIPTS[$file]:-}; do _tui_cache_source "$s"; done
	# the goto/on_visit calls come in on fd 9, not stdin: they must see the terminal on stdin - with them on
	# stdin, `stty size` failed and a tui.goto from on_visit laid out at 80x24
	while IFS= read -r -u 9 rec; do
		[[ -z "$rec" ]] && continue
		eval "$rec"
	done 9<<<"${_TUI_CACHE_GOTOS[$file]:-}"
	_tui_cache_relayout
	_tui_cache_run_on_visit "${_TUI_CACHE_ON_VISIT[$file]:-}"
	return 0
}

# tui.load_cached FILE - drop-in replacement for tui.load: replays a cached
# page if one's available and still valid (see tui.cache.valid: checked against the files' mtimes until the cache is
# trusted at the end of start-up, assumed valid afterwards), otherwise does a normal tui.load and records it fresh.
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

	local _lc_valid=no
	tui.cache.valid "$resolved" && _lc_valid=yes
	tui.log.debug "tui.load_cached: $resolved valid=$_lc_valid overlay=${_TUI_THEME_OVERLAY:-<none>}"
	if [[ "$_lc_valid" == yes ]] && tui.cache.replay "$resolved"; then
		_tui_perf.count cache_hit
		return 0
	fi
	_tui_perf.count cache_miss
	tui.cache.record "$resolved"
}

# ── cache (de)serialization - crosses the precompute worker's process
# boundary, since a background process can't share bash memory with the
# foreground one it's warming a cache for. ──────────────────────────────

# tui.cache.dump_dir DIR - writes every currently-recorded page out as one
# file set each (.key/.cache/.sig/.scripts/.onvisit/.gotos), named by a
# filesystem-safe encoding of its cache key. Also usable as a persistent
# on-disk cache, not just to cross the precompute worker's process boundary
# - see tui.cache.disk_dir.
tui.cache.dump_dir() {
	local dir="$1" key fname
	mkdir -p "$dir"
	for key in "${!_TUI_CACHE_PAGE[@]}"; do
		fname="${key//\//_}"
		printf '%s' "$key" >"$dir/${fname}.key"
		printf '%s' "${_TUI_CACHE_PAGE[$key]}" >"$dir/${fname}.cache"
		printf '%s' "${_TUI_CACHE_SIG[$key]:-}" >"$dir/${fname}.sig"
		printf '%s' "${_TUI_CACHE_SCRIPTS[$key]:-}" >"$dir/${fname}.scripts"
		printf '%s' "${_TUI_CACHE_ON_VISIT[$key]:-}" >"$dir/${fname}.onvisit"
		printf '%s' "${_TUI_CACHE_GOTOS[$key]:-}" >"$dir/${fname}.gotos"
		printf '%s' "${_TUI_CACHE_THEME[$key]:-}" >"$dir/${fname}.theme"
		printf '%s' "${_TUI_CACHE_CLASSES[$key]:-}" >"$dir/${fname}.classes"
	done
}

# tui.cache.load_dir DIR - reads cache files written by tui.cache.dump_dir
# into this process's own cache maps, dropping (not just leaving stale) any
# entry that fails tui.cache.valid against the current filesystem - callers
# can assume everything left after this call is actually usable, no
# separate check needed.
tui.cache.load_dir() {
	local dir="$1" f key
	local -a keys=() deps=()
	[[ -d "$dir" ]] || return 0
	for f in "$dir"/*.key; do
		[[ -e "$f" ]] || continue
		_tui_cache_slurp "$f"
		key="$_SLURP"
		_tui_cache_slurp "${f%.key}.cache"
		_TUI_CACHE_PAGE["$key"]="$_SLURP"
		_tui_cache_slurp "${f%.key}.sig"
		_TUI_CACHE_SIG["$key"]="$_SLURP"
		_tui_cache_slurp "${f%.key}.scripts"
		_TUI_CACHE_SCRIPTS["$key"]="$_SLURP"
		_tui_cache_slurp "${f%.key}.onvisit"
		_TUI_CACHE_ON_VISIT["$key"]="$_SLURP"
		_tui_cache_slurp "${f%.key}.gotos"
		_TUI_CACHE_GOTOS["$key"]="$_SLURP"
		_tui_cache_slurp "${f%.key}.theme"
		_TUI_CACHE_THEME["$key"]="$_SLURP"
		_tui_cache_slurp "${f%.key}.classes"
		_TUI_CACHE_CLASSES["$key"]="$_SLURP"
		keys+=("$key")
	done
	((${#keys[@]})) || return 0
	# every dependency of every cached page in one stat call; tui.cache.valid reads the result until
	# start_cached clears _TUI_CACHE_MTIME_FRESH; after start-up the cache is trusted (_TUI_CACHE_TRUSTED) and nothing stats at all
	local -a parts
	local pair
	for key in "${keys[@]}"; do
		IFS=';' read -ra parts <<<"${_TUI_CACHE_SIG[$key]:-}"
		for pair in "${parts[@]}"; do [[ -n "$pair" ]] && deps+=("${pair%=*}"); done
	done
	_tui_cache_stat_many "${deps[@]}"
	_TUI_CACHE_MTIME_FRESH=1
	for key in "${keys[@]}"; do
		tui.cache.valid "$key" || {
			unset '_TUI_CACHE_PAGE[$key]' '_TUI_CACHE_SIG[$key]' '_TUI_CACHE_SCRIPTS[$key]' \
				'_TUI_CACHE_ON_VISIT[$key]' '_TUI_CACHE_GOTOS[$key]' '_TUI_CACHE_THEME[$key]' \
				'_TUI_CACHE_CLASSES[$key]'
		}
	done
}

# tui.cache.disk_dir - the persistent, cross-run on-disk cache location:
# $TUI_HOME/cache/pages/ (in the DABT config home, not in the program folder).
tui.cache.disk_dir() {
	printf '%s' "$TUI_HOME/cache/pages"
}

# tui.cache.fname FILE -> stdout : the filesystem-safe encoding of a cache
# key tui.cache.dump_dir/tui.cache.warm_with_spinner's workers name files
# with.
tui.cache.fname() { printf '%s' "${1//\//_}"; }

# tui.cache.encode FILE -> stdout : everything tui.cache.record captured
# for FILE (signature, snapshot, scripts, on_visit, gotos), as one blob a
# parallel warm-up worker can write to a single file and a parent process
# can load back with tui.cache.decode - one atomic file per page instead of
# tui.cache.dump_dir's five, for stage 1.4's per-page worker pool.
tui.cache.encode() {
	local file="$1" sep=$'\x1e'
	printf '%s%s%s%s%s%s%s%s%s%s%s%s%s' \
		"${_TUI_CACHE_SIG[$file]:-}" "$sep" \
		"${_TUI_CACHE_PAGE[$file]:-}" "$sep" \
		"${_TUI_CACHE_SCRIPTS[$file]:-}" "$sep" \
		"${_TUI_CACHE_ON_VISIT[$file]:-}" "$sep" \
		"${_TUI_CACHE_GOTOS[$file]:-}" "$sep" \
		"${_TUI_CACHE_THEME[$file]:-}" "$sep" \
		"${_TUI_CACHE_CLASSES[$file]:-}"
}

# tui.cache.decode FILE BLOB - installs BLOB (from tui.cache.encode) as
# FILE's cache entry in this process's cache maps.
tui.cache.decode() {
	local file="$1" blob="$2" sep=$'\x1e'
	local -a parts=()
	# -d '': the blob's snapshot field is itself multi-line (declare -p, one
	# array per line) - plain `read` stops at the first newline regardless
	# of IFS, silently truncating everything after it.
	IFS="$sep" read -r -d '' -a parts <<<"$blob"
	_TUI_CACHE_SIG[$file]="${parts[0]:-}"
	_TUI_CACHE_PAGE[$file]="${parts[1]:-}"
	_TUI_CACHE_SCRIPTS[$file]="${parts[2]:-}"
	_TUI_CACHE_ON_VISIT[$file]="${parts[3]:-}"
	_TUI_CACHE_GOTOS[$file]="${parts[4]:-}"
	_TUI_CACHE_THEME[$file]="${parts[5]:-}"
	_TUI_CACHE_CLASSES[$file]="${parts[6]:-}"
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

	# Shared dependency, parsed once here in the parent: every page's <theme>
	# (its own, falling back to the framework default) gets the same
	# memoized parse (_tui.theme_load_file, tui_cache.sh's own stylesheet
	# memo above) BEFORE any worker forks, so every worker inherits an
	# already-populated _TUI_THEME_MEMO through fork copy-on-write memory
	# instead of re-parsing the same CSS once per page.
	tui.log.debug "tui.cache.warm_with_spinner: pre-parsing shared theme deps for ${#_tcw_pages[@]} page(s) in parent"
	[[ -r "${TUI_DEFAULTS_DIR:-}/theme.css" ]] && tui.load_theme "$TUI_DEFAULTS_DIR/theme.css" >/dev/null 2>&1
	local _tcw_dp _tcw_dtheme
	for _tcw_dp in "${_tcw_pages[@]}"; do
		if [[ "$_tcw_dp" == */* ]]; then _tcw_dtheme="${_tcw_dp%/*}/theme.css"; else _tcw_dtheme="./theme.css"; fi
		[[ -r "$_tcw_dtheme" ]] && tui.load_theme "$_tcw_dtheme" >/dev/null 2>&1
	done

	# One background subshell per stale page (a worker has no side effects
	# outside its own snapshot file - build is headless and sources no
	# <script>, see this file's top comment), up to
	# min(nproc, stale pages, TUI_CACHE_WORKERS), refilled as workers finish.
	local -a _tcw_pids=() _tcw_failed=()
	local _tcw_max="${TUI_CACHE_WORKERS:-}"
	[[ "$_tcw_max" =~ ^[0-9]+$ ]] || _tcw_max="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
	((_tcw_max < 1)) && _tcw_max=1
	((_tcw_max > ${#_tcw_pages[@]})) && _tcw_max=${#_tcw_pages[@]}
	local _tcw_total=${#_tcw_pages[@]} _tcw_next=0 _tcw_running=0

	# A worker's stdin/stdout are /dev/null - so its own tui.init can't put
	# the real terminal in raw mode and its screen paints never hit it -
	# and it reports one line down the shared fifo when its one page is
	# done (or failed), then exits: its snapshot is written atomically
	# (tmp.$BASHPID + mv), so a crashed worker leaves no partial .snap and
	# concurrent app instances warming the same page race harmlessly.
	_tui_cache_warm_worker() {
		local _tcw_page="$1"
		exec </dev/null
		exec 6>"$_tcw_fifo"
		exec 1>/dev/null 2>"$_tcw_root/worker.$BASHPID.stderr.log"
		tui.init
		tui.reset_ui
		if tui.cache.record "$_tcw_page"; then
			local _tcw_fn _tcw_tmp
			_tcw_fn="$(tui.cache.fname "$_tcw_page")"
			_tcw_tmp="$_tcw_cache_dir/${_tcw_fn}.snap.tmp.$BASHPID"
			tui.cache.encode "$_tcw_page" >"$_tcw_tmp"
			mv -f "$_tcw_tmp" "$_tcw_cache_dir/${_tcw_fn}.snap"
			printf 'DONE %s\n' "$_tcw_page" >&6
		else
			printf 'FAILED %s\n' "$_tcw_page" >&6
		fi
		exec 6>&-
		_master_cleanup 2>/dev/null
	}

	_tcw_launch_more() {
		while ((_tcw_next < _tcw_total && _tcw_running < _tcw_max)); do
			_tui_cache_warm_worker "${_tcw_pages[_tcw_next]}" &
			_tcw_pids+=($!)
			((_tcw_running++))
			((_tcw_next++))
		done
	}

	exec 5<>"$_tcw_fifo"
	# Ctrl-C: forward to every worker still running, not just wait for it -
	# a bare foreground `read`/sleep loop already gets SIGINT itself, but an
	# explicit kill of the pool avoids leaving orphaned page builds behind.
	trap '((${#_tcw_pids[@]})) && kill "${_tcw_pids[@]}" 2>/dev/null' INT
	_tcw_launch_more

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
	_tcw_start_us=${EPOCHREALTIME//[^0-9]/}
	_tcw_last_progress_us=$_tcw_start_us
	local _tcw_last_cycle_us=$_tcw_start_us

	local _tcw_bar_width=30
	local _tcw_last_pct=-1
	while ((! _tcw_done)); do
		# the bar is driven by pages completed (DONE/FAILED), not elapsed time
		if IFS= read -r -t 0.2 -u 5 _tcw_line2; then
			case "$_tcw_line2" in
				"DONE "*)
					((_tcw_current++))
					((_tcw_running--))
					_tcw_last_progress_us=${EPOCHREALTIME//[^0-9]/}
					_tcw_launch_more
					;;
				"FAILED "*)
					_tcw_failed+=("${_tcw_line2#FAILED }")
					((_tcw_current++))
					((_tcw_running--))
					_tcw_last_progress_us=${EPOCHREALTIME//[^0-9]/}
					_tcw_launch_more
					;;
			esac
		fi
		((_tcw_current >= _tcw_total)) && _tcw_done=1
		((_tcw_done)) && break
		_tcw_now=${EPOCHREALTIME//[^0-9]/}
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
				"$_tcw_bar_row" "$((_tcw_col0 - _tcw_bar_width / 2))" "$_tcw_bar" "$_tcw_pct"
		fi
	done

	wait "${_tcw_pids[@]}" 2>/dev/null
	trap - INT
	{ exec 5>&-; } 2>/dev/null

	# Load every page a worker actually finished - not tui.cache.load_dir
	# (that reads back tui.cache.dump_dir's five-file-per-page shape): each
	# worker wrote its own single atomic FILE.snap (tui.cache.encode), read
	# back here by the same original page path, not a directory scan.
	local _tcw_page3 _tcw_snap
	for _tcw_page3 in "${_tcw_pages[@]}"; do
		_tcw_snap="$_tcw_cache_dir/$(tui.cache.fname "$_tcw_page3").snap"
		[[ -f "$_tcw_snap" ]] && tui.cache.decode "$_tcw_page3" "$(<"$_tcw_snap")"
	done
	rm -rf "$_tcw_root" 2>/dev/null
	erase.all
	cur.show

	if ((${#_tcw_failed[@]} > 0)); then
		printf 'tui.cache.warm_with_spinner: %d page(s) failed to warm, falling back to an uncached load:\n' "${#_tcw_failed[@]}" >&2
		printf '  %s\n' "${_tcw_failed[@]}" >&2
	fi
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
	_tui_cache_dir "$file" && dir="$_CANON" || dir=""
	_TUI_APP_DIR="$dir"
	[[ -z "${TUI_THEMES_DIR:-}" && -d "$dir/themes" ]] && TUI_THEMES_DIR="$dir/themes"
	[[ -z "${TUI_THEMES_DIR:-}" && -d "$TUI_DEFAULTS_DIR/themes" ]] && TUI_THEMES_DIR="$TUI_DEFAULTS_DIR/themes"
	local -a pages=()
	while IFS= read -r f; do
		[[ "${f##*/}" == _* ]] && continue
		pages+=("$f")
	done < <(find "$dir" -maxdepth 1 -name '*.xml' | sort)
	while IFS= read -r f; do
		[[ "${f##*/}" == _* ]] && continue
		pages+=("$f")
	done < <(find "$TUI_DEFAULTS_DIR/pages" -maxdepth 1 -name '*.xml' 2>/dev/null | sort)

	# every page is checked up front (all of them are reachable), before the terminal is taken over
	_tui_validate.gate "${pages[@]}" || return 1

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
	_TUI_CACHE_MTIME_FRESH=0
	if ((${#stale[@]} > 0)); then
		tui.cache.warm_with_spinner "${stale[@]}"
		tui.cache.dump_dir "$disk_dir"
	fi
	# every page is now cached and checked against its files: from here on the files are assumed unchanged
	((TUI_CACHE_TRUST)) && _TUI_CACHE_TRUSTED=1

	tui.init
	if ! tui.load_cached "$file"; then
		_master_cleanup
		return 1
	fi
	_tui_validate.notify
	tui.run
}
