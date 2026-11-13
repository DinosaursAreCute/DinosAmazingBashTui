# shell.t.sh - lib/markup/tui_shell.sh: pages of one shell swap inside its outlet; the shell stays (stage 3D-3).
# Builds real pages, so every case is ti_.

_sh_pages() { # DIR - one shell, two pages of it, one page without a shell
	local d="$1"
	mkdir -p "$d"
	cat >"$d/_shell.xml" <<'XML'
<tui>
  <pane id="root" split="v">
    <pane id="head" border="single" weight="1">
      <input id="search" placeholder="s"/>
    </pane>
    <outlet id="body" weight="4"/>
    <pane id="foot" border="single" weight="1">
      <button id="quit" text="quit"/>
    </pane>
  </pane>
</tui>
XML
	cat >"$d/pa.xml" <<'XML'
<tui shell="_shell.xml">
  <pane id="pa_main" border="single">
    <button id="pa_btn" text="a"/>
    <input id="pa_in" placeholder="x" keep_value="true"/>
  </pane>
</tui>
XML
	cat >"$d/pb.xml" <<'XML'
<tui shell="_shell.xml">
  <pane id="pb_main" border="single">
    <button id="pb_btn" text="b"/>
  </pane>
</tui>
XML
	cat >"$d/pc.xml" <<'XML'
<tui shell="_shell.xml" on_visit="_sh_visit">
  <pane id="pc_main" border="single">
    <button id="pc_btn" text="c"/>
  </pane>
</tui>
XML
	cat >"$d/pf.xml" <<'XML'
<tui shell="_shell.xml">
  <pane id="pf_main" border="single">
    <button id="pf_first" text="1"/>
    <button id="pf_auto" text="2" autofocus="true"/>
  </pane>
</tui>
XML
	cat >"$d/pn.xml" <<'XML'
<tui>
  <pane id="root" border="single">
    <button id="pn_btn" text="n"/>
  </pane>
</tui>
XML
}

_sh_visit() { tui.button vis_btn pc_main 5 "made in on_visit" ""; } # what a page's on_visit does: widgets built after the page

_sh_setup() {
	TUI_HOME="$_T_ROOT/sh_home"
	_TUI_STORE=() _TUI_STORE_DEFAULT=() _TUI_STORE_DEFAULTED=() _TUI_STORE_FILE=() _TUI_STORE_LOADED=1
	tui.reset_ui
	_TUI_MARKUP_FILE=""
	_SHD="$_T_ROOT/sh_pages_${RANDOM}${RANDOM}"
	_sh_pages "$_SHD"
	_TUI_MARKUP_DIR="$_SHD"
	_TUI_ROWS=24 _TUI_COLS=80
}
_sh_go() { tui.goto "$_SHD/$1" >/dev/null 2>>"$_SHD/err"; }

ti_shell_pages_build_into_the_outlet_and_swap_without_touching_the_shell() {
	_sh_setup
	_sh_go pa.xml
	eq "$_SHD/_shell.xml" "$(tui.shell.file)"
	eq "head body foot" "${_TUI_P_CHILDREN[root]}"
	eq "pa_main" "${_TUI_P_CHILDREN[body]}"
	eq "search pa_btn pa_in quit" "${_TUI_W_ORDER[*]}"
	_TUI_W_VALUE[search]="query"
	_TUI_W_VALUE[pa_in]="typed"
	_tui_focus.ensure
	_TUI_FOCUS_ID=search
	_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[search]}"
	_sh_go pb.xml
	eq "pb_main" "${_TUI_P_CHILDREN[body]}"
	eq "query" "${_TUI_W_VALUE[search]}"
	eq search "$_TUI_FOCUS_ID"
	eq "search pb_btn quit" "${_TUI_W_ORDER[*]}"
	ok '[[ -z "${_TUI_W_TYPE[pa_btn]:-}" && -z "${_TUI_P_ROW[pa_main]:-}" ]]'
	_sh_go pa.xml
	eq "pa_main" "${_TUI_P_CHILDREN[body]}"
	eq "search pa_btn pa_in quit" "${_TUI_W_ORDER[*]}"
	eq "typed" "${_TUI_W_VALUE[pa_in]}"
	eq "" "$(<"$_SHD/err")"
}

