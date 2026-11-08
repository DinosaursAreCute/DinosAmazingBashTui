# layer_keys.t.sh - a modal layer owns the keyboard: page bindings and the palette / quit / scroll defaults are off while it is
# open, focus keys and the focused widget still work, and everything returns when it closes.

_lk_load() {
	_LKD="$_T_ROOT/lk_${RANDOM}${RANDOM}"
	mkdir -p "$_LKD"
	printf '%s\n' '<tui>
  <pane id="root" split="v">
    <pane id="base" border="single"><button id="base_btn" text="under"/></pane>
  </pane>
  <modal id="dlg" x="center" y="center" width="24" height="9" open="false">
    <list id="dlg_list" rows="4" items="a|b|c|d|e|f"/>
    <button id="dlg_ok" text="OK"/>
  </modal>
  <window id="win" x="2" y="2" width="20" height="5" float="true" open="false">
    <button id="win_btn" text="in a window"/>
  </window>
</tui>' >"$_LKD/p.xml"
	tui.reset_ui
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_MARKUP_DIR="$_LKD"
	tui.load "$_LKD/p.xml" 2>"$_LKD/err"
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=24 _TUI_P_W[root]=80
	_tui._layout root
	LK_HITS=""
	lk_page_x() { LK_HITS+="x"; }
	lk_pane_x() { LK_HITS+="p"; }
	tui.bind f5 lk_page_x
	tui.bind f6 lk_pane_x --pane base
	_TUI_FOCUS_ID="" _TUI_MODAL=""
}

_lk_key() { _tui_input.key_event "" "$1"; } # an escape sequence: f5 is [15~, f6 [17~

ti_layerkeys_page_binding_fires_without_a_modal_layer() {
	_lk_load
	_lk_key "[15~"
	eq "x" "$LK_HITS"
}

ti_layerkeys_page_binding_is_off_while_a_modal_layer_is_open() {
	_lk_load
	tui.layer.show dlg
	_lk_key "[15~"
	eq "" "$LK_HITS"
	tui.layer.hide dlg
	_lk_key "[15~"
	eq "x" "$LK_HITS"
}

ti_layerkeys_a_non_modal_window_leaves_the_page_bindings_alone() {
	_lk_load
	tui.layer.show win
	_lk_key "[15~"
	eq "x" "$LK_HITS"
}

ti_layerkeys_palette_and_quit_defaults_are_off_in_a_modal_layer() {
	_lk_load
	local opened=0 saved
	saved="$(declare -f tui.palette.open tui.action.quit)" # put back below: ti_ tests are not restored
	tui.palette.open() { opened=1; }
	tui.action.quit() { opened=2; }
	tui.layer.show dlg
	_tui_input.key_event $'\x10' "" # ctrl+p
	_tui_input.key_event $'\x11' "" # ctrl+q
	eq 0 "$opened"
	eval "$saved"
}

ti_layerkeys_the_focused_widget_still_gets_arrows() {
	_lk_load
	tui.layer.show dlg
	eq "dlg_list" "$_TUI_FOCUS_ID"
	_tui_input.key_event "" "[B"
	local sel
	tui.list.selected dlg_list sel
	eq 1 "$sel"
}

ti_layerkeys_tab_still_moves_focus_inside_the_modal_layer() {
	_lk_load
	tui.layer.show dlg
	_tui_input.key_event $'\t' ""
	eq "dlg_ok" "$_TUI_FOCUS_ID"
}

ti_layerkeys_a_pane_binding_of_the_page_is_off_too() {
	_lk_load
	_TUI_HOVERED_PANE=base
	tui.layer.show dlg
	_lk_key "[17~"
	eq "" "$LK_HITS"
}
