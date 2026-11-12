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
# requires: tui_style

declare -gA _TUI_CACHE_PAGE=()                           # resolved page path -> declare -p snapshot of its built engine state
declare -gA _TUI_CACHE_SIG=()                            # resolved page path -> "dep=mtime dep=mtime ..." signature
declare -gA _TUI_CACHE_SCRIPTS=()                        # resolved page path -> space-joined <script src> paths, re-sourced on every replay
declare -gA _TUI_CACHE_ON_VISIT=()                       # resolved page path -> on_visit function name, rerun on every replay
declare -gA _TUI_CACHE_GOTOS=()                          # resolved page path -> newline-joined "_tui_cache_define_goto ..." calls
declare -gA _TUI_CACHE_THEME=()                          # resolved page path -> its <theme src> file, reloaded on every replay
declare -gA _TUI_CACHE_CLASSES=()                        # resolved page path -> newline-joined "id\tclass" pairs, re-applied on every replay
declare -gA _TUI_CACHE_SHELL=()                          # resolved page path -> canonical path of its shell ("" for a page without one; unset = not recorded)
declare -gA _TUI_CACHE_SIZE=()                           # resolved page path -> "rows cols" of the terminal its geometry was laid out for
declare -gA _TUI_CACHE_PAGEUNDO=() _TUI_CACHE_PAGEGEO=() # shell page: scalar-restoring script / outlet "row col h w"; its _TUI_CACHE_PAGE is a delta over the shell
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
declare -g _TUI_CACHE_STATE_REGEX='^(_TUI_P_|_TUI_W_|_TUI_PANE_CONTENT$|_TUI_PANE_FOCUS$|_TUI_PANE_LAST_WIDGET$|_TUI_FACTORY_|_TUI_TABS_|_TUI_TAB_|_TUI_FOCUSABLE$|_TUI_FOCUS_ID$|_TUI_FOCUS_IDX$|_TUI_CURSOR$|_TUI_HOVERED_|_TUI_PENDING_OUTPUT$|_TUI_RENDER_TIMEOUT$|_TUI_TICK_FN$|_TUI_ON_RESIZE_FN$|_TUI_ON_INPUT_EVENT$|_TUI_ON_KEY_EVENT$|_TUI_STYLE_|_TUI_FOOTER_|_TUI_SHELL_|_TUI_OUTLET|_TUI_L_|_WX|_TX)'