ti_shell_a_page_widget_marked_autofocus_gets_focus_when_no_shell_widget_keeps_it() {
	_sh_setup
	_sh_go pa.xml
	_sh_go pf.xml
	eq pf_auto "$_TUI_FOCUS_ID"
	_sh_go pb.xml
	eq pb_btn "$_TUI_FOCUS_ID"
}

ti_shell_a_shell_widget_that_had_focus_keeps_it_over_a_pages_autofocus() {
	_sh_setup
	_sh_go pa.xml
	_tui_focus.ensure
	_TUI_FOCUS_ID=search
	_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[search]}"
	_sh_go pf.xml
	eq search "$_TUI_FOCUS_ID"
}

ti_shell_a_page_without_a_shell_rebuilds_from_scratch() {
	_sh_setup
	_sh_go pa.xml
	_sh_go pn.xml
	eq "" "$(tui.shell.file)"
	eq "pn_btn" "${_TUI_W_ORDER[*]}"
	_sh_go pb.xml
	eq "$_SHD/_shell.xml" "$(tui.shell.file)"
	eq "search pb_btn quit" "${_TUI_W_ORDER[*]}"
}

# ── validator ─────────────────────────────────────────────────────────────

# _sh_validate FILE -> _SHV: the findings of one page as "severity message" lines
_sh_validate() {
	tui.validate.files "$1"
	tui.validate.messages
	_SHV="${_TV_LINES[*]}"
}

ti_shell_validator_accepts_a_shell_and_its_pages() {
	_sh_setup
	_sh_validate "$_SHD/pa.xml"
	eq "" "$_SHV"
	_sh_validate "$_SHD/_shell.xml"
	eq "" "$_SHV"
}

ti_shell_validator_reports_a_missing_shell_a_stray_outlet_and_shared_ids() {
	_sh_setup
	printf '<tui shell="nope.xml">\n<pane id="p"/>\n</tui>\n' >"$_SHD/x1.xml"
	_sh_validate "$_SHD/x1.xml"
	match "$_SHV" "cannot be read"
	printf '<tui shell="_shell.xml">\n<outlet id="o2"/>\n</tui>\n' >"$_SHD/x2.xml"
	_sh_validate "$_SHD/x2.xml"
	match "$_SHV" "outlet belongs in the shell file"
	ok '[[ "$_SHV" != *"this one has"* ]]'
	printf '<tui shell="_shell.xml">\n<pane id="head"/>\n</tui>\n' >"$_SHD/x3.xml"
	_sh_validate "$_SHD/x3.xml"
	match "$_SHV" "pane id 'head' is already used"
	printf '<tui>\n<outlet id="o1"/>\n<outlet id="o2"/>\n</tui>\n' >"$_SHD/x4.xml"
	_sh_validate "$_SHD/x4.xml"
	ok '[[ "$_SHV" == *"exactly one <outlet/>"* ]]'
	printf '<tui shell="_shell.xml">\n<pane id="z"/>\n</tui>\n' >"$_SHD/x5.xml"
	printf '<tui shell="x5.xml">\n<pane id="y"/>\n</tui>\n' >"$_SHD/x6.xml"
	_sh_validate "$_SHD/x6.xml"
	match "$_SHV" "cannot name a shell"
}

# ── tui.shell.file / tui.page.refresh ─────────────────────────────────────

t_shell_file_stores_prints_and_reports_through_its_status() {
	local v=x
	_TUI_SHELL_FILE=""
	tui.shell.file v && _t_fail "status 0 without a shell"
	eq "" "$v"
	eq "" "$(tui.shell.file)"
	_TUI_SHELL_FILE="/app/_shell.xml"
	tui.shell.file v
	eq "/app/_shell.xml" "$v"
	eq "/app/_shell.xml" "$(tui.shell.file)"
}

t_shell_page_refresh_hands_a_shell_page_to_a_background_rebuild() {
	local got="" saved
	saved="$(declare -f tui.page.rebuild)"
	tui.page.rebuild() { got="$*"; }
	_TUI_MARKUP_FILE="/app/pa.xml" _TUI_SHELL_FILE="/app/_shell.xml" _TUI_P_RAW=":"
	tui.page.refresh
	eval "$saved"
	eq "--label Updating page... /app/pa.xml" "$got"
}

