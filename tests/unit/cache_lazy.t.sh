# cache_lazy.t.sh - lib/markup/tui_cache.sh lazy warm-up: the main loop collects the snapshots a background pool finishes.
# Snapshots are made from hand-set cache entries (no page build), so each test stays cheap.

_lz_snap() { # PAGE PAGE_BODY -> writes PAGE's snapshot into the lazy root, then forgets the entry
	_TUI_CACHE_SIG[$1]="$1=1" _TUI_CACHE_PAGE[$1]="$2"
	printf '%s' "$(tui.cache.encode "$1")" >"$_TUI_LAZY_ROOT/g0/cache/${1//\//_}.snap"
	tui.cache.forget "$1"
}

_lz_setup() { # PAGE... -> an empty lazy root with PAGE... pending
	_TUI_LAZY_ROOT="$_T_ROOT/lazy_${RANDOM}${RANDOM}"
	mkdir -p "$_TUI_LAZY_ROOT/g0/cache"
	_TUI_LAZY_GEN=0 _TUI_LAZY_REFRESH=()
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
	: >"$_TUI_LAZY_ROOT/g0/DONE"
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
	[[ -e "$dir/_x_done.xml.page" ]]
	eq "0" "$?"
	[[ -e "$dir/_x_unfinished.xml.page" ]]
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
	: >"$_TUI_LAZY_ROOT/g0/DONE"
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
	_tui_cache_warm_worker() { printf 'DONE %s%s\n' "$4" "$1" >>"$3"; }
	_TERM_SIZE="24 80"
	TUI_CACHE_LAZY_PREP="$1" TUI_CACHE_LAZY_NICE=0 _tui_cache_lazy.start /x/a.xml
	_tui_cache_lazy.request /x/a.xml
	local n=0
	while [[ ! -f "$_TUI_LAZY_ROOT/g$_TUI_LAZY_GEN/DONE" ]] && ((n++ < 100)); do read -rt 0.05 <> <(:); done
	_LZ_PREP_PID=""
	[[ -f "$_LZ_MARK" ]] && _LZ_PREP_PID="$(<"$_LZ_MARK")"
	eval "$saved_fns"
	_TUI_LAZY_QUIET=1
	_tui_cache_lazy.stop
	_TUI_LAZY_QUIET=0
	rm -f "$_LZ_MARK"
	_TERM_SIZE=""
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

ti_cache_size_is_recorded_encoded_and_compared_with_the_terminal() {
	_t_needs_caches || return 0
	_TERM_SIZE="30 100"
	_TUI_CACHE_SIG[/x/s.xml]="/x/s.xml=1" _TUI_CACHE_PAGE[/x/s.xml]=body _TUI_CACHE_SIZE[/x/s.xml]="30 100"
	tui.cache.is_sized /x/s.xml
	eq "0" "$?"
	local blob
	blob="$(tui.cache.encode /x/s.xml)"
	tui.cache.forget /x/s.xml
	eq "" "${_TUI_CACHE_SIZE[/x/s.xml]:-}"
	tui.cache.decode /x/s.xml "$blob"
	eq "30 100" "${_TUI_CACHE_SIZE[/x/s.xml]}"
	_TERM_SIZE="24 80"
	tui.cache.is_sized /x/s.xml
	eq "1" "$?"
	tui.cache.forget /x/s.xml
	_TERM_SIZE=""
}

ti_cache_size_survives_the_disk_cache() {
	_t_needs_caches || return 0
	_TUI_CACHE_SIG[/x/d.xml]="/x/d.xml=0" _TUI_CACHE_PAGE[/x/d.xml]=body _TUI_CACHE_SIZE[/x/d.xml]="40 120"
	local dir="$_T_ROOT/sizedir${RANDOM}"
	tui.cache.dump_dir "$dir"
	tui.cache.forget /x/d.xml
	tui.cache.load_dir "$dir"
	_TUI_CACHE_MTIME_FRESH=0 _TUI_CACHE_MTIME=() # load_dir leaves its stat table for tui.cache.valid: not for the next test
	eq "40 120" "${_TUI_CACHE_SIZE[/x/d.xml]:-}"
	tui.cache.forget /x/d.xml
}

_lz_teardown() {
	[[ -n "$_TUI_LAZY_FD" ]] && { exec {_TUI_LAZY_FD}>&-; } 2>/dev/null
	rm -rf "$_TUI_LAZY_ROOT"
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=() _TUI_LAZY_REFRESH=() _TUI_LAZY_ALL=() _TUI_LAZY_PID="" _TUI_LAZY_FD="" _TUI_LAZY_DEBOUNCE_AT=0
	tui.tick.remove _tui_cache_lazy.poll
}

ti_cache_lazy_poll_installs_a_refit_geometry_and_size_only() {
	_t_needs_caches || return 0
	_lz_setup /x/r.xml
	_TUI_CACHE_SIG[/x/r.xml]="/x/r.xml=1" _TUI_CACHE_PAGE[/x/r.xml]="old_size" _TUI_CACHE_SCRIPTS[/x/r.xml]="keep.sh"
	_TUI_LAZY_REFRESH[/x/r.xml]=1
	printf '50 160\x1egeo\x1eundo\x1efresh_size' >"$_TUI_LAZY_ROOT/g0/cache/_x_r.xml.snap" # a full snapshot is not what a refit waits for
	_tui_cache_lazy.poll
	eq "old_size" "${_TUI_CACHE_PAGE[/x/r.xml]}"
	printf '50 160\x1egeo\x1eundo\x1efresh_size' >"$_TUI_LAZY_ROOT/g0/cache/_x_r.xml.rsnap"
	_tui_cache_lazy.poll
	eq "fresh_size" "${_TUI_CACHE_PAGE[/x/r.xml]}"
	eq "50 160" "${_TUI_CACHE_SIZE[/x/r.xml]}"
	eq "geo" "${_TUI_CACHE_PAGEGEO[/x/r.xml]}"
	eq "undo" "${_TUI_CACHE_PAGEUNDO[/x/r.xml]}"
	eq "keep.sh" "${_TUI_CACHE_SCRIPTS[/x/r.xml]}"
	eq "0" "${#_TUI_LAZY_PENDING[@]}"
	tui.cache.forget /x/r.xml
	_lz_teardown
}

ti_cache_lazy_resize_is_debounced_then_requests_the_unfitted_pages() {
	_t_needs_caches || return 0
	_lz_setup
	_TERM_SIZE="50 160"
	_TUI_LAZY_ALL=(/x/a.xml /x/b.xml /x/s.xml)
	_TUI_CACHE_SIG[/x/a.xml]="/x/a.xml=1" _TUI_CACHE_PAGE[/x/a.xml]=pa _TUI_CACHE_SIZE[/x/a.xml]="24 80"
	_TUI_CACHE_SIG[/x/b.xml]="/x/b.xml=1" _TUI_CACHE_PAGE[/x/b.xml]=pb _TUI_CACHE_SIZE[/x/b.xml]="50 160"
	_TUI_CACHE_SIG[/x/s.xml]="/x/s.xml=1" _TUI_CACHE_PAGE[/x/s.xml]=ps _TUI_CACHE_SHELL[/x/s.xml]=/x/shell.xml
	exec {_TUI_LAZY_FD}>"$_TUI_LAZY_ROOT/req"
	_TUI_LAZY_PID=1
	_tui_cache_lazy.on_resize 50 160
	ok '((_TUI_LAZY_DEBOUNCE_AT > ${EPOCHREALTIME//[!0-9]/}))'
	_tui_cache_lazy.poll
	eq "0" "${_TUI_LAZY_GEN}" # not due yet: nothing requested
	_TUI_LAZY_DEBOUNCE_AT=1
	_tui_cache_lazy.poll
	eq "1" "${_TUI_LAZY_GEN}"
	eq "/x/a.xml /x/s.xml" "${_TUI_LAZY_PENDING[*]}"
	eq "0" "${_TUI_LAZY_DEBOUNCE_AT}"
	local line sep=$'\x1f'
	IFS= read -r line <"$_TUI_LAZY_ROOT/req.1"
	eq "50 160${sep}/x/a.xml${sep}/x/a.xml=1${sep}/x/s.xml${sep}/x/s.xml=1" "$line"
	eq "REQ 1" "$(<"$_TUI_LAZY_ROOT/req")"
	local p
	for p in a b s; do tui.cache.forget /x/$p.xml; done
	_TERM_SIZE=""
	_lz_teardown
}

ti_cache_lazy_a_newer_request_keeps_pages_still_built_from_scratch() {
	_t_needs_caches || return 0
	_lz_setup /x/new.xml
	_TERM_SIZE="50 160"
	_TUI_LAZY_ALL=(/x/new.xml /x/a.xml)
	_TUI_CACHE_SIG[/x/a.xml]="/x/a.xml=1" _TUI_CACHE_PAGE[/x/a.xml]=pa _TUI_CACHE_SIZE[/x/a.xml]="24 80"
	exec {_TUI_LAZY_FD}>"$_TUI_LAZY_ROOT/req"
	_TUI_LAZY_DEBOUNCE_AT=1
	_tui_cache_lazy.poll
	eq "/x/new.xml /x/a.xml" "${_TUI_LAZY_PENDING[*]}"
	local line sep=$'\x1f'
	IFS= read -r line <"$_TUI_LAZY_ROOT/req.1"
	eq "50 160${sep}/x/new.xml${sep}${sep}/x/a.xml${sep}/x/a.xml=1" "$line" # no signature: built from scratch
	tui.cache.forget /x/a.xml
	_TERM_SIZE=""
	_lz_teardown
}

ti_cache_lazy_driver_refits_a_page_to_the_new_size() {
	_t_needs_caches || return 0
	_cache_fixture page.xml '<tui><pane id="root" split="h"><pane id="a" weight="1"/><pane id="b" weight="1"/></pane></tui>'
	tui.reset_ui
	tui.cache.record "$_CF"
	eq "24 80" "${_TUI_CACHE_SIZE[$_CF]}"
	_TERM_SIZE="50 160"
	_tui_cache_lazy.start "$_CF"
	_TUI_LAZY_REFRESH[$_CF]=1
	_tui_cache_lazy.request "$_CF"
	local n=0
	while ((${#_TUI_LAZY_PENDING[@]} && n++ < 200)); do
		_tui_cache_lazy.poll
		read -rt 0.05 <> <(:)
	done
	eq "50 160" "${_TUI_CACHE_SIZE[$_CF]}"
	[[ "${_TUI_CACHE_PAGE[$_CF]}" == *'_TUI_SNAP_SIZE="50 160 '* ]]
	eq "0" "$?"
	tui.tick.remove _tui_cache_lazy.poll
	_TUI_LAZY_QUIET=1
	_tui_cache_lazy.stop
	_TUI_LAZY_QUIET=0
	eq "" "$_TUI_LAZY_ROOT"
	tui.cache.forget "$_CF"
	_TERM_SIZE=""
}

ti_cache_lazy_refresh_of_resized_pages_is_silent() {
	_t_needs_caches || return 0
	_lz_setup /x/r.xml
	_TUI_LAZY_REFRESH[/x/r.xml]=1
	_TUI_LAZY_TOAST=""
	_tui_cache_lazy.announce
	eq "" "$_TUI_LAZY_TOAST"
	rm -rf "$_TUI_LAZY_ROOT"
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=() _TUI_LAZY_REFRESH=()
	tui.tick.remove _tui_cache_lazy.poll
}

ti_cache_resized_lists_valid_pages_laid_out_for_another_size() {
	_t_needs_caches || return 0
	_TERM_SIZE="30 100"
	_TUI_CACHE_SIG[/x/a.xml]="" _TUI_CACHE_PAGE[/x/a.xml]=b _TUI_CACHE_SIZE[/x/a.xml]="30 100"
	_TUI_CACHE_SIG[/x/b.xml]="" _TUI_CACHE_PAGE[/x/b.xml]=b _TUI_CACHE_SIZE[/x/b.xml]="24 80"
	_TUI_CACHE_SIG[/x/c.xml]="" _TUI_CACHE_PAGE[/x/c.xml]=b
	_tui_cache_resized /x/a.xml /x/b.xml /x/c.xml /x/missing.xml
	eq "/x/b.xml /x/c.xml" "${_TUI_CACHE_RESIZED[*]}"
	tui.cache.forget /x/a.xml; tui.cache.forget /x/b.xml; tui.cache.forget /x/c.xml
	_TERM_SIZE=""
}

ti_cache_lazy_resize_refit_is_off_with_a_zero_debounce() {
	_t_needs_caches || return 0
	_TUI_LAZY_PID=1 _TUI_LAZY_DEBOUNCE_AT=0
	TUI_CACHE_RESIZE_DEBOUNCE_MS=0 _tui_cache_lazy.on_resize 50 160
	eq "0" "$_TUI_LAZY_DEBOUNCE_AT"
	_TUI_LAZY_PID=""
}

# ── one file per page on disk ─────────────────────────────────────────────

_dp_fill() { # KEY -> a cache entry with every field set, a newline in the snapshot and empty fields in between
	_TUI_CACHE_SIG[$1]=";" _TUI_CACHE_PAGE[$1]=$'line one\nline two "quoted" \\ back'
	_TUI_CACHE_SCRIPTS[$1]="a.sh b.sh" _TUI_CACHE_ON_VISIT[$1]="" _TUI_CACHE_GOTOS[$1]=$'g1\ng2'
	_TUI_CACHE_THEME[$1]="/t/theme.css" _TUI_CACHE_CLASSES[$1]=$'id\tcls' _TUI_CACHE_SHELL[$1]=""
	_TUI_CACHE_PAGEGEO[$1]="7 31 42 128" _TUI_CACHE_PAGEUNDO[$1]="u=1" _TUI_CACHE_SIZE[$1]="40 120"
}

ti_cache_dump_dir_writes_one_file_per_page_and_load_dir_restores_every_field() {
	_t_needs_caches || return 0
	_dp_fill /x/one.xml
	_dp_fill /x/two.xml
	local dir="$_T_ROOT/pagesdir${RANDOM}" f want got
	tui.cache.dump_dir "$dir"
	eq "1" "$(compgen -G "$dir/_x_one.xml*" | wc -l)" # not twelve
	[[ -f "$dir/_x_one.xml.page" && -f "$dir/_x_two.xml.page" ]]
	eq "0" "$?"
	for f in SIG PAGE SCRIPTS ON_VISIT GOTOS THEME CLASSES SHELL PAGEGEO PAGEUNDO SIZE; do
		local -n _m="_TUI_CACHE_$f"
		want+="$f=${_m[/x/one.xml]}|"
		unset -n _m
	done
	tui.cache.forget /x/one.xml
	tui.cache.forget /x/two.xml
	tui.cache.load_dir "$dir"
	_TUI_CACHE_MTIME_FRESH=0 _TUI_CACHE_MTIME=() # load_dir leaves its stat table for tui.cache.valid: not for the next test
	for f in SIG PAGE SCRIPTS ON_VISIT GOTOS THEME CLASSES SHELL PAGEGEO PAGEUNDO SIZE; do
		local -n _m="_TUI_CACHE_$f"
		got+="$f=${_m[/x/one.xml]}|"
		unset -n _m
	done
	eq "$want" "$got"
	eq "40 120" "${_TUI_CACHE_SIZE[/x/two.xml]}"
	tui.cache.forget /x/one.xml
	tui.cache.forget /x/two.xml
}

ti_cache_load_dir_ignores_a_page_file_that_was_not_written_whole() {
	_t_needs_caches || return 0
	_dp_fill /x/cut.xml
	local dir="$_T_ROOT/pagesdir${RANDOM}" whole
	tui.cache.dump_dir "$dir"
	IFS= read -r -d '' whole <"$dir/_x_cut.xml.page"
	printf '%s' "${whole:0:${#whole}-6}" >"$dir/_x_cut.xml.page" # a writer that stopped before its end marker
	tui.cache.forget /x/cut.xml
	tui.cache.load_dir "$dir"
	_TUI_CACHE_MTIME_FRESH=0 _TUI_CACHE_MTIME=() # load_dir leaves its stat table for tui.cache.valid: not for the next test
	eq "" "${_TUI_CACHE_PAGE[/x/cut.xml]:-}"
}

ti_cache_load_dir_removes_the_files_of_the_old_layout_once() {
	_t_needs_caches || return 0
	local dir="$_T_ROOT/pagesdir${RANDOM}" ext
	mkdir -p "$dir"
	for ext in key cache sig scripts onvisit gotos theme classes shell pageundo pagegeo size; do printf x >"$dir/_x_old.xml.$ext"; done
	tui.cache.load_dir "$dir"
	_TUI_CACHE_MTIME_FRESH=0 _TUI_CACHE_MTIME=() # load_dir leaves its stat table for tui.cache.valid: not for the next test
	eq "" "$(compgen -G "$dir/*")" # nothing is left in it
	eq "" "${_TUI_CACHE_PAGE[/x/old.xml]:-}"
}

ti_cache_a_refit_is_written_into_the_page_file_and_read_back_by_a_worker() {
	_t_needs_caches || return 0
	_dp_fill /x/rf.xml
	local dir="$_T_ROOT/pagesdir${RANDOM}"
	tui.cache.dump_dir "$dir"
	_TUI_LAZY_DISK="$dir"
	_TUI_CACHE_PAGE[/x/rf.xml]="refitted" _TUI_CACHE_SIZE[/x/rf.xml]="50 160" _TUI_CACHE_PAGEGEO[/x/rf.xml]="1 2 3 4"
	_tui_cache_persist_size /x/rf.xml
	local sig="${_TUI_CACHE_SIG[/x/rf.xml]}"
	tui.cache.forget /x/rf.xml
	TUI_HOME="$_T_ROOT/nohome" # the disk copy is found through tui.cache.disk_dir
	mkdir -p "$TUI_HOME/cache"
	ln -s "$dir" "$TUI_HOME/cache/pages"
	_tui_cache_base_load /x/rf.xml "$sig"
	eq "0" "$?"
	eq "refitted" "${_TUI_CACHE_PAGE[/x/rf.xml]}"
	_tui_cache_base_load /x/rf.xml "other-signature"
	eq "1" "$?"
	tui.cache.forget /x/rf.xml
	_TUI_LAZY_DISK=""
}