# _tui_cache_snapshot -> stdout : a `declare -p` dump of every currently
# live variable tui.reset_ui/_tui_wx.reset would clear - the built page's
# whole engine-visible state, replayable with one eval. Every "declare -X" is
# already rewritten to "declare -gX" (see _tui_cache_restore for why), once here
# at record time instead of line by line on every replay (about 7 of 9.5 ms).
_tui_cache_snapshot() {
	local -a names=()
	local v dump line out=""
	# grep -E in one batch over compgen's whole list, not a bash [[ =~ ]]
	# loop per variable - bash has hundreds to thousands of variables in
	# scope (env, framework globals, ...); looping that many regex matches
	# in-shell measured slower than the one extra fork this pipe costs.
	while IFS= read -r v; do names+=("$v"); done < <(compgen -A variable | grep -E "$_TUI_CACHE_STATE_REGEX")
	((${#names[@]} > 0)) || return 0
	dump="$(declare -p "${names[@]}")"
	while IFS= read -r line; do
		if [[ "$line" == "declare --"* ]]; then
			line="declare -g${line#declare --}"
		elif [[ "$line" == "declare -"* ]]; then
			line="declare -g${line#declare -}"
		fi
		out+="$line"$'\n'
	done <<<"$dump"
	# the terminal size the geometry in this snapshot was laid out for (tui.load ends with a layout): a replay at the
	# same size and footer needs no relayout, see tui.cache.replay
	printf '%sdeclare -g _TUI_SNAP_SIZE="%s %s %s %s"' "$out" "$_TUI_ROWS" "$_TUI_COLS" "$_TUI_FOOTER_ON" "$_TUI_DBG_ROWS"
}
declare -g _TUI_SNAP_SIZE=""

# _tui_cache_restore DUMP - restores a _tui_cache_snapshot dump. Run inside
# a function: declare -p's own output has no -g, so every "declare -X"
# becomes "declare -gX" before eval to land at global scope (same fix as
# tui_node.sh's load, stage 0.5) - line by line, since a plain scalar's
# "declare -- NAME=…" would otherwise collide with a blind `declare -`
# string replace (it turns "-- " into "-g- ", an invalid option).
_tui_cache_restore() {
	# a snapshot written by _tui_cache_snapshot is ready to eval; one recorded by an earlier version (still on disk)
	# has plain `declare -p` lines and goes through the rewrite below
	if [[ "$1" == "declare -g"* ]]; then
		eval "$1"
		return
	fi
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
declare -gA _TUI_THEME_MEMO=() _TUI_THEME_STAMP=() # file -> "class<US>fg<US>bg<US>mods<US>cursor\n..." (+ "@slot<US>glyph" lines) / stamp path
declare -gA _TUI_THEME_DEPS=()                     # file -> the files it @imports, newline-separated: editing one makes the memo stale
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

# _tui_cache_theme_fresh FILE - rc 0 while neither FILE nor anything it imports is newer than the memo's stamp
_tui_cache_theme_fresh() {
	local stamp="${_TUI_THEME_STAMP[$1]}" dep
	[[ ! "$1" -nt "$stamp" ]] || return 1
	while IFS= read -r dep; do
		[[ -z "$dep" || ! "$dep" -nt "$stamp" ]] || return 1
	done <<<"${_TUI_THEME_DEPS[$1]:-}"
}

_tui.theme_load_file() {
	local file="$1" cls fg bg mods cur out="" slot dep deps=""
	if ((_TUI_CACHES)) && [[ -n "${_TUI_THEME_MEMO[$file]+x}" ]] && { ((_TUI_CACHE_TRUSTED)) || _tui_cache_theme_fresh "$file"; }; then
		tui.log.debug "_tui.theme_load_file: memo HIT for $file, re-applying from memory"
		# fd 7, not stdin: tui.load_theme runs mid-build (from a <theme> tag
		# handler); keep fd 0 free for the tty the same way tui.cache.replay's
		# fd-9 goto/on_visit loop does.
		while IFS=$'\x1f' read -r -u 7 cls fg bg mods cur; do # hit: re-apply, nothing is parsed
			[[ -z "$cls" ]] && continue
			[[ "$cls" == @* ]] && {
				_TUI_G[${cls#@}]="$fg"
				continue
			} # glyph record: the glyph rides in the fg field
			[[ -n "$fg" ]] && _TUI_CLASS_FG[$cls]="$fg"
			[[ -n "$bg" ]] && _TUI_CLASS_BG[$cls]="$bg"
			[[ -n "$mods" ]] && _TUI_CLASS_MOD[$cls]="$mods"
			[[ -n "$cur" ]] && _TUI_CLASS_CUR[$cls]="$cur"
		done 7<<<"${_TUI_THEME_MEMO[$file]}"
		_TUI_G_GEN+=1
		return 0
	fi

	tui.log.debug "_tui.theme_load_file: memo MISS for $file, parsing from disk"
	_tui.theme_parse "$file" || return 1
	_tui.theme_commit
	for cls in "${_TP_ORDER[@]}"; do
		out+="$cls"$'\x1f'"${_TP_FG[$cls]:-}"$'\x1f'"${_TP_BG[$cls]:-}"$'\x1f'"${_TP_MOD[$cls]:-}"$'\x1f'"${_TP_CUR[$cls]:-}"$'\n'
	done
	for slot in "${!_TP_G[@]}"; do out+="@$slot"$'\x1f'"${_TP_G[$slot]}"$'\x1f\x1f\x1f\n'; done
	_TUI_THEME_MEMO[$file]="$out"
	for dep in "${_TP_DEPS[@]}"; do deps+="$dep"$'\n'; done
	_TUI_THEME_DEPS[$file]="$deps"
	_tui_cache_theme_stamp "$file"
	_tui.theme_check "$file"
}

# Forget every memoized stylesheet (tests, or after changing files in a way mtimes can't show).
tui.cache.theme_clear() {
	_TUI_THEME_MEMO=()
	_TUI_THEME_STAMP=()
	_TUI_THEME_DEPS=()
}

# Removes the stamp directory; called from _master_cleanup.
tui.cache.cleanup() {
	_tui_cache_lazy.stop
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

# _tui_cache_select_active_tabs FILE - after a restore, flags exactly each tabs group's active tab as selected.
# A snapshot recorded before tui.select existed (or under the bug that left sibling flags set) cannot be trusted
# for the flags, but always carries _TUI_TABS_ACTIVE.
_tui_cache_select_active_tabs() {
	local file="$1" tab_id group_id selected=""
	tui.log.debug "tui.cache.replay: '$file': ${#_TUI_TAB_GROUP[@]} tab(s) in ${#_TUI_TABS_ACTIVE[@]} group(s), rebuilding selected flags"
	for tab_id in "${!_TUI_TAB_GROUP[@]}"; do unset '_TUI_W_SELECTED[$tab_id]'; done
	for group_id in "${!_TUI_TABS_ACTIVE[@]}"; do
		tab_id="${_TUI_TABS_ACTIVE[$group_id]}"
		if [[ -z "${_TUI_TAB_GROUP[$tab_id]:-}" ]]; then
			tui.log.warn "tui.cache.replay: '$file': group '$group_id' names active tab '$tab_id', which is in no group; not selected"
			continue
		fi
		_TUI_W_SELECTED[$tab_id]=1
		selected+=" $tab_id"
	done
	tui.log.debug "tui.cache.replay: '$file': selected tabs:${selected:- <none>}"
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
	printf -v def '%s() { _tui_markup.nav %q; }' "$fn" "$page" # printf -v: no command-substitution fork per nav button
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
		_markup_attrv "$line" src src
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
	local file="$1" _rec_join _rec_shell=""
	tui.log.debug "tui.cache.record: building $file fresh (cache miss)"
	_tui_shell.scan "$file" 1
	_rec_shell="$_SH_OF"
	if [[ -n "$_rec_shell" ]]; then # a page of a shell: the shell is live first, the page is recorded as a delta over it
		_tui_shell.ensure "$_rec_shell" 1 || return 1
		_tui_shell.leave_page # what an earlier page left in the outlet
		_tui_shell.base_capture
		_SHL_RECORD=1
	fi
	_TUI_CACHE_REC_SCRIPTS=()
	_TUI_CACHE_REC_GOTOS=()
	_TUI_CACHE_REC_THEME=""
	_TUI_CACHE_REC_CLASSES=()
	tui.load "$file" || {
		_SHL_RECORD=0
		return 1 # a worker (1.4) checks this: no snapshot, page falls back to an uncached load
	}
	_SHL_RECORD=0
	_TUI_STYLE_SIG="${_TUI_THEME_OVERLAY:-}"
	_TUI_CACHE_SHELL["$file"]="$_rec_shell"
	_TUI_CACHE_SIZE["$file"]="$_TUI_ROWS $_TUI_COLS"
	if [[ -n "$_rec_shell" ]]; then # _SH_APPLY / _SH_UNDO: the delta tui.load took before on_visit
		printf -v _rec_join '_TUI_STYLE_SIG=%q\n' "$_TUI_STYLE_SIG"
		_TUI_CACHE_PAGE["$file"]="${_SH_APPLY}${_rec_join}"
		_TUI_CACHE_PAGEUNDO["$file"]="$_SH_UNDO"
		_tui_shell.geometry
		_TUI_CACHE_PAGEGEO["$file"]="$_SH_GEO"
		_tui_shell.drop_base
	else
		_TUI_CACHE_PAGE["$file"]="$(_tui_cache_snapshot)"
	fi
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
	tui_addon.deps deps "$file"
	tui_plugin.deps deps
	if [[ -n "$_rec_shell" ]]; then # changing the shell invalidates every page that uses it
		tui.cache.deps_of "$_rec_shell" deps
		tui_addon.deps deps "$_rec_shell"
	fi
	_TUI_CACHE_SIG["$file"]="$(tui.cache.signature "${deps[@]}")"
}

# tui.cache.forget FILE - drops everything cached for FILE (an absolute page path): its next visit builds fresh.
# For a page whose inputs changed while the app runs, where the trusted cache (below) would not look.
tui.cache.forget() {
	unset '_TUI_CACHE_PAGE[$1]' '_TUI_CACHE_SIG[$1]' '_TUI_CACHE_SCRIPTS[$1]' \
		'_TUI_CACHE_ON_VISIT[$1]' '_TUI_CACHE_GOTOS[$1]' '_TUI_CACHE_THEME[$1]' \
		'_TUI_CACHE_CLASSES[$1]' '_TUI_CACHE_SHELL[$1]' '_TUI_CACHE_PAGEUNDO[$1]' '_TUI_CACHE_PAGEGEO[$1]' '_TUI_CACHE_SIZE[$1]'
}

# 1 once tui.start_cached has validated and warmed every page: source files are then assumed not to change while the
# app runs, so tui.cache.valid and the theme memo stop checking mtimes (one stat call per page switch gone). Edits made
# while the app runs take effect on the next start. TUI_CACHE_TRUST=0 keeps the live checks (developing a page).
declare -gi _TUI_CACHE_TOTAL=0 _TUI_CACHE_STALE=0 _TUI_CACHE_ON_DISK=0 # start_cached: pages known, built this start, found valid on disk
declare -gi _TUI_CACHE_TRUSTED=0
declare -gi TUI_CACHE_TRUST="${TUI_CACHE_TRUST:-1}"

# tui.cache.valid FILE - true if FILE has a cached page AND every
# dependency file its signature covers (the page itself plus every
# <include> it pulled in at record time) still has the exact mtime it had
# then, i.e. neither the page nor anything it includes has changed since.
# Once the cache is trusted (_TUI_CACHE_TRUSTED) a recorded page is simply valid: no stat.
tui.cache.valid() {
	((_TUI_CACHES)) || return 1
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
	local file="$1" rec shell="${_TUI_CACHE_SHELL[$1]:-}"
	[[ -n "${_TUI_CACHE_PAGE[$file]:-}" ]] || return 1
	tui.log.debug "tui.cache.replay: replaying $file from snapshot (cache hit)"
	if [[ -n "$shell" ]]; then
		_tui_shell.ensure "$shell" 1 || return 1
		_tui_shell.leave_page
	fi
	_TUI_STYLE_SIG="?" # a snapshot recorded before the signature existed leaves it at "?": never equal, so it re-bakes
	_TUI_SNAP_SIZE=""  # a snapshot from an earlier version does not set it
	_TUI_W_SELECTED=() # likewise lacks the array: must not keep the previous page's selected tabs
	if [[ -n "$shell" ]]; then
		_tui_shell.apply "$file"
	else
		_tui_cache_restore "${_TUI_CACHE_PAGE[$file]}"
		# a fresh build reaches on_visit with no focus and no hover (tui.goto and the app put them back afterwards); the
		# snapshot carries the recording's, so an on_visit that reads the focus would see a different page
		_TUI_FOCUS_ID="" _TUI_FOCUS_IDX=-1 _TUI_CURSOR=0 _TUI_PANE_FOCUS="" _TUI_HOVERED_PANE="" _TUI_HOVERED_WIDGET=""
	fi
	_tui_cache_select_active_tabs "$file"
	_tui.epoch_bump style  # the restore replaced the style tables; the epoch is not in the snapshot (it only ever grows)
	_tui.epoch_bump layout # the layout memo belongs to the previous page (see _tui_cache_relayout)
	local _ly_gen=$_TUI_LY_GEN
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
		# two passes: clear every recorded id first (an id may carry several classes that merge), then bake
		while IFS=$'\t' read -r -u 6 _rc_id _rc_cls; do
			[[ -z "$_rc_id" ]] && continue
			_tui.style_clear "$_rc_id"
		done 6<<<"${_TUI_CACHE_CLASSES[$file]:-}"
		while IFS=$'\t' read -r -u 6 _rc_id _rc_cls; do
			[[ -z "$_rc_id" ]] && continue
			tui.class "$_rc_id" "$_rc_cls"
		done 6<<<"${_TUI_CACHE_CLASSES[$file]:-}"
	fi
	# _TUI_FL_ORDER (lib/chrome/tui_layer.sh) isn't page state, so it isn't in the
	# snapshot: tui.reset_ui's _tui_footer.reset always removes _tui_footer.draw from it,
	# and restoring _TUI_FOOTER_ON=1 alone wouldn't re-add it without this.
	[[ -z "$shell" ]] && ((_TUI_FOOTER_ON)) && tui.layer.fn_add _tui_footer.draw ambient
	# a recorded script's exec controls came back with the snapshot, but the instance they belonged to is gone: the re-sourced script starts a new one
	local s ns live=" ${_EXEC_NS[*]} "
	for ns in "${!_TUI_FACTORY_IDS[@]}"; do
		[[ "$ns" == exec_* && "$live" != *" $ns "* ]] && tui.factory.clear "$ns"
	done
	for s in ${_TUI_CACHE_SCRIPTS[$file]:-}; do _tui_cache_source "$s"; done
	# the goto/on_visit calls come in on fd 9, not stdin: they must see the terminal on stdin - with them on
	# stdin, `stty size` failed and a tui.goto from on_visit laid out at 80x24
	while IFS= read -r -u 9 rec; do
		[[ -z "$rec" ]] && continue
		eval "$rec"
	done 9<<<"${_TUI_CACHE_GOTOS[$file]:-}"
	# The restored geometry was laid out at the size the page was recorded at. When the terminal and the footer still
	# match and nothing the scripts did changed a layout input (every layout setter bumps _TUI_LY_GEN), it is already
	# right: no relayout (the memo was invalidated above, so a later layout still recomputes everything).
	if [[ -n "$shell" ]]; then # the page's panes were laid out in the outlet's rectangle of the recording
		_tui_shell.geometry
		if [[ "$_SH_GEO" == "${_TUI_CACHE_PAGEGEO[$file]:-}" ]] && ((_TUI_LY_GEN == _ly_gen)); then
			_tui_perf.count relayout_skipped
		else
			_tui.epoch_bump layout
			_tui._layout "$_TUI_OUTLET"
		fi
		((_TUI_L_N)) && _tui_layer.layout # the recorded rectangles of the layers belong to the recording's screen
	elif [[ "$_TUI_SNAP_SIZE" == "$_TUI_ROWS $_TUI_COLS $_TUI_FOOTER_ON $_TUI_DBG_ROWS" ]] && ((_TUI_LY_GEN == _ly_gen)); then
		_tui_perf.count relayout_skipped
	else
		_tui_cache_relayout
	fi
	_tui_cache_run_on_visit "${_TUI_CACHE_ON_VISIT[$file]:-}"
	[[ -n "$shell" ]] && _tui_shell.sync_page_ids # on_visit may have added widgets
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

	local _lc_valid=no _lc_t0=0
	((TUI_DEBUG)) && _lc_t0=${EPOCHREALTIME//[!0-9]/}
	tui.cache.valid "$resolved" && _lc_valid=yes
	tui.log.debug "tui.load_cached: $resolved valid=$_lc_valid overlay=${_TUI_THEME_OVERLAY:-<none>}"
	if [[ "$_lc_valid" == yes ]] && tui.cache.replay "$resolved"; then
		_tui_perf.count cache_hit
		((TUI_DEBUG)) && _tui_debug.visit "$resolved" hit "$_lc_t0"
		return 0
	fi
	_tui_perf.count cache_miss
	((TUI_DEBUG)) && tui.debug.event cache.page.miss "$resolved"
	tui.cache.record "$resolved"
	local _lc_rc=$?
	((TUI_DEBUG)) && _tui_debug.visit "$resolved" miss "$_lc_t0"
	return $_lc_rc
}

# ── cache (de)serialization - crosses the precompute worker's process
# boundary, since a background process can't share bash memory with the
# foreground one it's warming a cache for. ──────────────────────────────

# tui.cache.dump_page KEY [DIR] - one page's cache entry as ONE file, DIR/<fname>.page (DIR defaults to the disk cache
# the background pool persists into). The file is the entry packed by tui.cache.encode between a version tag with the key
# and an end marker, fields apart by \x1e: one read loads it, and a writer that stopped halfway leaves no marker, so a reader
# (tui.cache.load_dir, _tui_cache_base_load) never takes a partial page. No rename: a rewrite is plain, and a fork-free write.
declare -g _TUI_CACHE_FILE_TAG="DABT-PAGE-1"
tui.cache.dump_page() {
	local key="$1" dir="${2:-$_TUI_LAZY_DISK}"
	{
		printf '%s\x1e%s\x1e' "$_TUI_CACHE_FILE_TAG" "$key"
		tui.cache.encode "$key"
		printf '\x1eEND'
	} >"$dir/${key//\//_}.page"
}

# tui.cache.dump_dir DIR - writes every recorded page to DIR, one file each (tui.cache.dump_page). Also usable as a
# persistent on-disk cache, not just to cross the precompute worker's process boundary - see tui.cache.disk_dir.
tui.cache.dump_dir() {
	local dir="$1" key
	mkdir -p "$dir"
	for key in "${!_TUI_CACHE_PAGE[@]}"; do tui.cache.dump_page "$key" "$dir"; done
}

# _tui_cache_read_file FILE -> _TCI: FILE's fields (tag, key, then the encoded entry); rc 1 unless it is a whole page file
declare -ga _TCI=()
_tui_cache_read_file() {
	_TCI=()
	[[ -f "$1" ]] || return 1
	IFS=$'\x1e' read -r -d '' -a _TCI <"$1"
	[[ "${_TCI[0]:-}" == "$_TUI_CACHE_FILE_TAG" && "${_TCI[13]:-}" == END ]]
}

# tui.cache.load_dir DIR - reads page files written by tui.cache.dump_dir into this process's own cache maps, dropping
# (not just leaving stale) any entry that fails tui.cache.valid against the current filesystem - callers can assume
# everything left after this call is actually usable, no separate check needed. The files of the older layout (twelve per
# page) are deleted the first time they are seen; their pages are built again.
tui.cache.load_dir() {
	local dir="$1" f key
	local -a keys=() deps=()
	[[ -d "$dir" ]] || return 0
	if compgen -G "$dir/*.key" >/dev/null; then
		rm -f "$dir"/*.{key,cache,sig,scripts,onvisit,gotos,theme,classes,shell,pageundo,pagegeo,size}
	fi
	for f in "$dir"/*.page; do
		_tui_cache_read_file "$f" || continue
		key="${_TCI[1]}"
		_tui_cache_install "$key" 2
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
			tui.cache.forget "$key"
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
	printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s' \
		"${_TUI_CACHE_SIG[$file]:-}" "$sep" \
		"${_TUI_CACHE_PAGE[$file]:-}" "$sep" \
		"${_TUI_CACHE_SCRIPTS[$file]:-}" "$sep" \
		"${_TUI_CACHE_ON_VISIT[$file]:-}" "$sep" \
		"${_TUI_CACHE_GOTOS[$file]:-}" "$sep" \
		"${_TUI_CACHE_THEME[$file]:-}" "$sep" \
		"${_TUI_CACHE_CLASSES[$file]:-}" "$sep" \
		"${_TUI_CACHE_SHELL[$file]:-}" "$sep" \
		"${_TUI_CACHE_PAGEGEO[$file]:-}" "$sep" \
		"${_TUI_CACHE_PAGEUNDO[$file]:-}" "$sep" \
		"${_TUI_CACHE_SIZE[$file]:-}"
}

# tui.cache.decode FILE BLOB - installs BLOB (from tui.cache.encode) as
# FILE's cache entry in this process's cache maps.
tui.cache.decode() {
	local file="$1" blob="$2"
	# -d '': the blob's snapshot field is itself multi-line (declare -p, one array per line) - plain `read` stops at the
	# first newline regardless of IFS, silently truncating everything after it.
	IFS=$'\x1e' read -r -d '' -a _TCI <<<"$blob"
	_tui_cache_install "$file" 0
	_TUI_CACHE_SIZE[$file]="${_TUI_CACHE_SIZE[$file]%$'\n'}" # the here-string adds one newline to the last field
}

# _tui_cache_install FILE FIRST - FILE's cache entry from the fields _TCI[FIRST..FIRST+10], in tui.cache.encode's order
_tui_cache_install() {
	local file="$1" i=$2
	_TUI_CACHE_SIG[$file]="${_TCI[i]:-}"
	_TUI_CACHE_PAGE[$file]="${_TCI[i + 1]:-}"
	_TUI_CACHE_SCRIPTS[$file]="${_TCI[i + 2]:-}"
	_TUI_CACHE_ON_VISIT[$file]="${_TCI[i + 3]:-}"
	_TUI_CACHE_GOTOS[$file]="${_TCI[i + 4]:-}"
	_TUI_CACHE_THEME[$file]="${_TCI[i + 5]:-}"
	_TUI_CACHE_CLASSES[$file]="${_TCI[i + 6]:-}"
	_TUI_CACHE_SHELL[$file]="${_TCI[i + 7]:-}"
	_TUI_CACHE_PAGEGEO[$file]="${_TCI[i + 8]:-}"
	_TUI_CACHE_PAGEUNDO[$file]="${_TCI[i + 9]:-}"
	_TUI_CACHE_SIZE[$file]="${_TCI[i + 10]:-}"
}

# tui.cache.is_sized FILE - true when FILE's cached geometry was laid out for the current terminal size, so a replay needs
# no relayout (see tui.cache.replay). A page cached before the size was recorded is not.
tui.cache.is_sized() {
	local rows cols
	term.size rows cols
	[[ "${_TUI_CACHE_SIZE[$1]:-}" == "$rows $cols" ]]
}

# _tui_cache_resized PAGE... -> _TUI_CACHE_RESIZED: the cached PAGEs whose geometry is for another terminal size. They are
# re-fitted by the background pool, so the first visit replays without a relayout.
declare -ga _TUI_CACHE_RESIZED=()
_tui_cache_resized() {
	local p
	_TUI_CACHE_RESIZED=()
	for p; do
		[[ -n "${_TUI_CACHE_PAGE[$p]:-}" ]] && ! tui.cache.is_sized "$p" && _TUI_CACHE_RESIZED+=("$p")
	done
	return 0
}

_tui_cache_now_us() { printf '%s' "${EPOCHREALTIME//[^0-9]/}"; }

# _tui_cache_warm_prelude PAGE... - what every page's build shares, done once in the parent so forked workers inherit it
# through copy-on-write memory instead of redoing it per page: each page's <theme> (its own, else the framework default)
# parsed into the stylesheet memo, and the shells built once (a worker replays them).
_tui_cache_warm_prelude() {
	tui.log.debug "tui.cache.warm: pre-parsing shared theme deps for $# page(s) in parent"
	[[ -r "${TUI_DEFAULTS_DIR:-}/theme.css" ]] && tui.load_theme "$TUI_DEFAULTS_DIR/theme.css" >/dev/null 2>&1
	# tui.load_theme costs about 3 ms even for a memoized file: once per distinct file, not once per page
	local page theme seen=" ${TUI_DEFAULTS_DIR:-}/theme.css "
	for page; do
		if [[ "$page" == */* ]]; then theme="${page%/*}/theme.css"; else theme="./theme.css"; fi
		[[ "$seen" == *" $theme "* ]] && continue
		seen+="$theme "
		[[ -r "$theme" ]] && tui.load_theme "$theme" >/dev/null 2>&1
	done
	_tui_shell.warm "$@"
}

# _tui_cache_warm_worker PAGE ROOT REPORT [TAG] - one forked build of PAGE: headless, no side effects outside its own snapshot
# ROOT/cache/<fname>.snap (written atomically via tmp + mv, so a crashed worker leaves no partial file and concurrent
# app instances warming the same page race harmlessly). Stdin/stdout are /dev/null, so its tui.init cannot take the
# terminal; it appends one "DONE TAGpage" or "FAILED TAGpage" line to REPORT (a fifo or a file) and exits.
_tui_cache_warm_worker() {
	local _tcw_page="$1" _tcw_root="$2" _tcw_cache_dir="$2/cache" _tcw_tag="${4:-}"
	exec </dev/null
	exec 6>>"$3"
	exec 1>/dev/null 2>"$_tcw_root/worker.$BASHPID.stderr.log"
	# a worker that dies without reporting (an error aborting the build) would leave the parent waiting forever
	trap 'tui.log.error "cache worker $BASHPID: died while recording $_tcw_page without reporting, reporting FAILED"; printf "FAILED %s%s\n" "$_tcw_tag" "$_tcw_page" >&6' EXIT
	tui.log.debug "cache worker $BASHPID: recording $_tcw_page"
	_TUI_WARM_WORKER=1
	tui.init
	tui.reset_ui
	if tui.cache.record "$_tcw_page"; then
		local _tcw_fn _tcw_tmp
		_tcw_fn="$(tui.cache.fname "$_tcw_page")"
		_tcw_tmp="$_tcw_cache_dir/${_tcw_fn}.snap.tmp.$BASHPID"
		tui.cache.encode "$_tcw_page" >"$_tcw_tmp"
		mv -f "$_tcw_tmp" "$_tcw_cache_dir/${_tcw_fn}.snap"
		tui.log.debug "cache worker $BASHPID: $_tcw_page recorded, snapshot at $_tcw_cache_dir/${_tcw_fn}.snap"
		printf 'DONE %s%s\n' "$_tcw_tag" "$_tcw_page" >&6
	else
		tui.log.warn "cache worker $BASHPID: tui.cache.record failed for $_tcw_page"
		printf 'FAILED %s%s\n' "$_tcw_tag" "$_tcw_page" >&6
	fi
	trap - EXIT
	exec 6>&-
	_master_cleanup 2>/dev/null
}

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
	_tui_mkdtemp _tcw_root tui_cache_warm || return 1
	_tcw_cache_dir="$_tcw_root/cache"
	_tcw_fifo="$_tcw_root/progress.fifo"
	mkdir -p "$_tcw_cache_dir"
	mkfifo "$_tcw_fifo"

	_tui_cache_warm_prelude "${_tcw_pages[@]}"

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

	_tcw_launch_more() {
		while ((_tcw_next < _tcw_total && _tcw_running < _tcw_max)); do
			_tui_cache_warm_worker "${_tcw_pages[_tcw_next]}" "$_tcw_root" "$_tcw_fifo" &
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
	# (that reads back tui.cache.dump_dir's one-file-per-page shape): each
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

# ── lazy warm-up: pages after the first are built while the app runs; later, resizes re-fit the cached pages ──────
#
# One pool driver (_tui_cache_lazy.serve) is forked before the terminal is taken over, so the workers it forks never touch
# the running UI. It stays up for the whole run, blocked on a fifo, and serves a numbered request ("generation") at a time:
# a list of pages, each either built from scratch (no signature) or only re-fitted to the terminal size (its cached
# signature). A newer request cancels the running one. The app polls the current generation's directory from its tick.

declare -g _TUI_LAZY_ROOT="" _TUI_LAZY_PID="" _TUI_LAZY_OWNER="" _TUI_LAZY_TOAST="" _TUI_LAZY_QUIET=0 _TUI_LAZY_FD="" _TUI_LAZY_DISK=""
declare -gi _TUI_LAZY_GEN=0 _TUI_LAZY_BUILT=0 _TUI_LAZY_DEBOUNCE_AT=0
declare -ga _TUI_LAZY_PENDING=() _TUI_LAZY_ALL=()
declare -gA _TUI_LAZY_REFRESH=() # pages the pool re-fits to the terminal size: their snapshot replaces the page's geometry only

# _tui_cache_lazy.split FIRST STALE... -> _TUI_LAZY_FIRST (FIRST when it is among STALE, else empty) and _TUI_LAZY_LATER
declare -ga _TUI_LAZY_FIRST=() _TUI_LAZY_LATER=()
_tui_cache_lazy.split() {
	local first="$1" p
	shift
	_TUI_LAZY_FIRST=() _TUI_LAZY_LATER=()
	for p; do
		if [[ "$p" == "$first" ]]; then _TUI_LAZY_FIRST+=("$p"); else _TUI_LAZY_LATER+=("$p"); fi
	done
}

# _tui_cache_lazy.order FIRST - puts the pages FIRST links to (its buttons' and its shell's gotos, in the order they appear)
# in front of the others in _TUI_LAZY_LATER: the next click is most likely one of them, and it should find its page built
_tui_cache_lazy.order() {
	local first="$1" dir="${1%/*}" gotos line page p
	local -a seq=() ordered=()
	local -A linked=() later=()
	gotos="${_TUI_CACHE_GOTOS[$first]:-}"
	[[ -n "${_TUI_CACHE_SHELL[$first]:-}" ]] && gotos+=$'\n'"${_TUI_CACHE_GOTOS[${_TUI_CACHE_SHELL[$first]}]:-}"
	while IFS= read -r line; do
		[[ "$line" == "_tui_cache_define_goto "* ]] || continue
		eval "set -- ${line#_tui_cache_define_goto }" # the recorded calls are %q-quoted, and are eval'd on every replay too
		page="${2:-}"
		[[ -n "$page" ]] || continue
		[[ "$page" == /* ]] || page="$dir/${page#./}"
		[[ -n "${linked[$page]+x}" ]] && continue
		linked[$page]=1
		seq+=("$page")
	done <<<"$gotos"
	for p in "${_TUI_LAZY_LATER[@]}"; do later[$p]=1; done
	for p in "${seq[@]}"; do [[ -n "${later[$p]+x}" ]] && ordered+=("$p") && unset "later[$p]"; done
	for p in "${_TUI_LAZY_LATER[@]}"; do [[ -n "${later[$p]+x}" ]] && ordered+=("$p"); done
	_TUI_LAZY_LATER=("${ordered[@]}")
}

# _tui_cache_refit_page PAGE -> _RF_PAGE _RF_UNDO _RF_GEO: PAGE's cached state laid out for the terminal size in
# _TUI_ROWS/_TUI_COLS, the steps tui.cache.replay takes at a different size. A page without a shell is restored, laid out
# and snapshotted again. A page of a shell is applied as a delta onto the shell (replayed from the cache), only the outlet
# is laid out, and the delta against the shell is taken again, as tui.cache.record takes it.
_tui_cache_refit_page() {
	local page="$1" shell="${_TUI_CACHE_SHELL[$1]:-}" _rf_join
	_RF_UNDO="" _RF_GEO=""
	if [[ -z "$shell" ]]; then
		_tui_cache_restore "${_TUI_CACHE_PAGE[$page]}"
		_tui_cache_relayout
		_RF_PAGE="$(_tui_cache_snapshot)"
		return 0
	fi
	tui.reset_ui
	_tui_shell.ensure "$shell" 1 || return 1
	_tui_shell.leave_page
	_tui_shell.base_capture
	_tui_shell.apply "$page"
	_tui_cache_select_active_tabs "$page"
	_tui.epoch_bump layout
	_tui._layout "$_TUI_OUTLET"
	_tui_shell.delta
	printf -v _rf_join '_TUI_STYLE_SIG=%q\n' "$_TUI_STYLE_SIG"
	_RF_PAGE="${_SH_APPLY}${_rf_join}"
	_RF_UNDO="$_SH_UNDO"
	_tui_shell.geometry
	_RF_GEO="$_SH_GEO"
}

# _tui_cache_refresh_job PAGE GENDIR REPORT TAG SIG - one forked re-fit of PAGE's cached state to the terminal size in
# _TERM_SIZE (see _tui_cache_refit_page): no markup parse, no scripts, no on_visit, and no tui.init (nothing here touches
# the terminal). The new state is written as "SIZE GEO UNDO PAGE", fields apart by \x1e. SIG is the signature the cached
# page must carry; the disk copy is used when the process has no such entry.
_tui_cache_refresh_job() {
	local page="$1" dir="$2" tag="$4" sig="$5" tmp sep=$'\x1e'
	exec </dev/null >/dev/null 2>&1
	exec 6>>"$3"
	trap 'printf "FAILED %s%s\n" "$tag" "$page" >&6' EXIT
	tmp="$dir/cache/${page//\//_}.rsnap.tmp.$BASHPID"
	if _tui_cache_base_load "$page" "$sig"; then
		_TUI_ROWS="${_TERM_SIZE% *}" _TUI_COLS="${_TERM_SIZE#* }"
		if _tui_cache_refit_page "$page"; then
			printf '%s' "$_TUI_ROWS $_TUI_COLS$sep$_RF_GEO$sep$_RF_UNDO$sep$_RF_PAGE" >"$tmp" && mv -f "$tmp" "${tmp%.tmp.*}" &&
				printf 'DONE %s%s\n' "$tag" "$page" >&6 && trap - EXIT
		fi
	fi
	exit 0
}

# _tui_cache_base_load PAGE SIG - makes the cached state of PAGE, the one carrying signature SIG, the process's own:
# already there, or read from the page file on disk, which counts only when it is whole (see tui.cache.dump_page) and
# carries signature SIG.
_tui_cache_base_load() {
	local page="$1" sig="$2" dir
	[[ -n "$sig" ]] || return 1
	[[ "${_TUI_CACHE_SIG[$page]:-}" == "$sig" && -n "${_TUI_CACHE_PAGE[$page]:-}" ]] && return 0
	dir="$(tui.cache.disk_dir)"
	_tui_cache_read_file "$dir/${page//\//_}.page" && [[ "${_TCI[2]}" == "$sig" && -n "${_TCI[3]}" ]] || return 1
	_tui_cache_install "$page" 2
}

# _tui_cache_persist_size PAGE - PAGE's re-fitted entry into its page file on disk (see tui.cache.dump_page: a reader never
# takes a half-written file)
_tui_cache_persist_size() {
	[[ -d "$_TUI_LAZY_DISK" && -e "$_TUI_LAZY_DISK/${1//\//_}.page" ]] || return 0 # only a page that is on disk already
	tui.cache.dump_page "$1"
}

# _tui_cache_lazy.serve ROOT OWNER MAX PAGE... - the pool driver: serves requests from the fifo ROOT/req until OWNER (the
# app) is gone. PAGE... is every page of the app (themes and shells are prepared for them once, TUI_CACHE_LAZY_PREP, before
# the first build, and inherited by the workers). Workers report "DONE|FAILED GEN PAGE" down the same fifo, which keeps
# MAX of them running and ends a cancelled request's workers.
_tui_cache_lazy.serve() {
	local root="$1" owner="$2" max="$3" fd line tag f=0 i gen=-1 running=0 next=0 total=0 prepared=0 sep=$'\x1f'
	shift 3
	local -a all=("$@") pids=() queue=() sigs=() fields=()
	exec </dev/null >/dev/null 2>&1
	trap - EXIT INT
	((${TUI_CACHE_LAZY_NICE:-10} > 0)) && renice -n "${TUI_CACHE_LAZY_NICE:-10}" -p "$BASHPID" >/dev/null 2>&1 # workers inherit it: the app's own input wins the cores
	exec {fd}<>"$root/req"
	trap 'kill "${pids[@]}" 2>/dev/null; exit 0' TERM
	_tcl_launch() {
		while ((next < total && running < max)); do
			if [[ -n "${sigs[next]}" ]]; then
				_tui_cache_refresh_job "${queue[next]}" "$root/g$gen" "$root/req" "$gen " "${sigs[next]}" &
			else
				_tui_cache_warm_worker "${queue[next]}" "$root/g$gen" "$root/req" "$gen " &
			fi
			pids+=($!)
			((running++, next++))
		done
		((gen >= 0 && next >= total && running == 0)) && : >"$root/g$gen/DONE"
		return 0
	}
	while :; do
		if IFS= read -r -t 2 -u "$fd" line; then
			case "$line" in
				QUIT) break ;;
				"REQ "*)
					((${#pids[@]})) && {
						kill "${pids[@]}" 2>/dev/null
						wait "${pids[@]}" 2>/dev/null
					}
					((gen >= 0)) && rm -rf "$root/g$gen" "$root/req.$gen"
					pids=() queue=() sigs=() running=0 next=0
					gen="${line#REQ }"
					IFS= read -r line <"$root/req.$gen"
					IFS=$sep read -ra fields <<<"$line"
					_TERM_SIZE="${fields[0]}" # the workers lay out for the size the request was made at
					for ((i = 1; i < ${#fields[@]}; i += 2)); do
						queue+=("${fields[i]}")
						sigs+=("${fields[i + 1]:-}")
						[[ -n "${fields[i + 1]:-}" ]] || f=1
					done
					total=${#queue[@]}
					mkdir -p "$root/g$gen/cache"
					if ((f && ! prepared)); then # something is built from scratch: its shared inputs are parsed once, here
						prepared=1
						((${TUI_CACHE_LAZY_PREP:-1})) && _tui_cache_warm_prelude "${all[@]}"
					fi
					f=0
					_tcl_launch
					;;
				"DONE "* | "FAILED "*)
					tag="${line#* }"
					[[ "${tag%% *}" == "$gen" ]] || continue # a cancelled request's worker
					((running--))
					_tcl_launch
					;;
			esac
		else
			kill -0 "$owner" 2>/dev/null || {
				((${#pids[@]})) && kill "${pids[@]}" 2>/dev/null
				rm -rf "$root" # the app died without stopping the pool
				exit 0
			}
		fi
	done
	((${#pids[@]})) && kill "${pids[@]}" 2>/dev/null
	exit 0
}

# _tui_cache_lazy.start PAGE... - forks the pool driver for the app's pages, before the terminal is taken over, and
# registers the resize hook that re-fits the cached pages (TUI_CACHE_LAZY_WORKERS workers, 0 = half the cores). It builds
# nothing until _tui_cache_lazy.request.
_tui_cache_lazy.start() {
	(($#)) || return 0
	_tui_mkdtemp _TUI_LAZY_ROOT tui_cache_lazy || return 1
	mkfifo "$_TUI_LAZY_ROOT/req" || return 1
	_TUI_LAZY_ALL=("$@")
	_TUI_LAZY_OWNER="$BASHPID"
	_TUI_LAZY_DISK="$(tui.cache.disk_dir)"
	local max="${TUI_CACHE_LAZY_WORKERS:-0}"
	((max > 0)) || max=$(($(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4) / 2))
	((max < 1)) && max=1
	exec {_TUI_LAZY_FD}<>"$_TUI_LAZY_ROOT/req"
	_tui_cache_lazy.serve "$_TUI_LAZY_ROOT" "$BASHPID" "$max" "$@" &
	_TUI_LAZY_PID=$!
	tui.hook.on resize _tui_cache_lazy.on_resize
}

# _tui_cache_lazy.request PAGE... - the pool builds PAGE... at the current terminal size and drops whatever it was doing.
# A page in _TUI_LAZY_REFRESH is only re-fitted (it has a snapshot already), any other is built from scratch.
# The request line goes into a file (it can exceed what a fifo write keeps whole), the fifo gets only its number.
_tui_cache_lazy.request() {
	local rows cols p sep=$'\x1f' line
	_tui_perf.begin cache_lazy_request
	term.size rows cols
	_TUI_LAZY_PENDING=("$@")
	_TUI_LAZY_GEN+=1
	line="$rows $cols"
	for p; do line+="$sep$p$sep${_TUI_LAZY_REFRESH[$p]:+${_TUI_CACHE_SIG[$p]:-}}"; done
	printf '%s\n' "$line" >"$_TUI_LAZY_ROOT/req.$_TUI_LAZY_GEN"
	printf 'REQ %d\n' "$_TUI_LAZY_GEN" >&"$_TUI_LAZY_FD"
	tui.tick.add _tui_cache_lazy.poll
	_tui_perf.end cache_lazy_request
}

# _tui_cache_lazy.on_resize ROWS COLS - the resize hook: the re-fit is requested once the terminal has been still for
# TUI_CACHE_RESIZE_DEBOUNCE_MS (the drag of a window edge is a burst of sizes, only the last one matters)
_tui_cache_lazy.on_resize() {
	[[ -n "$_TUI_LAZY_PID" ]] && ((TUI_CACHE_RESIZE_DEBOUNCE_MS > 0)) || return 0
	_TUI_LAZY_DEBOUNCE_AT=$((${EPOCHREALTIME//[!0-9]/} + TUI_CACHE_RESIZE_DEBOUNCE_MS * 1000))
	tui.tick.add _tui_cache_lazy.poll
}

# _tui_cache_lazy.refit - requests the pages not fitted to the terminal size, behind the ones still being built from
# scratch (a new request would cancel those): the current page's links first
_tui_cache_lazy.refit() {
	local p i
	local -a build=()
	_TUI_LAZY_DEBOUNCE_AT=0
	for i in "${!_TUI_LAZY_PENDING[@]}"; do
		p="${_TUI_LAZY_PENDING[i]}"
		[[ -n "${_TUI_LAZY_REFRESH[$p]+x}" ]] || build+=("$p")
	done
	_tui_cache_resized "${_TUI_LAZY_ALL[@]}"
	_TUI_LAZY_LATER=("${_TUI_CACHE_RESIZED[@]}")
	for p in "${_TUI_LAZY_LATER[@]}"; do _TUI_LAZY_REFRESH[$p]=1; done
	[[ -n "${_TUI_MARKUP_FILE:-}" ]] && _tui_cache_lazy.order "$_TUI_MARKUP_FILE"
	((${#build[@]} + ${#_TUI_LAZY_LATER[@]})) || return 0
	_tui_cache_lazy.request "${build[@]}" "${_TUI_LAZY_LATER[@]}"
}

# _tui_cache_lazy.poll_one - installs ONE finished snapshot of the current request (input stays responsive); rc 1 when
# there is none. A re-fit replaces the page's geometry and size and is persisted at once; a page built from scratch is
# kept only if the app has not built it meanwhile.
_tui_cache_lazy.poll_one() {
	local i page snap blob size geo undo
	for i in "${!_TUI_LAZY_PENDING[@]}"; do
		page="${_TUI_LAZY_PENDING[i]}"
		snap="$_TUI_LAZY_ROOT/g$_TUI_LAZY_GEN/cache/${page//\//_}"
		if [[ -n "${_TUI_LAZY_REFRESH[$page]+x}" ]]; then snap+=".rsnap"; else snap+=".snap"; fi
		[[ -f "$snap" ]] || continue
		unset "_TUI_LAZY_PENDING[$i]"
		if [[ -n "${_TUI_LAZY_REFRESH[$page]+x}" ]]; then
			# one read splits the four fields: a pattern expansion (${x#*sep}) on a snapshot this size is quadratic
			if [[ -n "${_TUI_CACHE_PAGE[$page]:-}" ]]; then
				_tui_perf.begin cache_refit_install
				IFS=$'\x1e' read -r -d '' size geo undo blob <"$snap"
				_TUI_CACHE_SIZE[$page]="$size"
				_TUI_CACHE_PAGEGEO[$page]="$geo"
				_TUI_CACHE_PAGEUNDO[$page]="$undo"
				_TUI_CACHE_PAGE[$page]="$blob"
				_tui_cache_persist_size "$page"
				_tui_perf.end cache_refit_install
				_tui_perf.count cache_refit
			fi
		elif [[ -z "${_TUI_CACHE_PAGE[$page]:-}" ]]; then
			_tui_cache_slurp "$snap"
			tui.cache.decode "$page" "$_SLURP"
			_TUI_LAZY_BUILT=1
		fi
		return 0
	done
	return 1
}

# _tui_cache_lazy.poll - the tick listener: the debounced re-fit when it is due, else one finished snapshot per call;
# ends the request once the pool is done with it and nothing more is coming.
_tui_cache_lazy.poll() {
	if ((_TUI_LAZY_DEBOUNCE_AT)); then
		((${EPOCHREALTIME//[!0-9]/} >= _TUI_LAZY_DEBOUNCE_AT)) && _tui_cache_lazy.refit
		return 0
	fi
	_tui_cache_lazy.poll_one && return 0
	[[ -f "$_TUI_LAZY_ROOT/g$_TUI_LAZY_GEN/DONE" ]] && _tui_cache_lazy.finish
	return 0
}

# _tui_cache_lazy.announce - once the first page is up: a toast that stays while the pool builds (the app is usable, the
# first visit of a page may be slower) and the cache_building hook. Only for pages built from scratch: a re-fit changes
# nothing the user can see.
_tui_cache_lazy.announce() {
	[[ -n "$_TUI_LAZY_ROOT" ]] || return 0
	((${#_TUI_LAZY_PENDING[@]} > ${#_TUI_LAZY_REFRESH[@]})) || return 0
	tui.notify "Building the page cache in the background (${#_TUI_LAZY_PENDING[@]} pages)..." info 0
	_TUI_LAZY_TOAST="$TUI_NOTIFY_ID"
	tui.hook.fire cache_building
}

# _tui_cache_lazy.finish - the current request is done, and every page that could be built is in memory: persist the pages
# built from scratch; the toast turns into "ready" and the cache_complete hook fires (both skipped when the app is ending).
# The driver stays up for the next resize; without one (nothing started it) the directory goes too.
_tui_cache_lazy.finish() {
	tui.tick.remove _tui_cache_lazy.poll
	((_TUI_LAZY_BUILT)) && tui.cache.dump_dir "$(tui.cache.disk_dir)"
	_TUI_LAZY_BUILT=0 _TUI_LAZY_PENDING=() _TUI_LAZY_REFRESH=()
	if [[ -z "$_TUI_LAZY_PID" ]]; then
		rm -rf "$_TUI_LAZY_ROOT" 2>/dev/null
		_TUI_LAZY_ROOT=""
	fi
	((_TUI_LAZY_QUIET)) && return 0
	[[ -n "$_TUI_LAZY_TOAST" ]] || return 0 # never announced: nothing to turn into "ready"
	tui.notify.clear "$_TUI_LAZY_TOAST"
	_TUI_LAZY_TOAST=""
	tui.notify "Page cache ready" success
	tui.hook.fire cache_complete
}

# _tui_cache_lazy.stop - the app ends: stop the driver (it ends its workers), keep every page already built (decoded and
# persisted like a finished request's), and drop the directory; the rest are built again on the next start. Only the
# process that started the driver acts: its workers inherit these variables and run the same exit path.
_tui_cache_lazy.stop() {
	[[ -n "$_TUI_LAZY_ROOT" && "$_TUI_LAZY_OWNER" == "$BASHPID" ]] || return 0
	if [[ -n "$_TUI_LAZY_PID" ]]; then
		kill "$_TUI_LAZY_PID" 2>/dev/null
		wait "$_TUI_LAZY_PID" 2>/dev/null
	fi
	_TUI_LAZY_QUIET=1
	_TUI_LAZY_DEBOUNCE_AT=0
	while _tui_cache_lazy.poll_one; do :; done
	_TUI_LAZY_PID="" # no driver any more: finish removes the directory
	_tui_cache_lazy.finish
	_TUI_LAZY_QUIET=0
	[[ -n "$_TUI_LAZY_FD" ]] && { exec {_TUI_LAZY_FD}>&-; } 2>/dev/null
	_TUI_LAZY_FD=""
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
	local f
	if [[ -n "$dir" ]]; then
		for f in "$dir"/*.xml; do # globs expand sorted
			[[ -f "$f" && "${f##*/}" != _* ]] && pages+=("$f")
		done
	fi
	for f in "$TUI_DEFAULTS_DIR/pages"/*.xml; do
		[[ -f "$f" && "${f##*/}" != _* ]] && pages+=("$f")
	done

	# every page is checked (all of them are reachable) before the terminal is taken over; the check runs in the background
	# (TUI_VALIDATE_ASYNC) while the first page is prepared and built, and is joined before anything is persisted or started
	_tui_validate.begin "${TUI_VALIDATE_ASYNC:-1}" "${pages[@]}"

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
	_TUI_CACHE_TOTAL=${#pages[@]} _TUI_CACHE_STALE=${#stale[@]} _TUI_CACHE_ON_DISK=$((${#pages[@]} - ${#stale[@]}))
	# measured before any worker forks: they inherit _TERM_SIZE and build every page for this size. Cached pages fitted to
	# another size are re-fitted by the background pool, so they are ready for this terminal when visited.
	local -a resized=()
	local r _sz_rows _sz_cols
	if ((TUI_CACHE_LAZY && _TUI_CACHES)); then
		term.size _sz_rows _sz_cols
		_tui_cache_resized "${pages[@]}"
		resized=("${_TUI_CACHE_RESIZED[@]}")
		for r in "${resized[@]}"; do _TUI_LAZY_REFRESH[$r]=1; done
	fi
	local -a later=()
	if ((${#stale[@]} > 1 && TUI_CACHE_LAZY)); then
		# only the first page is needed for the first frame: it is prepared and built behind the splash, the rest by the
		# background pool (which prepares them too, unless TUI_CACHE_LAZY_PREP is off: then it is done here, for all)
		_tui_path_canon "$file"
		local first_file="$_CANON"
		_tui_cache_lazy.split "$first_file" "${stale[@]}"
		((TUI_CACHE_LAZY_PREP)) || _tui_cache_warm_prelude "${stale[@]}"
		((${#_TUI_LAZY_FIRST[@]})) && tui.cache.warm_with_spinner "${_TUI_LAZY_FIRST[@]}"
		_tui_validate.finish || return 1
		# persisted at once: a quit before the pool is done still leaves the first page warm
		((${#_TUI_LAZY_FIRST[@]})) && tui.cache.dump_dir "$disk_dir"
		_TUI_LAZY_LATER+=("${resized[@]}")
		_tui_cache_lazy.order "$first_file" # the first page is built (or loaded) by now: its links are known
		later=("${_TUI_LAZY_LATER[@]}")
	elif ((${#stale[@]} > 0)); then
		tui.cache.warm_with_spinner "${stale[@]}"
		_tui_validate.finish || return 1
		tui.cache.dump_dir "$disk_dir"
		later=("${resized[@]}")
	else
		later=("${resized[@]}")
	fi
	# the pool driver is forked here, before the terminal is taken over, and stays up: it serves the pages still to build
	# and every later resize
	if ((TUI_CACHE_LAZY && _TUI_CACHES && ${#pages[@]} && (${#later[@]} || TUI_CACHE_RESIZE_DEBOUNCE_MS > 0))); then
		_tui_cache_lazy.start "${pages[@]}"
		((${#later[@]})) && _tui_cache_lazy.request "${later[@]}"
	fi
	_tui_validate.finish || return 1 # nothing to build: the check is joined here (a no-op when already done)
	# every page is now cached and checked against its files: from here on the files are assumed unchanged
	((TUI_CACHE_TRUST)) && _TUI_CACHE_TRUSTED=1

	tui.init
	if ! tui.load_cached "$file"; then
		_master_cleanup
		return 1
	fi
	_tui_store.restore_page
	_tui_store.enter_focus
	_tui_validate.notify
	_tui_cache_lazy.announce
	tui.run
}
