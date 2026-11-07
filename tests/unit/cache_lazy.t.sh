# cache_lazy.t.sh - lib/markup/tui_cache.sh lazy warm-up: the main loop collects the snapshots a background pool finishes.
# Snapshots are made from hand-set cache entries (no page build), so each test stays cheap.

_lz_snap() { # PAGE PAGE_BODY -> writes PAGE's snapshot into the lazy root, then forgets the entry
	_TUI_CACHE_SIG[$1]="$1=1" _TUI_CACHE_PAGE[$1]="$2"
	printf '%s' "$(tui.cache.encode "$1")" >"$_TUI_LAZY_ROOT/cache/${1//\//_}.snap"
	tui.cache.forget "$1"
}

_lz_setup() { # PAGE... -> an empty lazy root with PAGE... pending
	_TUI_LAZY_ROOT="$_T_ROOT/lazy_${RANDOM}${RANDOM}"
	mkdir -p "$_TUI_LAZY_ROOT/cache"
	_TUI_LAZY_PENDING=("$@")
	_TUI_LAZY_PID=""
	_TUI_LAZY_OWNER="$BASHPID"
	tui.tick.add _tui_cache_lazy.poll
}

ti_cache_lazy_poll_loads_one_finished_snapshot_per_call() {
	_t_needs_caches || return 0
	_lz_setup /x/a.xml /x/b.xml /x/c.xml
	_lz_snap /x/a.xml body_a
	_lz_snap /x/b.xml body_b
	_tui_cache_lazy.poll
	eq "body_a" "${_TUI_CACHE_PAGE[/x/a.xml]:-}"
	eq "" "${_TUI_CACHE_PAGE[/x/b.xml]:-}"
	eq "/x/b.xml /x/c.xml" "${_TUI_LAZY_PENDING[*]}"
	_tui_cache_lazy.poll
	eq "body_b" "${_TUI_CACHE_PAGE[/x/b.xml]:-}"
	eq "/x/c.xml" "${_TUI_LAZY_PENDING[*]}"
	rm -rf "$_TUI_LAZY_ROOT"
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=()
	tui.tick.remove _tui_cache_lazy.poll
}

ti_cache_lazy_poll_keeps_a_page_built_in_this_shell_meanwhile() {
	_t_needs_caches || return 0
	_lz_setup /x/a.xml
	_lz_snap /x/a.xml from_worker
	_TUI_CACHE_SIG[/x/a.xml]="/x/a.xml=2" _TUI_CACHE_PAGE[/x/a.xml]="built_on_visit"
	_tui_cache_lazy.poll
	eq "built_on_visit" "${_TUI_CACHE_PAGE[/x/a.xml]}"
	eq "0" "${#_TUI_LAZY_PENDING[@]}"
	tui.cache.forget /x/a.xml
	rm -rf "$_TUI_LAZY_ROOT"
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=()
	tui.tick.remove _tui_cache_lazy.poll
}

ti_cache_lazy_poll_finishes_when_the_pool_is_done_and_a_page_failed() {
	_t_needs_caches || return 0
	_lz_setup /x/failed.xml
	: >"$_TUI_LAZY_ROOT/DONE"
	local root="$_TUI_LAZY_ROOT"
	_tui_cache_lazy.poll
	eq "" "$_TUI_LAZY_ROOT"
	eq "0" "${#_TUI_LAZY_PENDING[@]}"
	[[ ! -d "$root" ]]
	eq "0" "$?"
	local l found=0
	for l in "${_TUI_TICK_LISTENERS[@]}"; do [[ "$l" == _tui_cache_lazy.poll ]] && found=1; done
	eq "0" "$found"
	tui.notify.clear
}

ti_cache_lazy_stop_ends_the_pool_and_removes_its_directory() {
	_t_needs_caches || return 0
	_lz_setup /x/a.xml
	local root="$_TUI_LAZY_ROOT"
	(sleep 30) &
	_TUI_LAZY_PID=$!
	_tui_cache_lazy.stop
	eq "" "$_TUI_LAZY_ROOT"
	[[ ! -d "$root" ]]
	eq "0" "$?"
	kill -0 "$_TUI_LAZY_PID" 2>/dev/null
	eq "1" "$?"
}