t_shell_scan_ignores_a_shell_attribute_quoted_in_a_comment() {
	local f="$_T_ROOT/sh_scan.xml"
	printf '<!-- a page opts in with <tui shell="_x.xml"> -->\n<tui>\n<pane id="a"/>\n</tui>\n' >"$f"
	_tui_shell.scan "$f" 1
	eq "" "$_SH_OF"
	printf '<!-- note -->\n<tui shell="_x.xml">\n</tui>\n' >"$f"
	_tui_shell.scan "$f" 1
	eq "$_T_ROOT/_x.xml" "$_SH_OF"
}

ti_shell_widgets_made_in_on_visit_are_neither_doubled_on_replay_nor_left_behind() {
	_sh_setup
	_sh_go pc.xml
	_sh_go pb.xml
	ok '[[ -z "${_TUI_W_TYPE[vis_btn]:-}" ]]'
	_sh_go pc.xml
	_sh_go pb.xml
	_sh_go pc.xml
	local -a hits=()
	local id
	for id in "${_TUI_W_ORDER[@]}"; do [[ "$id" == vis_btn ]] && hits+=("$id"); done
	eq 1 "${#hits[@]}"
	_sh_go pb.xml
	eq "search pb_btn quit" "${_TUI_W_ORDER[*]}"
}

ti_shell_first_goto_from_a_page_without_a_shell_builds_the_shell_and_the_page() {
	_sh_setup
	_sh_go pn.xml
	_sh_go pa.xml
	eq "$_SHD/_shell.xml" "$(tui.shell.file)"
	eq "pa_main" "${_TUI_P_CHILDREN[body]}"
	eq "search pa_btn pa_in quit" "${_TUI_W_ORDER[*]}"
}

ti_shell_demo_pages_but_home_use_the_shell_whose_menu_is_collapsible_and_resizable() {
	local p bad=""
	for p in "$REPO"/share/demo/*.xml; do
		[[ "$p" == @(*/_*|*/commands.xml|*/home.xml) ]] || grep -q 'shell="_shell.xml"' "$p" || bad+="${p##*/} "
	done
	eq "" "$bad"
	tui.reset_ui
	tui.load "$REPO/share/demo/docu.xml" 2>/dev/null
	eq 1 "${_TUI_P_COLLAPSIBLE[nav]:-}"
	eq rail "${_TUI_P_COLLAPSE_TO[nav]:-}"
	eq x "${_TUI_P_RESIZABLE[nav]:-}"
}

ti_shell_pane_collapsed_in_the_shell_keeps_its_state_and_width_when_the_page_reloads() {
	_sh_setup
	cat >"$_SHD/_shell2.xml" <<'XML'
<tui>
  <pane id="root" split="h">
    <pane id="side" weight="20" border="single" collapsible="true" collapse_to="0" keep_collapsed="true">
      <button id="side_btn" text="side"/>
    </pane>
    <outlet id="body2" weight="80"/>
  </pane>
</tui>
XML
	cat >"$_SHD/pz.xml" <<'XML'
<tui shell="_shell2.xml">
  <pane id="pz_main" border="single">
    <button id="pz_btn" text="z"/>
  </pane>
</tui>
XML
	_sh_go pz.xml
	local open_w=${_TUI_P_W[side]}
	tui.collapse side on
	_sh_go pz.xml # same page again: a full reload, the shell is rebuilt
	eq 1 "${_TUI_P_COLLAPSED[side]:-}"
	ok '(( _TUI_P_W[side] < open_w ))' # the geometry follows the restored state, not the first layout
}

ti_shell_leaving_a_page_ends_its_exec_instances_and_frees_their_control_rows() {
	_sh_setup
	cat >"$_SHD/px.xml" <<'XML'
<tui shell="_shell.xml">
  <pane id="px_main" split="v">
    <pane id="px_out" weight="3"/>
    <pane id="px_ctl" weight="1"/>
  </pane>
</tui>
XML
	_sh_go px.xml
	tui.exec "sleep 30" px_out px_ctl
	eq 1 "${#_EXEC_STATUS[@]}"
	_sh_go pa.xml
	eq 0 "${#_EXEC_STATUS[@]}"
	eq 0 "${_EXEC_PANE_CTL_ROW[px_ctl]:-0}" # the next visit's controls start at the top again, not below a ghost cluster
}

