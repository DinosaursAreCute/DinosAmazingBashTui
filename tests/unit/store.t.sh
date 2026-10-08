# store.t.sh - page-state store: set/get, save/restore per widget type, collapsed + size, keep_state, reset
# (lib/state/tui_store.sh, stage 3D part 1).

_st_setup() {
	_TUI_STORE=() _TUI_STORE_DEFAULT=() _TUI_STORE_DEFAULTED=() _TUI_STORE_FILE=()
	_TUI_STORE_LOADED=1 _TUI_STORE_DIRTY="" _TUI_STORE_ARMED=""
	_WXSEL=() _WXTOP=() _TXC=() _TXA=() _TXS=() _TXT=() _TUI_CV_ZONES=0
	_TUI_MARKUP_FILE="/app/pa.xml" _TUI_ROWS=24 _TUI_FOCUS_ID="" _TUI_PANE_FOCUS="" _TUI_HZ_EXTRA=()
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=20 _TUI_P_W[root]=80
}
# _st_w ID TYPE - a widget as the builders leave it (no layout, no redraw), which is what a rebuilt page starts from
_st_w() {
	_TUI_W_TYPE[$1]="$2" _TUI_W_VALUE[$1]=""
	unset '_TXC[$1]' '_TXT[$1]' '_TXS[$1]'
	[[ " ${_TUI_W_ORDER[*]} " == *" $1 "* ]] || _TUI_W_ORDER+=("$1")
}
# _st_leave_and_return - what tui.goto A -> B -> A does to the state, minus the build: save, then the page is rebuilt (a
# `rebuild` command re-creates the widgets and panes at their defaults), then restore
_st_leave_and_return() {
	_tui_store.save_page
	"$@"
	_tui_store.restore_page
}

# ── the store ─────────────────────────────────────────────────────────────

t_store_set_get_unset_has() {
	_st_setup
	tui.store.get pa.xml name value && _t_fail "absent key found"
	tui.store.set pa.xml name value hello
	tui.store.get pa.xml name value
	eq hello "$REPLY"
	ok 'tui.store.has pa.xml'
	ok 'tui.store.has pa.xml name'
	ok '! tui.store.has pb.xml'
	ok '! tui.store.has pa.xml other'
	tui.store.set pa.xml name cursor 3
	tui.store.unset pa.xml name cursor
	ok '! tui.store.get pa.xml name cursor'
	tui.store.get pa.xml name value
	eq hello "$REPLY"
	tui.store.unset pa.xml name
	ok '! tui.store.has pa.xml name'
	tui.store.set pa.xml a value 1
	tui.store.set pb.xml a value 2
	tui.store.unset pa.xml
	ok '! tui.store.has pa.xml'
	ok 'tui.store.has pb.xml'
}

t_store_ids_with_a_pipe_do_not_collide() {
	_st_setup
	tui.store.set pa.xml "a|b" value one
	tui.store.set pa.xml a value two
	tui.store.get pa.xml "a|b" value
	eq one "$REPLY"
	tui.store.get pa.xml a value
	eq two "$REPLY"
	tui.store.unset pa.xml a
	ok 'tui.store.has pa.xml "a|b"'
	tui.store.set "p|q.xml" "x%y" value 7
	tui.store.get "p|q.xml" "x%y" value
	eq 7 "$REPLY"
	ok '! tui.store.has "p.xml" "x"'
}

t_store_values_keep_newlines_and_empty() {
	_st_setup
	tui.store.set pa.xml t value $'a\nb'
	tui.store.get pa.xml t value
	eq $'a\nb' "$REPLY"
	tui.store.set pa.xml t cursor ""
	tui.store.get pa.xml t cursor
	eq "" "$REPLY"
}

# ── widgets: save and restore per type ───────────────────────────────────

t_store_input_keeps_value_cursor_and_scroll() {
	_st_setup
	_st_w name input
	_tui_store.build_widget name true ""
	_TUI_W_VALUE[name]="hello" _TXC[name]=3 _TXS[name]=2
	_st_leave_and_return _st_w name input
	eq "hello 3 2" "${_TUI_W_VALUE[name]} ${_TXC[name]} ${_TXS[name]}"
}

t_store_password_keeps_value_and_cursor() {
	_st_setup
	_st_w pw password
	_tui_store.build_widget pw true ""
	_TUI_W_VALUE[pw]="s3cret" _TXC[pw]=6
	_st_leave_and_return _st_w pw password
	eq "s3cret 6" "${_TUI_W_VALUE[pw]} ${_TXC[pw]}"
}