ti_cache_lazy_stop_does_nothing_in_a_process_that_did_not_start_the_pool() {
	_t_needs_caches || return 0
	_lz_setup /x/a.xml
	_TUI_LAZY_OWNER=1 # a forked worker inherits the pool's variables but is not its owner
	_tui_cache_lazy.stop
	[[ -d "$_TUI_LAZY_ROOT" ]]
	eq "0" "$?"
	rm -rf "$_TUI_LAZY_ROOT"
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=() _TUI_LAZY_OWNER=""
	tui.tick.remove _tui_cache_lazy.poll
}

ti_cache_lazy_stop_keeps_the_pages_finished_so_far_on_disk() {
	_t_needs_caches || return 0
	_lz_setup /x/done.xml /x/unfinished.xml
	_lz_snap /x/done.xml body_done
	_tui_cache_lazy.stop
	local dir
	dir="$(tui.cache.disk_dir)"
	eq "body_done" "$(<"$dir/_x_done.xml.cache")"
	[[ -e "$dir/_x_unfinished.xml.cache" ]]
	eq "1" "$?"
	rm -rf "$dir"
	tui.cache.forget /x/done.xml
}

_lz_hook() { _LZ_EVENTS+="$1 "; }

ti_cache_lazy_announce_shows_a_toast_and_fires_cache_building() {
	_t_needs_caches || return 0
	_lz_setup /x/a.xml /x/b.xml
	_LZ_EVENTS=""
	tui.hook.on cache_building _lz_hook
	_tui_cache_lazy.announce
	tui.hook.off cache_building _lz_hook
	eq "1" "$(tui.notify.count)"
	eq "$TUI_NOTIFY_ID" "$_TUI_LAZY_TOAST"
	eq "1" "$((${#_LZ_EVENTS} > 0))"
	tui.notify.clear
	rm -rf "$_TUI_LAZY_ROOT"
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=()
	tui.tick.remove _tui_cache_lazy.poll
}

ti_cache_lazy_finish_swaps_the_toast_and_fires_cache_complete() {
	_t_needs_caches || return 0
	_lz_setup /x/a.xml
	_tui_cache_lazy.announce
	local building="$_TUI_LAZY_TOAST"
	: >"$_TUI_LAZY_ROOT/DONE"
	_LZ_EVENTS=""
	tui.hook.on cache_complete _lz_hook
	_tui_cache_lazy.poll
	tui.hook.off cache_complete _lz_hook
	eq "1" "$(tui.notify.count)" # the "building" toast is gone, "ready" is shown
	eq "0" "$((_TST_ID[0] == building))"
	eq "1" "$((${#_LZ_EVENTS} > 0))"
	tui.notify.clear
}

ti_cache_lazy_stop_is_silent() {
	_t_needs_caches || return 0
	_lz_setup /x/a.xml
	_LZ_EVENTS=""
	tui.hook.on cache_complete _lz_hook
	_tui_cache_lazy.stop
	tui.hook.off cache_complete _lz_hook
	eq "0" "$(tui.notify.count)"
	eq "" "$_LZ_EVENTS"
}

ti_cache_warm_prelude_loads_each_theme_file_once() {
	_t_needs_caches || return 0
	local d="$_T_ROOT/prelude_${RANDOM}${RANDOM}"
	mkdir -p "$d/a" "$d/b" "$d/defaults"
	: >"$d/a/theme.css"
	: >"$d/b/theme.css"
	: >"$d/defaults/theme.css"
	local saved_defaults="$TUI_DEFAULTS_DIR"
	TUI_DEFAULTS_DIR="$d/defaults"
	_LZ_THEMES=()
	local saved_fns
	saved_fns="$(declare -f tui.load_theme _tui_shell.warm)"
	tui.load_theme() { _LZ_THEMES+=("${1#"$d"/}"); }
	_tui_shell.warm() { :; }
	_tui_cache_warm_prelude "$d/a/p1.xml" "$d/a/p2.xml" "$d/b/p3.xml" "$d/a/p3.xml" "$d/defaults/p4.xml"
	eval "$saved_fns"
	eq "defaults/theme.css a/theme.css b/theme.css" "${_LZ_THEMES[*]}"
	TUI_DEFAULTS_DIR="$saved_defaults"
}

ti_cache_lazy_split_puts_the_first_page_in_front_and_the_rest_behind() {
	_tui_cache_lazy.split /x/b.xml /x/a.xml /x/b.xml /x/c.xml
	eq "/x/b.xml" "${_TUI_LAZY_FIRST[*]}"
	eq "/x/a.xml /x/c.xml" "${_TUI_LAZY_LATER[*]}"
}