ti_shell_exec_started_by_a_page_script_has_one_live_control_cluster_after_a_cached_revisit() {
	_sh_setup
	cat >"$_SHD/pz_init.sh" <<'SH'
tui.exec.cancel_pane pz_out
tui.exec "cat" pz_out pz_ctl
SH
	cat >"$_SHD/pz2.xml" <<'XML'
<tui shell="_shell.xml">
  <pane id="pz_main" split="v">
    <pane id="pz_out" weight="3"/>
    <pane id="pz_ctl" weight="1"/>
  </pane>
  <script src="pz_init.sh"/>
</tui>
XML
	tui.cache.record "$_SHD/pz2.xml" >/dev/null 2>&1
	_sh_go pa.xml
	tui.cache.replay "$_SHD/pz2.xml" >/dev/null 2>&1
	local w n=0 live=0
	for w in "${_TUI_W_ORDER[@]}"; do
		[[ "${_TUI_W_TYPE[$w]:-}" == input ]] || continue
		[[ "$w" == __f_exec_* ]] || continue
		n=$((n + 1))
		[[ -n "${_EXEC_WIDGET_TO_IID[$w]:-}" ]] && live=$((live + 1))
	done
	eq 1 "$n"    # no ghost cluster restored with the snapshot
	eq 1 "$live" # and the one there is wired to a running instance
	tui.exec.cancel_pane pz_out
}

ti_shell_page_layers_leave_with_the_page_and_the_shells_layers_stay() {
	_sh_setup
	cat >"$_SHD/_shell3.xml" <<'XML'
<tui>
  <pane id="root" split="v">
    <outlet id="body3"/>
  </pane>
  <window id="shell_win" x="2" y="2" width="20" height="5" float="true">
    <button id="shell_win_btn" text="s"/>
  </window>
</tui>
XML
	printf '<tui shell="_shell3.xml">\n<pane id="la"/>\n<window id="page_win" x="30" y="3" width="20" height="5">\n<button id="page_win_btn" text="p"/>\n</window>\n</tui>\n' >"$_SHD/la.xml"
	printf '<tui shell="_shell3.xml">\n<pane id="lb"/>\n</tui>\n' >"$_SHD/lb.xml"
	_sh_go la.xml
	eq "shell_win page_win" "${_TUI_L_ORDER[*]}"
	_sh_go lb.xml
	eq "shell_win" "${_TUI_L_ORDER[*]}"
	ok '[[ -z "${_TUI_P_ROW[page_win]:-}" && -z "${_TUI_W_TYPE[page_win_btn]:-}" ]]'
	ok '[[ -n "${_TUI_W_TYPE[shell_win_btn]:-}" ]]'
	_sh_go la.xml
	eq "shell_win page_win" "${_TUI_L_ORDER[*]}"
	eq "page_win" "${_TUI_P_LAYER[page_win]}"
	eq "" "$(<"$_SHD/err")"
}

ti_shell_page_replayed_from_the_cache_still_carries_what_a_refresh_needs() {
	_sh_setup
	_sh_go pa.xml # recorded
	_sh_go pb.xml
	_sh_go pa.xml # replayed from the delta
	ok '[[ -n "$_TUI_P_RAW" && -n "${_TUI_P_SIG_OWN[pa_main]:-}" && -n "$_TUI_P_SIG_TOP" ]]'
	_sh_go pb.xml
	ok '[[ -n "${_TUI_P_SIG_OWN[pb_main]:-}" && -z "${_TUI_P_SIG_OWN[pa_main]:-}" || -n "${_TUI_P_SIG_OWN[pb_main]:-}" ]]'
	eq "" "$(<"$_SHD/err")"
}