t_store_textarea_keeps_value_cursor_and_scroll() {
	_st_setup
	_st_w notes textarea
	_tui_store.build_widget notes true ""
	_TUI_W_VALUE[notes]=$'one\ntwo\nthree' _TXC[notes]=9 _TXT[notes]=1 _TXS[notes]=0
	_st_leave_and_return _st_w notes textarea
	eq $'one\ntwo\nthree' "${_TUI_W_VALUE[notes]}"
	eq "9 1 0" "${_TXC[notes]} ${_TXT[notes]} ${_TXS[notes]}"
}

t_store_checkbox_keeps_value() {
	_st_setup
	_st_w chk checkbox
	_tui_store.build_widget chk true ""
	_TUI_W_VALUE[chk]=1
	_st_leave_and_return _st_w chk checkbox
	eq 1 "${_TUI_W_VALUE[chk]}"
}

t_store_select_keeps_value_and_selection() {
	_st_setup
	tui.select sel root 0 Pick
	tui.select.set sel a b c
	_tui_store.build_widget sel true ""
	_TUI_W_VALUE[sel]=c _WXSEL[sel]=2
	_st_leave_and_return eval 'tui.select sel root 0 Pick; tui.select.set sel a b c'
	eq "c 2" "${_TUI_W_VALUE[sel]} ${_WXSEL[sel]}"
}

t_store_list_keeps_selection_and_scroll() {
	_st_setup
	tui.list lst root 0
	tui.list.set lst a b c d e f
	_tui_store.build_widget lst true ""
	_WXSEL[lst]=4 _WXTOP[lst]=2
	_st_leave_and_return eval 'tui.list lst root 0; tui.list.set lst a b c d e f'
	eq "4 2" "${_WXSEL[lst]} ${_WXTOP[lst]}"
}

t_store_table_keeps_selection_and_scroll() {
	_st_setup
	tui.table tbl root 0
	tui.table.set tbl "H1|H2" "a|b" "c|d" "e|f"
	_tui_store.build_widget tbl true ""
	_WXSEL[tbl]=2 _WXTOP[tbl]=1
	_st_leave_and_return eval 'tui.table tbl root 0; tui.table.set tbl "H1|H2" "a|b" "c|d" "e|f"'
	eq "2 1" "${_WXSEL[tbl]} ${_WXTOP[tbl]}"
}

t_store_selection_is_clamped_to_the_items_there_now() {
	_st_setup
	tui.list lst root 0
	tui.list.set lst a b c d e f
	_tui_store.build_widget lst true ""
	_WXSEL[lst]=5
	_st_leave_and_return eval 'tui.list lst root 0; tui.list.set lst a b'
	eq 1 "${_WXSEL[lst]}"
}

t_store_progress_keeps_value() {
	_st_setup
	_st_w bar progress
	_tui_store.build_widget bar true ""
	_TUI_W_VALUE[bar]=60
	_st_leave_and_return _st_w bar progress
	eq 60 "${_TUI_W_VALUE[bar]}"
}

t_store_widget_without_keep_value_is_not_kept() {
	_st_setup
	_st_w a input
	_st_w b input
	_tui_store.build_widget a true ""
	_TUI_W_VALUE[a]=x _TUI_W_VALUE[b]=y
	_st_leave_and_return eval '_st_w a input; _st_w b input'
	eq "x " "${_TUI_W_VALUE[a]} ${_TUI_W_VALUE[b]}"
}

t_store_state_is_per_page() {
	_st_setup
	_st_w a input
	_tui_store.build_widget a true ""
	_TUI_W_VALUE[a]=on_a
	_tui_store.save_page
	_TUI_MARKUP_FILE="/app/pb.xml"
	_st_w a input
	_tui_store.build_widget a true ""
	_tui_store.restore_page
	eq "" "${_TUI_W_VALUE[a]}"
	_tui_store.save_page
	_TUI_MARKUP_FILE="/app/pa.xml"
	_st_w a input
	_tui_store.build_widget a true ""
	_tui_store.restore_page
	eq on_a "${_TUI_W_VALUE[a]}"
}

t_store_a_custom_type_registers_its_fields() {
	_st_setup
	tui.store.register_type dial value
	_TUI_W_TYPE[dl]=dial _TUI_W_VALUE[dl]=5 _TUI_W_ORDER+=(dl)
	_tui_store.build_widget dl true ""
	_tui_store.save_page
	_TUI_W_VALUE[dl]=0
	_tui_store.restore_page
	eq 5 "${_TUI_W_VALUE[dl]}"
}

# ── panes: collapsed, size ──────────────────────────────────────────────