ti_cache_lazy_split_without_a_stale_first_page_sends_everything_behind() {
	_tui_cache_lazy.split /x/b.xml /x/a.xml /x/c.xml
	eq "" "${_TUI_LAZY_FIRST[*]}"
	eq "/x/a.xml /x/c.xml" "${_TUI_LAZY_LATER[*]}"
}

_lz_start_with_prep() { # PREP -> the pid that ran the pool's prelude (empty when none did) in _LZ_PREP_PID
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=()
	_LZ_MARK="$_T_ROOT/prep_mark_${RANDOM}${RANDOM}"
	local saved_fns
	saved_fns="$(declare -f _tui_cache_warm_prelude _tui_cache_warm_worker)"
	_tui_cache_warm_prelude() { printf '%s' "$BASHPID" >"$_LZ_MARK"; }
	_tui_cache_warm_worker() { :; }
	TUI_CACHE_LAZY_PREP="$1" TUI_CACHE_LAZY_NICE=0 _tui_cache_lazy.start /x/a.xml
	wait "$_TUI_LAZY_PID" 2>/dev/null
	_LZ_PREP_PID=""
	[[ -f "$_LZ_MARK" ]] && _LZ_PREP_PID="$(<"$_LZ_MARK")"
	eval "$saved_fns"
	rm -rf "$_TUI_LAZY_ROOT" "$_LZ_MARK"
	tui.tick.remove _tui_cache_lazy.poll
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=() _TUI_LAZY_PID=""
}

ti_cache_lazy_pool_driver_prepares_the_later_pages_when_prep_is_on() {
	_lz_start_with_prep 1
	eq "1" "$((${_LZ_PREP_PID:-0} > 0 && ${_LZ_PREP_PID:-0} != BASHPID))"
}

ti_cache_lazy_pool_driver_leaves_the_prep_to_the_caller_when_prep_is_off() {
	_lz_start_with_prep 0
	eq "" "$_LZ_PREP_PID"
}

_lz_goto() { printf '_tui_cache_define_goto %q %q %q\n' "$1" "$2" "$3"; }

ti_cache_lazy_order_builds_the_pages_the_first_page_links_to_first_in_link_order() {
	_TUI_CACHE_GOTOS[/x/a.xml]="$(_lz_goto f1 form.xml Form)
$(_lz_goto f2 /x/data.xml Data)
$(_lz_goto f3 ./layout.xml Layout)"
	_TUI_LAZY_LATER=(/x/data.xml /x/extra.xml /x/form.xml /x/layout.xml /x/other.xml)
	_tui_cache_lazy.order /x/a.xml
	eq "/x/form.xml /x/data.xml /x/layout.xml /x/extra.xml /x/other.xml" "${_TUI_LAZY_LATER[*]}"
	unset '_TUI_CACHE_GOTOS[/x/a.xml]'
}

ti_cache_lazy_order_also_reads_the_links_of_the_pages_shell() {
	_TUI_CACHE_SHELL[/x/a.xml]=/x/_shell.xml
	_TUI_CACHE_GOTOS[/x/_shell.xml]="$(_lz_goto s1 z.xml Z)
$(_lz_goto s2 y.xml Y)"
	_TUI_LAZY_LATER=(/x/y.xml /x/z.xml /x/m.xml)
	_tui_cache_lazy.order /x/a.xml
	eq "/x/z.xml /x/y.xml /x/m.xml" "${_TUI_LAZY_LATER[*]}"
	unset '_TUI_CACHE_SHELL[/x/a.xml]' '_TUI_CACHE_GOTOS[/x/_shell.xml]'
}

ti_cache_lazy_order_keeps_the_order_when_the_first_page_links_nowhere_in_the_list() {
	_TUI_CACHE_GOTOS[/x/a.xml]="$(_lz_goto f1 gone.xml Gone)"
	_TUI_LAZY_LATER=(/x/c.xml /x/b.xml)
	_tui_cache_lazy.order /x/a.xml
	eq "/x/c.xml /x/b.xml" "${_TUI_LAZY_LATER[*]}"
	_TUI_LAZY_LATER=(/x/c.xml /x/b.xml)
	_tui_cache_lazy.order /x/unknown.xml
	eq "/x/c.xml /x/b.xml" "${_TUI_LAZY_LATER[*]}"
	unset '_TUI_CACHE_GOTOS[/x/a.xml]'
}
