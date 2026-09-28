# cache.t.sh - lib/markup/tui_cache.sh page-load snapshot cache (stage 1.3).
#
# Each test performs at most one real tui.cache.record (the only path that
# actually builds a page - tui.cache.replay just restores a snapshot, no
# build) to stay inside the unit tier's speed budget: a real build pays a
# markup-independent fork cost (one per attribute read across the tag
# handlers it walks, unchanged from the pre-1.2 code) of roughly 80ms even
# for a tiny fixture.

_cache_fixture() { # NAME CONTENT -> writes CONTENT to $_T_ROOT/NAME, returns its path in _CF
	_CF="$_T_ROOT/$1"
	printf '%s' "$2" >"$_CF"
}

t_cache_record_then_valid_then_replay_rebuilds_same_state() {
	_cache_fixture cb.sh 'declare -gi CACHE_SCRIPT_RUNS=$((CACHE_SCRIPT_RUNS + 1))'
	_cache_fixture page.xml '<tui on_visit="cache_test_on_visit"><script src="cb.sh"/><pane id="root" split="v"><pane id="a" weight="1"/><pane id="b" weight="2"/></pane></tui>'
	declare -gi CACHE_SCRIPT_RUNS=0 CACHE_ON_VISIT_RUNS=0
	cache_test_on_visit() { CACHE_ON_VISIT_RUNS=$((CACHE_ON_VISIT_RUNS + 1)); }

	tui.reset_ui
	tui.cache.record "$_CF"
	local weights_before="${_TUI_P_WEIGHTS[root]}"
	eq "1" "$CACHE_SCRIPT_RUNS"
	eq "1" "$CACHE_ON_VISIT_RUNS"
	ok 'tui.cache.valid "$_CF"'

	# replay restores a snapshot - no markup parse, no tag dispatch, no new fork per attribute -
	# but still re-sources <script> and reruns on_visit (both stay live, see tui_cache.sh's header doc).
	tui.reset_ui
	tui.cache.replay "$_CF"
	eq "$weights_before" "${_TUI_P_WEIGHTS[root]}"
	eq "a b" "${_TUI_P_CHILDREN[root]}"
	eq "2" "$CACHE_SCRIPT_RUNS"
	eq "2" "$CACHE_ON_VISIT_RUNS"
}

t_cache_editing_page_invalidates_it() {
	_cache_fixture page.xml '<tui><pane id="root" split="v"><pane id="a" weight="1"/></pane></tui>'
	touch -d '@1000000000' "$_CF"
	tui.reset_ui
	tui.cache.record "$_CF"
	ok 'tui.cache.valid "$_CF"'
	touch -d '@2000000000' "$_CF" # deterministic distinct mtime: no reliance on real elapsed time
	ok '! tui.cache.valid "$_CF"'
}

# Regression test (bug report): (1) `declare -p` prints an untyped scalar as
# `declare -- NAME=…` (no -a/-A/-i) - a blind `${dump//declare -/declare -g}`
# turns that "--" into "-g-" (invalid option); (2) even once that's fixed,
# eval-ing the fixed-up dump through DEEPER function frames than
# tui.cache.replay itself must still land every restored value at global
# scope, not shadow it in some caller's frame; (3) switching pages must
# never leave the root pane at a fraction of the real terminal size - every
# switch reruns _tui_cache_relayout (tui.cache.replay and tui.load both
# do), which recomputes root's H/W from the CURRENT terminal size, not a
# cached one. One record covers all three, to stay inside the unit budget.
_cache_deep_replay_wrapper() { _cache_deeper_replay_wrapper "$@"; }
_cache_deeper_replay_wrapper() { tui.cache.replay "$1"; }

# One record+replay cycle covers three things: (1) a `declare` without -g
# anywhere in the eval-restore chain would shadow a restored value locally
# instead of landing on the real global _TUI_P_CHILDREN/_TUI_CURSOR this
# reads after (driven through two extra function frames, not directly);
# (2) _TUI_CACHE_STATE_REGEX matches every _TUI_P_* array, including
# _TUI_P_W[root]/_TUI_P_H[root] - a cache hit's restore blindly overwrites
# root's own size with whatever it was AT RECORD TIME. _tui._root_h already
# self-healed height (recomputed from the live _TUI_ROWS, not the restored
# value); root width had no equivalent and stayed stuck at the record-time
# terminal width - deterministic, not a race: run the app at any size other
# than whichever one warmed the cache, and every cached page is too narrow
# (or too wide). _tui._root_w (lib/chrome/tui_footer.sh) fixes it the same
# way - proven here by recording at one size and replaying at another.
t_cache_restore_reaches_global_scope_and_root_matches_replay_time_size() {
	_cache_fixture page.xml '<tui><pane id="root" split="h"><pane id="a" weight="1"/><pane id="b" weight="1"/></pane></tui>'
	local real_term_size
	real_term_size="$(declare -f term.size)"
	term.size() {
		printf -v "$1" 24
		printf -v "$2" 80
	} # size when the page's cache was warmed
	tui.reset_ui
	tui.cache.record "$_CF"
	local children_before="${_TUI_P_CHILDREN[root]}" cursor_before=$_TUI_CURSOR
	eq "80" "${_TUI_P_W[root]}"
	eq "24" "${_TUI_P_H[root]}"

	term.size() {
		printf -v "$1" 50
		printf -v "$2" 160
	} # a later run, at a different terminal size
	tui.reset_ui
	# call through two extra function frames, not directly - see (1) above
	_cache_deep_replay_wrapper "$_CF"
	eq "$children_before" "${_TUI_P_CHILDREN[root]}"
	eq "$cursor_before" "$_TUI_CURSOR"
	eq "160" "${_TUI_P_W[root]}" # not 80: replay must not restore the record-time width
	eq "50" "${_TUI_P_H[root]}"
	ok '(( _TUI_P_W[root] != 70 ))' # half of 140 (an earlier reported size) - the exact symptom reported
	eval "$real_term_size"
}
