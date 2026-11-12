# debugbar.t.sh - lib/chrome/tui_debugbar.sh: the debug status strip above the footer.

_bar_setup() {
	TUI_DEBUG=1 TUI_DEBUG_CATS="" _TUI_ROWS=24 _TUI_COLS=80 _TUI_FOOTER_ON=0 _TUI_FRAME=""
	_TUI_DBG_PAINTED=""
	tui.debug.reset
}

t_debugbar_off_by_default() {
	eq "0" "$_TUI_DBG_BAR"
}

t_debugbar_on_takes_one_row_from_root_and_off_gives_it_back() {
	_bar_setup
	tui.debug.bar on
	_tui._root_h
	eq "23" "${_TUI_P_H[root]}"
	tui.debug.bar off
	_tui._root_h
	eq "24" "${_TUI_P_H[root]}"
}

t_debugbar_sits_above_the_footer() {
	_bar_setup
	_TUI_FOOTER_ON=1
	tui.debug.bar on
	_tui._root_h
	eq "22" "${_TUI_P_H[root]}"
	_tui_debugbar.draw
	tui.debug.bar off
	ok '[[ "$_TUI_FRAME" == *$'"'"'\e[23;1H'"'"'* ]]'
}

t_debugbar_toggle_flips() {
	_bar_setup
	tui.debug.bar toggle
	eq "1" "$_TUI_DBG_BAR"
	tui.debug.bar toggle
	eq "0" "$_TUI_DBG_BAR"
}

t_debugbar_unchanged_strip_adds_nothing_to_the_frame() {
	_bar_setup
	tui.debug.bar on
	_tui_debugbar.draw
	_TUI_FRAME=""
	_tui_debugbar.draw
	tui.debug.bar off
	eq "" "$_TUI_FRAME"
}

t_debugbar_shows_miss_count_only_when_there_are_misses() {
	_bar_setup
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" != *miss* ]]'
	tui.debug.event cache.page.miss home
	tui.debug.event cache.page.miss p
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"2 miss"* ]]'
}

t_debugbar_shows_the_newest_event_on_the_right() {
	_bar_setup
	tui.debug.event cache.page.miss home
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"cache.page.miss home"* ]]'
}

t_debugbar_segment_toggle_hides_and_shows_it() {
	_bar_setup
	tui.debug.event cache.page.miss home
	tui.debug.segment.toggle miss
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" != *"1 miss"* ]]'
	tui.debug.segment.toggle miss
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"1 miss"* ]]'
}

t_debugbar_custom_segment_renders_its_text() {
	_bar_setup
	_seg_demo() { _DBG_SEG="demo=7"; }
	tui.debug.segment demo _seg_demo left
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"demo=7"* ]]'
}

t_debugbar_never_wider_than_the_terminal() {
	_bar_setup
	_TUI_COLS=30
	tui.debug.event cache.page.miss a_very_long_page_name_that_cannot_fit_at_all
	_tui_debugbar.build
	local plain="${_TUI_DBG_STR//$'\e'\[[0-9;]*m/}"
	ok "((${#plain} <= 30))"
}

t_debugbar_pages_segment_shows_cached_of_total() {
	_bar_setup
	_TUI_CACHE_PAGE=([/a/x.xml]=s [/a/y.xml]=s [/a/_shell.xml]=s) _TUI_CACHE_TOTAL=5
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"pages 2/5"* ]]'
}

t_debugbar_build_segment_counts_pending_builds_and_refits_apart() {
	_bar_setup
	_TUI_LAZY_PENDING=(/a/x.xml /a/y.xml /a/z.xml)
	_TUI_LAZY_REFRESH=([/a/z.xml]=1)
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"building 2"* && "$_TUI_DBG_STR" == *"refit 1"* ]]'
}

t_debugbar_build_segment_is_hidden_when_nothing_is_pending() {
	_bar_setup
	_TUI_LAZY_PENDING=() _TUI_LAZY_REFRESH=()
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" != *building* && "$_TUI_DBG_STR" != *refit* ]]'
}

t_debugbar_visit_segment_shows_the_last_page_load() {
	_bar_setup
	_tui_debug.visit /a/home.xml miss "${EPOCHREALTIME//[!0-9]/}"
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"home miss "* ]]'
}

t_debugbar_prepared_segment_shows_first_visits_that_were_ready() {
	_bar_setup
	local t=${EPOCHREALTIME//[!0-9]/}
	_tui_debug.visit /a/home.xml hit "$t"
	_tui_debug.visit /a/about.xml miss "$t"
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"ready 1/2"* ]]'
}

t_debugbar_boot_segment_is_off_by_default_and_shows_disk_and_stale() {
	_bar_setup
	_TUI_CACHE_TOTAL=8 _TUI_CACHE_ON_DISK=6 _TUI_CACHE_STALE=2
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" != *"disk 6"* ]]'
	tui.debug.segment.toggle boot
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"disk 6"* && "$_TUI_DBG_STR" == *"stale 2"* ]]'
}

t_debugbar_render_segment_shows_zero_ms_once() {
	_bar_setup
	_TUI_PERF_TRACKING=1 _TUI_RENDER_LOG_T=("${EPOCHREALTIME//[!0-9]/}") _TUI_RENDER_LOG_MS=(0)
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"render 0ms "* ]]'
}

t_debugbar_switch_segment_shows_total_switch_time() {
	_bar_setup
	_tui_debug.switch /a/about.xml "${EPOCHREALTIME//[!0-9]/}"
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"switch about "* ]]'
}

t_debugbar_input_segment_shows_the_last_interaction() {
	_bar_setup
	_tui_debug.input_begin "key enter"
	_tui_debug.input_end
	_tui_debugbar.build
	ok '[[ "$_TUI_DBG_STR" == *"input key enter "* ]]'
}

t_debugbar_repaints_itself_when_an_interaction_ends() {
	_bar_setup
	local saved_write
	saved_write="$(declare -f _tui.write)"
	_tui.write() { _WROTE="$1"; }
	_TUI_RUNNING=1 _TUI_DBG_BAR=1 _WROTE=""
	_tui_debug.input_begin "key a"
	_tui_debug.input_end
	_TUI_RUNNING=0 _TUI_DBG_BAR=0
	eval "$saved_write"
	ok '[[ "$_WROTE" == *"input key a "* ]]'
}
