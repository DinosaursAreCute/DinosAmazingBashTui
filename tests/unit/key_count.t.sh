# key_count.t.sh - held keys: identical key presses already waiting in the input are merged into one event with a count
# (TUI_EVENT_COUNT) when the handler that would receive them takes a count, and that handler moves by the whole count.

# the _WX* widget tables are not in the runner snapshot: start every test clean
_kc_reset() {
	_WXSEL=() _WXTOP=() _WXA=()
	_TUI_FOCUS_ID="" _TUI_MODAL="" _TUI_MODAL_COUNT_KEYS="" _TUI_PENDING_INPUT="" _TUI_L_TRAP="" _TUI_REPEAT=1 TUI_EVENT_COUNT=1
	TUI_INPUT_COALESCE=1
	_TUI_P_ROW[kcp]=1 _TUI_P_COL[kcp]=1 _TUI_P_H[kcp]=8 _TUI_P_W[kcp]=20
	unset '_TUI_P_CHILDREN[kcp]'
}

_kc_list() { # a focused 20-row list "kcl" in pane kcp
	_kc_reset
	local items=() i
	for i in {1..20}; do items+=("item $i"); done
	tui.list kcl kcp 0 "" 5
	tui.list.set kcl "${items[@]}"
	tui.list.select kcl 0
	_TUI_FOCUS_ID=kcl
}

ti_keycount_list_moves_by_the_whole_count_and_clamps_at_the_end() {
	_kc_list
	_tui_wx.move kcl down 3
	tui.list.selected kcl s
	eq 3 "$s"
	_tui_wx.move kcl down 100
	tui.list.selected kcl s
	eq 19 "$s"
	_tui_wx.move kcl up 5
	tui.list.selected kcl s
	eq 14 "$s"
}

ti_keycount_list_fires_on_change_once_per_batch() {
	_kc_list
	KC_CHANGES=0
	kc_changed() { KC_CHANGES=$((KC_CHANGES + 1)); }
	tui.on_change kcl kc_changed
	TUI_EVENT_COUNT=6
	_tui_wx.key kcl down
	tui.list.selected kcl s
	eq 6 "$s"
	eq 1 "$KC_CHANGES"
}

ti_keycount_page_keys_move_a_page_per_count() {
	_kc_list
	_tui_wx.move kcl pgdn 1
	tui.list.selected kcl s
	local one=$s
	tui.list.select kcl 0
	_tui_wx.move kcl pgdn 2
	tui.list.selected kcl s
	eq "$((one * 2))" "$s"
}

ti_keycount_countable_is_true_for_list_navigation_only() {
	_kc_list
	ok '_tui_input.countable down'
	ok '_tui_input.countable up'
	ok '_tui_input.countable pgdn'
	ok '! _tui_input.countable home'
	ok '! _tui_input.countable enter'
	ok '! _tui_input.countable a'
	_TUI_FOCUS_ID=""
	ok '! _tui_input.countable down'          # nothing focused that takes a count
	eq "" "$(_tui_input.countable down 2>&1)" # and no "bad array subscript" from the empty focus id
}

ti_keycount_a_held_down_key_over_a_list_is_merged() {
	_kc_list
	_tui_input.coalesce_key "" "[B" < <(printf '\e[B\e[B\e[B')
	eq 4 "$_TUI_REPEAT"
}

ti_keycount_a_different_key_ends_the_batch_and_is_kept() {
	_kc_list
	_tui_input.coalesce_key "" "[B" < <(printf '\e[B\e[B\e[A')
	eq 3 "$_TUI_REPEAT"
	eq $'\e[A' "$_TUI_PENDING_INPUT"
}

ti_keycount_keys_are_not_merged_when_coalescing_is_off_or_nothing_takes_a_count() {
	_kc_list
	TUI_INPUT_COALESCE=0
	_tui_input.coalesce_key "" "[B" < <(printf '\e[B\e[B')
	eq 1 "$_TUI_REPEAT"
	TUI_INPUT_COALESCE=1
	_TUI_FOCUS_ID=""
	_tui_input.coalesce_key "" "[B" < <(printf '\e[B\e[B')
	eq 1 "$_TUI_REPEAT"
}

ti_keycount_a_modal_layer_still_merges_for_its_focused_list() {
	_kc_list
	_TUI_L_TRAP=dlg
	_tui_input.coalesce_key "" "[B" < <(printf '\e[B\e[B')
	eq 3 "$_TUI_REPEAT"
}