# a page of a shell re-fitted by the cache pool equals the page replayed at the new size: same panes, and its recorded
# outlet needs no relayout
ti_shell_a_refit_page_replays_like_a_relayout_at_the_new_size() {
	_t_needs_caches || return 0
	_sh_setup
	local pa="$_SHD/pa.xml" g="$_SHD/gen" sig geo_before h_expected w_expected
	_sh_go pa.xml # recorded at 24x80
	sig="${_TUI_CACHE_SIG[$pa]}"
	_TUI_ROWS=50 _TUI_COLS=160 _TERM_SIZE="50 160"
	_tui._root_w
	_tui._root_h
	tui.reset_ui
	tui.cache.replay "$pa"
	h_expected="${_TUI_P_H[pa_main]}" w_expected="${_TUI_P_W[pa_main]}"
	_tui_shell.geometry
	geo_before="$_SH_GEO"
	mkdir -p "$g/cache"
	(_tui_cache_refresh_job "$pa" "$g" "$g/report" "1 " "$sig")
	eq "DONE 1 $pa" "$(<"$g/report")"
	_TUI_LAZY_ROOT="$_SHD/lazyroot" _TUI_LAZY_GEN=7 _TUI_LAZY_PENDING=("$pa") _TUI_LAZY_REFRESH=([$pa]=1)
	mkdir -p "$_TUI_LAZY_ROOT/g7/cache"
	cp "$g/cache/${pa//\//_}.rsnap" "$_TUI_LAZY_ROOT/g7/cache/"
	_tui_cache_lazy.poll
	eq "50 160" "${_TUI_CACHE_SIZE[$pa]}"
	eq "$geo_before" "${_TUI_CACHE_PAGEGEO[$pa]}"
	tui.reset_ui
	tui.cache.replay "$pa"
	eq "$h_expected $w_expected" "${_TUI_P_H[pa_main]} ${_TUI_P_W[pa_main]}"
	eq "pa_main" "${_TUI_P_CHILDREN[body]}"
	_TUI_LAZY_ROOT="" _TUI_LAZY_PENDING=() _TUI_LAZY_REFRESH=() _TERM_SIZE=""
	tui.tick.remove _tui_cache_lazy.poll
}

# leaving a page twice in a row does the work once: tui.goto leaves the old page, and the replay or the build that follows
# starts by leaving whatever page is there - which is nothing
_sh_count_leaves() { # CMD... -> _SH_LEAVES: how many times CMD ran the full leave (it always ends in _tui_modal.reset)
	_SH_LEAVES=0
	local saved
	saved="$(declare -f _tui_modal.reset)"
	_tui_modal.reset() { ((_SH_LEAVES++)); }
	"$@"
	eval "$saved"
}

ti_shell_leaving_an_already_left_page_does_nothing() {
	_sh_setup
	_sh_go pa.xml
	_sh_count_leaves _tui_shell.leave_page
	eq "1" "$_SH_LEAVES"
	_sh_count_leaves _tui_shell.leave_page
	eq "0" "$_SH_LEAVES"
	_sh_go pb.xml # a page is built again: the next leave is real
	_sh_count_leaves _tui_shell.leave_page
	eq "1" "$_SH_LEAVES"
}

ti_shell_a_goto_between_pages_of_a_shell_leaves_once() {
	_sh_setup
	_sh_go pa.xml
	_sh_go pb.xml # recorded and cached
	_sh_go pa.xml
	_TUI_RUNNING=1
	_sh_count_leaves _sh_go pb.xml
	_TUI_RUNNING=0
	eq "1" "$_SH_LEAVES"
	eq "pb_main" "${_TUI_P_CHILDREN[body]}"
	eq "search pb_btn quit" "${_TUI_W_ORDER[*]}"
}

# the page's ids are synced when something may have changed them, not again right after: a goto between cached pages of
# a shell syncs once before it leaves the page and once after the page's on_visit
ti_shell_a_goto_between_pages_of_a_shell_syncs_the_page_ids_twice() {
	_sh_setup
	_sh_go pa.xml
	_sh_go pb.xml
	_sh_go pa.xml
	_TUI_RUNNING=1
	local saved
	saved="$(declare -f _tui_shell.sync_page_ids)"
	_SH_SYNCS=0
	eval "_real_$saved"
	eval "_real_sync_page_ids() $(declare -f _tui_shell.sync_page_ids | tail -n +2)"
	_tui_shell.sync_page_ids() {
		((_SH_SYNCS++))
		_real_sync_page_ids
	}
	_sh_go pb.xml
	eval "$saved"
	_TUI_RUNNING=0
	eq "2" "$_SH_SYNCS"
	eq "pb_main" "${_TUI_P_CHILDREN[body]}"
}

# a widget made after the page was left is a page widget again: leaving finds it
ti_shell_leaving_sees_a_widget_made_after_the_last_leave() {
	_sh_setup
	_sh_go pa.xml
	_tui_shell.leave_page
	tui.button late_btn body 5 "late" ""
	_tui_shell.leave_page
	ok '[[ -z "${_TUI_W_TYPE[late_btn]:-}" ]]'
}