_st_split() {
	tui.hsplit root a b
	_tui_collapse.build a true "" "" "$1" "" ""
	_tui._layout root
}

ti_store_collapsed_round_trip_with_keep_collapsed() {
	_st_setup
	_st_split true
	tui.collapse a on
	_tui_store.save_page
	tui.collapse a off
	_tui_store.restore_page
	ok 'tui.collapsed a'
}

ti_store_expanded_is_restored_over_a_default_collapsed_pane() {
	_st_setup
	tui.hsplit root a b
	_tui_collapse.build a true collapsed "" true "" ""
	_tui_collapse.init_children root x
	tui.collapsed a || _t_fail "default collapsed pane is not collapsed"
	_tui_store.restore_page # first visit: captures the default
	tui.collapse a off
	_tui_store.save_page
	tui.collapse a on # rebuilt at its default
	_tui_store.restore_page
	ok '! tui.collapsed a'
}

ti_store_collapsed_is_not_kept_without_keep_collapsed() {
	_st_setup
	_st_split ""
	tui.collapse a on
	_tui_store.save_page
	tui.collapse a off
	_tui_store.restore_page
	ok '! tui.collapsed a'
}

ti_store_size_round_trip_with_keep_size() {
	_st_setup
	tui.hsplit root a b
	_tui_store.build_pane a true ""
	_tui_resize.build a x divider ""
	_tui._layout root
	local before="${_TUI_P_WEIGHTS[root]}"
	tui.resize a 10 0
	local after="${_TUI_P_WEIGHTS[root]}"
	[[ "$before" != "$after" ]] || _t_fail "resize did not change the weights"
	_tui_store.save_page
	_TUI_P_WEIGHTS[root]="$before"
	unset '_TUI_P_WEIGHTS0[root]'
	_tui_store.restore_page
	eq "$after" "${_TUI_P_WEIGHTS[root]}"
	ok '[[ -n "${_TUI_P_WEIGHTS0[root]+x}" ]]'
}

ti_store_size_is_not_kept_without_keep_size() {
	_st_setup
	tui.hsplit root a b
	_tui_resize.build a x divider ""
	_tui._layout root
	local before="${_TUI_P_WEIGHTS[root]}"
	tui.resize a 10 0
	_tui_store.save_page
	_TUI_P_WEIGHTS[root]="$before"
	_tui_store.restore_page
	eq "$before" "${_TUI_P_WEIGHTS[root]}"
}

ti_store_size_of_a_collapsed_pane_keeps_its_expanded_spec() {
	_st_setup
	tui.hsplit root a b
	_tui_collapse.build a true "" "" true "" ""
	_tui_store.build_pane a true ""
	_tui._layout root
	local before="${_TUI_P_WEIGHTS[root]}"
	tui.collapse a on
	_tui_store.save_page
	tui.collapse a off
	_tui_store.restore_page
	ok 'tui.collapsed a'
	tui.collapse a off
	eq "$before" "${_TUI_P_WEIGHTS[root]}"
}

# ── keep_state ───────────────────────────────────────────────────────────

ti_store_keep_state_keeps_every_widget_and_pane() {
	_st_setup
	tui.hsplit root a b
	_tui_collapse.build a true "" "" "" "" ""
	tui.input name a 0
	tui.checkbox chk b 0 L 0
	_tui_store.build_page true ""
	_tui._layout root
	_TUI_W_VALUE[name]=zed _TXC[name]=2 _TUI_W_VALUE[chk]=1
	tui.collapse a on
	_st_leave_and_return eval 'tui.input name a 0; tui.checkbox chk b 0 L 0; tui.collapse a off'
	eq "zed 2 1" "${_TUI_W_VALUE[name]} ${_TXC[name]} ${_TUI_W_VALUE[chk]}"
	ok 'tui.collapsed a'
}

t_store_a_page_without_keep_attrs_stores_nothing() {
	_st_setup
	_st_w name input
	_TUI_W_VALUE[name]=zed
	_tui_store.save_page
	ok '! tui.store.has pa.xml'
}

t_store_pane_scroll_is_kept_with_keep_state() {
	_st_setup
	_TUI_P_ALL=(root a b)
	_tui_store.build_page true ""
	_TUI_P_SOFF_V[a]=7 _TUI_P_SOFF_H[a]=2
	_tui_store.save_page
	_TUI_P_SOFF_V[a]=0 _TUI_P_SOFF_H[a]=0
	_tui_store.restore_page
	eq "7 2" "${_TUI_P_SOFF_V[a]} ${_TUI_P_SOFF_H[a]}"
}