ti_keycount_choose_dialog_moves_by_the_count() {
	_kc_reset
	_DLG_KIND=choose _DLG_ITEMS=(a b c d e f g h) _DLG_SEL=0 _DLG_TOP=0 _DLG_ROWS=4
	_TUI_MODAL=dialog _TUI_MODAL_DRAWFN=""
	tui.modal.redraw() { :; }
	TUI_EVENT_COUNT=3
	_tui_dialog.key down
	eq 3 "$_DLG_SEL"
	TUI_EVENT_COUNT=50
	_tui_dialog.key down
	eq 7 "$_DLG_SEL"
	TUI_EVENT_COUNT=2
	_tui_dialog.key up
	eq 5 "$_DLG_SEL"
	TUI_EVENT_COUNT=1
	_tui_dialog.key pgdn
	eq 7 "$_DLG_SEL"
}

ti_keycount_view_dialog_scrolls_by_the_count() {
	_kc_reset
	_DLG_KIND=view _DLG_ITEMS=(1 2 3 4 5 6 7 8 9 10 11 12) _DLG_TOP=0 _DLG_ROWS=4
	tui.modal.redraw() { :; }
	TUI_EVENT_COUNT=3
	_tui_dialog.key down
	eq 3 "$_DLG_TOP"
	TUI_EVENT_COUNT=2
	_tui_dialog.key up
	eq 1 "$_DLG_TOP"
}

ti_keycount_a_modal_names_the_keys_it_counts() {
	_kc_reset
	_TUI_MODAL=dialog _TUI_MODAL_COUNT_KEYS=" up down pgup pgdn "
	ok '_tui_input.countable down'
	ok '! _tui_input.countable enter'
	_tui_input.coalesce_key "" "[B" < <(printf '\e[B\e[B\e[B\e[B')
	eq 5 "$_TUI_REPEAT"
	_TUI_MODAL="" _TUI_MODAL_COUNT_KEYS=""
}

ti_keycount_palette_moves_by_the_count() {
	_kc_reset
	_PAL_IDS=(a b c d e f g h) _PAL_SEL=0 _PAL_ROWS=4 _PAL_TOP=0
	_tui_cmd.scroll_into_view() { :; }
	tui.modal.redraw() { :; }
	TUI_EVENT_COUNT=3
	_tui_cmd.palette_key down
	eq 3 "$_PAL_SEL"
	TUI_EVENT_COUNT=2
	_tui_cmd.palette_key up
	eq 1 "$_PAL_SEL"
}

ti_keycount_a_bind_flagged_count_is_merged_and_an_unflagged_one_is_not() {
	_kc_reset
	tui.bind f9 kc_noop
	_tui_input.coalesce_key "" "[20~" < <(printf '\e[20~\e[20~')
	eq 1 "$_TUI_REPEAT"
	tui.bind f9 kc_noop --count
	_tui_input.coalesce_key "" "[20~" < <(printf '\e[20~\e[20~')
	eq 3 "$_TUI_REPEAT"
	tui.unbind f9
}

# _kc_redraw_bytes ID -> _KC_OUT: what one list redraw sends to the terminal (_tui.write wraps it in the synchronized update)
_kc_redraw_bytes() {
	_KC_OUT=""
	local saved_write
	saved_write="$(declare -f _tui.write)"
	_tui.write() { _KC_OUT+="$1"; }
	_TUI_RUNNING=1
	_tui_wx.redraw "$1"
	_TUI_RUNNING=0
	eval "$saved_write"
}

ti_list_redraw_goes_through_the_flush_path() {
	_kc_list
	tui.paint.reset
	_kc_redraw_bytes kcl
	match "$_KC_OUT" $'\e\\[[0-9]+;[0-9]+H'
}

# tui.on_change ID FN --debounce: a held key moves the list on every step, the callback runs once the keys stop
ti_debounced_on_change_waits_for_flush_changes() {
	_kc_list
	KC_CHANGES=0
	kc_changed() { KC_CHANGES=$((KC_CHANGES + 1)); }
	tui.on_change kcl kc_changed --debounce
	_TUI_RUNNING=1
	_tui_wx.move kcl down 1
	_tui_wx.move kcl down 1
	_TUI_RUNNING=0
	eq 0 "$KC_CHANGES"
	_tui_wx.flush_changes
	eq 1 "$KC_CHANGES"
	_tui_wx.flush_changes
	eq 1 "$KC_CHANGES"
}

ti_debounced_on_change_fires_at_once_while_the_loop_is_not_running() {
	_kc_list
	KC_CHANGES=0
	kc_changed() { KC_CHANGES=$((KC_CHANGES + 1)); }
	tui.on_change kcl kc_changed --debounce
	_tui_wx.move kcl down 1
	eq 1 "$KC_CHANGES"
}

ti_on_change_without_the_flag_fires_on_every_move() {
	_kc_list
	KC_CHANGES=0
	kc_changed() { KC_CHANGES=$((KC_CHANGES + 1)); }
	tui.on_change kcl kc_changed
	_TUI_RUNNING=1
	_tui_wx.move kcl down 1
	_tui_wx.move kcl down 1
	_TUI_RUNNING=0
	eq 2 "$KC_CHANGES"
}