# ── reset ────────────────────────────────────────────────────────────────

_st_two_inputs() {
	tui.hsplit root a b
	_st_w one input
	_st_w two input
	_tui_store.build_widget one true ""
	_tui_store.build_widget two true ""
	_TUI_W_VALUE[one]=d1 _TUI_W_VALUE[two]=d2
	_tui_store.restore_page # first visit: captures the defaults
}

ti_store_reset_restores_every_kept_widget_to_its_first_build_value() {
	_st_setup
	_st_two_inputs
	_TUI_W_VALUE[one]=x _TUI_W_VALUE[two]=y _TXC[one]=1
	_tui_store.save_page
	_tui_store.restore_page
	eq "x y" "${_TUI_W_VALUE[one]} ${_TUI_W_VALUE[two]}"
	local g=${_TUI_LY_GEN:-0}
	tui.page.reset
	eq "d1 d2" "${_TUI_W_VALUE[one]} ${_TUI_W_VALUE[two]}"
	ok '! tui.store.has pa.xml'
	ok "((${_TUI_LY_GEN:-0} > g))"
}

ti_store_restore_never_overwrites_the_defaults() {
	_st_setup
	_st_two_inputs
	_TUI_W_VALUE[one]=changed
	_tui_store.save_page
	_tui_store.restore_page
	_tui_store.restore_page
	tui.page.reset_field one
	eq "d1" "${_TUI_W_VALUE[one]}"
}

ti_store_reset_field_touches_one_widget() {
	_st_setup
	_st_two_inputs
	_TUI_W_VALUE[one]=x _TUI_W_VALUE[two]=y
	_tui_store.save_page
	tui.page.reset_field one
	eq "d1 y" "${_TUI_W_VALUE[one]} ${_TUI_W_VALUE[two]}"
	ok '! tui.store.has pa.xml one'
	ok 'tui.store.has pa.xml two'
}

t_store_reset_field_of_an_unkept_widget_fails() {
	_st_setup
	_st_two_inputs
	_st_w three input
	ok '! tui.page.reset_field three'
}

ti_store_reset_restores_collapsed_and_size() {
	_st_setup
	tui.hsplit root a b
	_tui_collapse.build a true "" "" true "" ""
	_tui_store.build_pane a true ""
	_tui_resize.build a x divider ""
	_tui._layout root
	local before="${_TUI_P_WEIGHTS[root]}"
	_tui_store.restore_page
	tui.resize a 10 0
	tui.collapse a on
	_tui_store.save_page
	tui.page.reset
	ok '! tui.collapsed a'
	eq "$before" "${_TUI_P_WEIGHTS[root]}"
	ok '[[ -z "${_TUI_P_WEIGHTS0[root]+x}" ]]'
}

ti_store_reset_returns_a_default_collapsed_pane_to_collapsed() {
	_st_setup
	tui.hsplit root a b
	_tui_collapse.build a true collapsed "" true "" ""
	_tui_collapse.init_children root x
	_tui_store.restore_page
	tui.collapse a off
	tui.page.reset
	ok 'tui.collapsed a'
}

ti_store_reset_all_clears_the_whole_store() {
	_st_setup
	_st_two_inputs
	tui.store.set pb.xml z value 1
	_TUI_W_VALUE[one]=x
	_tui_store.save_page
	tui.page.reset_all
	ok '! tui.store.has pa.xml'
	ok '! tui.store.has pb.xml'
	eq "d1" "${_TUI_W_VALUE[one]}"
}

ti_store_reset_of_another_page_only_drops_its_state() {
	_st_setup
	_st_two_inputs
	tui.store.set pb.xml z value 1
	_TUI_W_VALUE[one]=x
	tui.page.reset pb.xml
	ok '! tui.store.has pb.xml'
	eq "x" "${_TUI_W_VALUE[one]}"
}

t_store_resettable_follows_state_against_defaults() {
	_st_setup
	_st_two_inputs
	ok '! tui.page.resettable'
	_TUI_W_VALUE[one]=x
	ok 'tui.page.resettable'
	_TUI_W_VALUE[one]=d1
	ok '! tui.page.resettable'
	_TUI_P_WEIGHTS0[root]="1 1"
	ok 'tui.page.resettable'
}

ti_store_resettable_sees_a_collapsed_pane_that_defaults_to_open() {
	_st_setup
	tui.hsplit root a b
	_tui_collapse.build a true "" "" true "" ""
	_tui._layout root
	_tui_store.restore_page
	ok '! tui.page.resettable'
	tui.collapse a on
	ok 'tui.page.resettable'
}

t_store_page_without_kept_state_is_not_resettable() {
	_st_setup
	_st_w a input
	ok '! tui.page.resettable'
}

ti_store_actions_and_commands_exist() {
	_st_setup
	ok 'declare -F tui.action.page_reset >/dev/null'
	ok 'declare -F tui.action.page_reset_field >/dev/null'
	ok 'declare -F tui.action.page_reset_all >/dev/null'
	_st_two_inputs
	_TUI_W_VALUE[one]=x _TUI_W_VALUE[two]=y
	_TUI_FOCUS_ID=one
	tui.action.page_reset_field
	eq "d1 y" "${_TUI_W_VALUE[one]} ${_TUI_W_VALUE[two]}"
	tui.action.page_reset
	eq "d2" "${_TUI_W_VALUE[two]}"
}

# ── the real seam: tui.goto A -> B -> A ──────────────────────────────────

ti_store_goto_a_b_a_restores_what_a_kept() {
	_st_setup
	local d="$_T_ROOT/store_pages"
	mkdir -p "$d"
	cat >"$d/pa.xml" <<'XML'
<tui keep_state="false">
  <pane id="root" split="h" border="single">
    <pane id="left" collapsible="true" keep_collapsed="true" resizable="x" keep_size="true" weight="1" border="single">
      <input id="name" keep_value="true" placeholder="x"/>
      <input id="loose"/>
    </pane>
    <pane id="right" weight="1" border="single"><label id="l" text="a"/></pane>
  </pane>
</tui>
XML
	cat >"$d/pb.xml" <<'XML'
<tui>
  <pane id="root" border="single"><input id="name" keep_value="true"/></pane>
</tui>
XML
	_TUI_MARKUP_DIR="$d"
	_TUI_ROWS=24 _TUI_COLS=80
	tui.goto "$d/pa.xml" >/dev/null 2>"$_T_ROOT/st.err"
	ok '[[ -n "${_TUI_W_KEEP[name]:-}" ]]'
	_TUI_W_VALUE[name]=typed _TUI_W_VALUE[loose]=lost
	tui.collapse left on
	tui.goto "$d/pb.xml" >/dev/null 2>>"$_T_ROOT/st.err"
	eq "" "${_TUI_W_VALUE[name]}"
	_TUI_W_VALUE[name]=b_value
	tui.goto "$d/pa.xml" >/dev/null 2>>"$_T_ROOT/st.err"
	eq "typed " "${_TUI_W_VALUE[name]} ${_TUI_W_VALUE[loose]}"
	ok 'tui.collapsed left'
	tui.goto "$d/pb.xml" >/dev/null 2>>"$_T_ROOT/st.err"
	eq b_value "${_TUI_W_VALUE[name]}"
	eq "" "$(<"$_T_ROOT/st.err")"
}

# ── only what is kept is walked, and an unchanged restore lays nothing out again ──

t_store_kept_ids_lists_only_the_widgets_and_panes_that_keep_something() {
	_st_setup
	_st_w a input
	_st_w b input
	_TUI_P_ALL=(root p1 p2)
	_TUI_W_KEEP=() _TUI_P_KEEP_SIZE=() _TUI_P_KEEP_COLLAPSED=() _TUI_P_LAYOUT_KEEP=() _TUI_P_KEEP_STATE=""
	_tui_store.kept_ids
	eq 0 "${#_SIDS[@]}" # a page that keeps nothing walks nothing
	_TUI_W_KEEP[b]=1 _TUI_P_KEEP_SIZE[p2]=1
	_tui_store.kept_ids
	eq "b p2" "${_SIDS[*]}"
	_TUI_P_KEEP_STATE=1
	_tui_store.kept_ids
	eq "a b root p1 p2" "${_SIDS[*]}" # keep_state keeps every widget and pane
	_TUI_W_KEEP=() _TUI_P_KEEP_SIZE=() _TUI_P_KEEP_STATE="" _TUI_P_ALL=(root) _TUI_W_ORDER=() _TUI_W_TYPE=()
}

ti_store_restoring_what_is_already_there_does_not_lay_out_again() {
	_st_setup
	_st_split true
	tui.collapse a on
	_tui_store.save_page
	local _real_layout _lays=0
	_real_layout="$(declare -f _tui._layout)"
	_tui._layout() { _lays+=1; }
	_tui_store.restore_page # the page is as it was saved
	eval "$_real_layout"
	eq 0 "$_lays"
	tui.collapse a off
	_tui_store.restore_page # now it differs: the pane is collapsed again and the geometry is stale until the layout runs
	ok 'tui.collapsed a'
}
