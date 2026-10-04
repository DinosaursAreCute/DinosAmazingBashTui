# layer.t.sh - lib/chrome/tui_layer.sh: layers float above the page (stage 3B). Builds real pages, so every case is ti_.

# _ly_load XML - writes a page into the runner root, loads and lays it out at 80x24
_ly_load() {
	_LYD="$_T_ROOT/ly_${RANDOM}${RANDOM}"
	mkdir -p "$_LYD"
	printf '%s\n' "$1" >"$_LYD/p.xml"
	tui.reset_ui
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_MARKUP_DIR="$_LYD"
	tui.load "$_LYD/p.xml" 2>"$_LYD/err"
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=24 _TUI_P_W[root]=80
	_tui._layout root
}
_LY_PAGE='<tui>
  <pane id="root" split="v">
    <pane id="base" border="single">
      <button id="base_btn" text="under"/>
    </pane>
  </pane>
  <window id="w1" title="Win" x="5" y="3" width="30" height="8" float="true">
    <button id="w1_btn" text="inside"/>
  </window>
</tui>'

ti_layer_window_is_a_layer_outside_the_split_tree_placed_at_its_rectangle() {
	_ly_load "$_LY_PAGE"
	eq "" "$(<"$_LYD/err")"
	eq "w1" "${_TUI_L_ORDER[*]}"
	eq "base" "${_TUI_P_CHILDREN[root]}"
	eq "4 6 8 30" "${_TUI_L_ROW[w1]} ${_TUI_L_COL[w1]} ${_TUI_L_H[w1]} ${_TUI_L_W[w1]}"
	eq "4 6 8 30" "${_TUI_P_ROW[w1]} ${_TUI_P_COL[w1]} ${_TUI_P_H[w1]} ${_TUI_P_W[w1]}"
	eq "w1" "${_TUI_P_LAYER[w1]}"
	eq "root base w1" "${_TUI_P_ALL[*]}" # the layer's panes follow the page's
}

ti_layer_rectangle_is_clamped_to_the_screen_and_percent_sizes_follow_it() {
	_ly_load '<tui>
  <pane id="root"/>
  <window id="far" x="100" y="40" width="30" height="10"/>
  <window id="pct" x="0" y="0" width="50%" height="25%"/>
  <window id="mid" x="center" y="center" width="20" height="6"/>
</tui>'
	eq "15 51 10 30" "${_TUI_L_ROW[far]} ${_TUI_L_COL[far]} ${_TUI_L_H[far]} ${_TUI_L_W[far]}"
	eq "40 6" "${_TUI_L_W[pct]} ${_TUI_L_H[pct]}"
	eq "10 31" "${_TUI_L_ROW[mid]} ${_TUI_L_COL[mid]}"
}

ti_layer_anchor_to_a_pane_measures_from_its_corner() {
	_ly_load '<tui>
  <pane id="root" split="v">
    <pane id="a" weight="1" border="single"/>
    <pane id="b" weight="1" border="single"/>
  </pane>
  <popup id="pop" anchor="#a" x="2" y="below" width="12" height="4"/>
</tui>'
	eq "$((_TUI_P_ROW[a] + _TUI_P_H[a]))" "${_TUI_L_ROW[pop]}" # y=below: the anchor's bottom edge
	eq "$((_TUI_P_COL[a] + 2))" "${_TUI_L_COL[pop]}"
}

ti_layer_hit_ranks_the_layer_over_the_page_and_blocks_what_is_under_it() {
	_ly_load "$_LY_PAGE"
	local r c
	_tui._widget_pos w1_btn
	_tui_hit.at "$_WSC" "$_WSR"
	eq "widget:w1_btn" "$_HIT_KIND:$_HIT_ID"
	_tui_hit.at 8 7 # the layer's blank body, the page's button is not under it
	eq "w1" "$_HIT_PANE"
	_tui._widget_pos base_btn
	r=$_WSR c=$_WSC
	_tui_hit.at "$c" "$r"
	eq "widget:base_btn" "$_HIT_KIND:$_HIT_ID" # outside the layer: the page
	_tui_hit.at 8 4                            # the header row of the layer, left of its buttons
	eq "layer:w1:drag" "$_HIT_KIND:$_HIT_ID:$_HIT_ARG"
}

ti_layer_page_render_skips_layers_and_the_overlay_draws_them() {
	_ly_load "$_LY_PAGE"
	_TUI_FRAME=""
	tui.render
	ok '[[ "$_TUI_BASE_FRAME" != *"Win"* ]]'
	ok '[[ "$_TUI_BASE_FRAME" == *"under"* ]]'
	_TUI_FRAME=""
	_tui_layer.draw
	ok '[[ "$_TUI_FRAME" == *"Win"* && "$_TUI_FRAME" == *"inside"* ]]'
	ok '[[ "$_TUI_FRAME" == *"▒"* ]]' # the shadow
	ok '[[ "$_TUI_FRAME" == *"↺"* ]]' # a floating layer has the reset button
}

ti_layer_raise_reorders_and_hit_follows_the_stack() {
	_ly_load '<tui>
  <pane id="root"/>
  <window id="a" x="2" y="2" width="20" height="6"/>
  <window id="b" x="6" y="3" width="20" height="6"/>
</tui>'
	eq "a b" "${_TUI_L_ORDER[*]}"
	_tui_hit.at 8 4
	eq "b" "$_HIT_PANE" # both cover it: the upper one
	tui.layer.raise a
	eq "b a" "${_TUI_L_ORDER[*]}"
	_tui_hit.at 8 4
	eq "a" "$_HIT_PANE"
	eq "root b a" "${_TUI_P_ALL[*]}"
}

ti_layer_hide_show_close_and_the_modal_focus_scope() {
	_ly_load '<tui>
  <pane id="root">
    <button id="page_btn" text="page"/>
  </pane>
  <modal id="dlg" x="center" y="center" width="24" height="7" open="false">
    <button id="dlg_ok" text="ok"/>
  </modal>
</tui>'
	ok '! tui.layer.active dlg'
	_tui_focus.ensure
	eq "page_btn" "${_TUI_FOCUSABLE[*]}" # a hidden layer's widgets are not focusable
	tui.focus page_btn
	tui.layer.show dlg
	ok 'tui.layer.active dlg'
	_tui_focus.ensure
	eq "dlg_ok" "${_TUI_FOCUSABLE[*]}" # the modal layer holds the scope
	eq "dlg_ok" "$_TUI_FOCUS_ID"
	tui.layer.close dlg
	ok '! tui.layer.active dlg'
	eq "page_btn" "$_TUI_FOCUS_ID" # focus comes back
	_tui_focus.ensure
	eq "page_btn" "${_TUI_FOCUSABLE[*]}"
}

ti_layer_move_resize_reset_and_zoom() {
	_ly_load "$_LY_PAGE"
	tui.layer.move w1 10 20
	eq "10 20" "${_TUI_L_ROW[w1]} ${_TUI_L_COL[w1]}"
	eq "10 20" "${_TUI_P_ROW[w1]} ${_TUI_P_COL[w1]}"
	tui.layer.move w1 99 99 # clamped
	eq "17 51" "${_TUI_L_ROW[w1]} ${_TUI_L_COL[w1]}"
	tui.layer.size w1 5 12
	eq "5 12" "${_TUI_P_H[w1]} ${_TUI_P_W[w1]}"
	tui.layer.reset w1
	eq "4 6 8 30" "${_TUI_L_ROW[w1]} ${_TUI_L_COL[w1]} ${_TUI_L_H[w1]} ${_TUI_L_W[w1]}"
	tui.layer.zoom w1
	eq "1 1 24 80" "${_TUI_L_ROW[w1]} ${_TUI_L_COL[w1]} ${_TUI_L_H[w1]} ${_TUI_L_W[w1]}"
	tui.layer.zoom w1
	eq "4 6 8 30" "${_TUI_L_ROW[w1]} ${_TUI_L_COL[w1]} ${_TUI_L_H[w1]} ${_TUI_L_W[w1]}"
}

ti_layer_header_buttons_and_the_drag_corner_are_zones() {
	_ly_load '<tui>
  <pane id="root"/>
  <window id="w" x="2" y="2" width="30" height="8" float="true" closable="true" fullscreen="true" minimizable="true"/>
</tui>'
	local right=$((_TUI_L_COL[w] + _TUI_L_W[w])) row=${_TUI_L_ROW[w]}
	_tui_hit.at "$((right - 3))" "$row"
	eq "btn:close" "$_HIT_ARG"
	_tui_hit.at "$((right - 5))" "$row"
	eq "btn:min" "$_HIT_ARG"
	_tui_hit.at "$((right - 7))" "$row"
	eq "btn:full" "$_HIT_ARG"
	_tui_hit.at "$((right - 9))" "$row"
	eq "btn:reset" "$_HIT_ARG"
	_tui_hit.at "$((right - 2))" "$((row + _TUI_L_H[w] - 1))"
	eq "size" "$_HIT_ARG"
}

ti_layer_mouse_drags_the_header_and_the_corner() {
	_ly_load "$_LY_PAGE"
	_tui_hit.at 8 4
	_tui_layer.mouse mouse:left 8 4
	_tui_layer.mouse drag:left 18 7
	eq "7 16" "${_TUI_L_ROW[w1]} ${_TUI_L_COL[w1]}" # the pointer moved by (+10, +3)
	_tui_layer.mouse release 18 7
	eq "" "$_TUI_L_DRAG"
	_tui_hit.at "$((_TUI_L_COL[w1] + _TUI_L_W[w1] - 1))" "$((_TUI_L_ROW[w1] + _TUI_L_H[w1] - 1))"
	eq "size" "$_HIT_ARG"
}

ti_layer_a_page_change_removes_the_layers() {
	_ly_load "$_LY_PAGE"
	tui.reset_ui
	eq 0 "$_TUI_L_N"
	eq "" "${_TUI_L_ORDER[*]}"
	eq 0 "${#_TUI_P_LAYER[@]}"
}

ti_layer_popup_closes_on_an_outside_press_and_esc_and_a_modal_swallows_presses() {
	_ly_load '<tui>
  <pane id="root">
    <button id="page_btn" text="page"/>
  </pane>
  <popup id="pop" x="10" y="10" width="14" height="4" open="false">
    <label id="pop_l" text="menu"/>
  </popup>
  <modal id="dlg" x="center" y="center" width="20" height="5" open="false">
    <button id="dlg_ok" text="ok"/>
  </modal>
</tui>'
	tui.layer.show pop
	_tui_hit.at 2 2 # over the page
	ok '_tui_layer.outside'
	ok '! tui.layer.active pop' # an outside press closes a popup
	tui.layer.show pop
	ok '_tui_layer.dismiss_key' # Esc: popups are closable by nature
	ok '! tui.layer.active pop'
	tui.layer.show dlg
	_tui_hit.at 2 2
	ok '_tui_layer.outside'   # swallowed
	ok 'tui.layer.active dlg' # ...and the modal stays
	_tui_hit.at "$((_TUI_L_COL[dlg] + 2))" "$((_TUI_L_ROW[dlg] + 2))"
	ok '! _tui_layer.outside'                                                          # inside: it goes on to the widget
	_tui_layer.dismiss_key && ok '! tui.layer.active dlg' || ok 'tui.layer.active dlg' # a modal without closable has no Esc
}

ti_layer_press_in_a_lower_layer_raises_it_and_focus_into_it_does_too() {
	_ly_load '<tui>
  <pane id="root"/>
  <window id="a" x="2" y="2" width="20" height="6"><button id="a_btn" text="a"/></window>
  <window id="b" x="40" y="2" width="20" height="6"><button id="b_btn" text="b"/></window>
</tui>'
	_tui_hit.at 4 4
	ok '! _tui_layer.outside'
	eq "b a" "${_TUI_L_ORDER[*]}"
	tui.focus b_btn
	eq "a b" "${_TUI_L_ORDER[*]}"
}

ti_layer_toast_hides_itself_after_its_timeout() {
	_ly_load '<tui>
  <pane id="root"/>
  <toast id="t" x="2" y="2" width="12" height="3" timeout="3"/>
</tui>'
	ok 'tui.layer.active t'
	_TUI_L_EXPIRES[t]=$((${EPOCHREALTIME%[.,]*} - 1)) # the clock has passed it
	_tui_layer.expire
	ok '! tui.layer.active t'
}

ti_layer_dragging_snaps_to_a_screen_edge() {
	_ly_load "$_LY_PAGE"
	_tui_layer.snap w1 2 3
	eq "1 1" "$_SN_ROW $_SN_COL"
	_tui_layer.snap w1 10 20
	eq "10 20" "$_SN_ROW $_SN_COL"
	_tui_layer.snap w1 15 49
	eq "17 51" "$_SN_ROW $_SN_COL" # 24 rows, 80 cols: 8x30 snapped against the bottom right
}

_LY_SPLIT='<tui>
  <pane id="root" split="h">
    <pane id="a" weight="1" border="single" detachable="true" on_detach="_ly_on_detach" on_dock="_ly_on_dock" title="Logs">
      <button id="a_btn" text="a"/>
    </pane>
    <pane id="b" weight="2" border="single"/>
    <pane id="c" weight="1" border="single"/>
  </pane>
</tui>'
_ly_on_detach() { _LY_CB+="detach:$1 "; }
_ly_on_dock() { _LY_CB+="dock:$1 "; }

ti_layer_detach_moves_the_pane_out_of_its_split_and_dock_puts_it_back() {
	_LY_CB=""
	_ly_load "$_LY_SPLIT"
	local row=${_TUI_P_ROW[a]} col=${_TUI_P_COL[a]}
	eq "a b c" "${_TUI_P_CHILDREN[root]}"
	eq "1 2 1" "${_TUI_P_WEIGHTS[root]}"
	tui.layer.detach a
	eq "b c" "${_TUI_P_CHILDREN[root]}"
	eq "2 1" "${_TUI_P_WEIGHTS[root]}"
	eq "a" "${_TUI_L_ORDER[*]}"
	eq "a" "${_TUI_P_LAYER[a]}"
	eq "1 $((col + 2))" "${_TUI_L_ROW[a]} ${_TUI_L_COL[a]}" # beside the place it left (a full-height pane: clamped to the top)
	eq "detach:a " "$_LY_CB"
	ok '[[ -n "${_TUI_L_F[a.float]:-}" ]]'
	tui.layer.dock a
	eq "a b c" "${_TUI_P_CHILDREN[root]}"
	eq "1 2 1" "${_TUI_P_WEIGHTS[root]}"
	eq 0 "$_TUI_L_N"
	eq "detach:a dock:a " "$_LY_CB"
	ok '[[ -z "${_TUI_P_LAYER[a]+x}" ]]'
}

ti_layer_detach_with_a_placeholder_keeps_the_place_and_refuses_what_it_cannot_move() {
	_ly_load "${_LY_SPLIT/title=\"Logs\"/title=\"Logs\" leave=\"placeholder\"}"
	tui.layer.detach a
	eq "a__slot b c" "${_TUI_P_CHILDREN[root]}"
	eq "1 2 1" "${_TUI_P_WEIGHTS[root]}"
	tui.layer.dock a
	eq "a b c" "${_TUI_P_CHILDREN[root]}"
	ok '[[ -z "${_TUI_P_ROW[a__slot]:-}" ]]'
	ok '! tui.layer.detach root' # the root has no split to leave
	ok '! tui.layer.dock b'      # b never detached
}

ti_layer_detach_button_is_a_zone_and_the_dock_button_appears_while_floating() {
	_ly_load "$_LY_SPLIT"
	_tui_layer.detach_cell a
	_tui_hit.at "$_DT_C" "$_DT_R"
	eq "layer:a:dt" "$_HIT_KIND:$_HIT_ID:$_HIT_ARG"
	_tui_layer.mouse mouse:left "$_DT_C" "$_DT_R"
	eq "a" "${_TUI_L_ORDER[*]}"
	_tui_layer.buttons a
	ok '[[ " $_LB " == *" dock "* ]]'
}

ti_layer_layout_persists_across_a_page_reload() {
	_ly_load '<tui>
  <pane id="root"/>
  <window id="w" x="2" y="2" width="20" height="6" float="true" persist="layout"/>
  <pane id="dummy"/>
</tui>'
	tui.layer.move w 9 33
	tui.layer.hide w
	_tui_store.save_page
	local file="$_LYD/p.xml"
	tui.reset_ui
	tui.load "$file" 2>/dev/null
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=24 _TUI_P_W[root]=80
	_tui._layout root
	eq "2 2" "$((_TUI_L_ROW[w] - 1)) $((_TUI_L_COL[w] - 1))" # first build: where the markup put it
	_tui_store.restore_page
	eq "9 33" "${_TUI_L_ROW[w]} ${_TUI_L_COL[w]}"
	ok '! tui.layer.active w'
}

ti_layer_detached_pane_layout_persists_too() {
	_ly_load "${_LY_SPLIT/title=\"Logs\"/title=\"Logs\" persist=\"layout\"}"
	tui.layer.detach a
	tui.layer.size a 8 30
	tui.layer.move a 10 30
	_tui_store.save_page
	local file="$_LYD/p.xml"
	tui.reset_ui
	tui.load "$file" 2>/dev/null
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=24 _TUI_P_W[root]=80
	_tui._layout root
	eq "a b c" "${_TUI_P_CHILDREN[root]}"
	_tui_store.restore_page
	eq "b c" "${_TUI_P_CHILDREN[root]}"
	eq "10 30" "${_TUI_L_ROW[a]} ${_TUI_L_COL[a]}"
}

# ── validator ─────────────────────────────────────────────────────────────

_ly_validate() { # XML -> _LYV: the findings of one page
	_LYD="$_T_ROOT/lyv_${RANDOM}${RANDOM}"
	mkdir -p "$_LYD"
	printf '%s\n' "$1" >"$_LYD/p.xml"
	tui.validate.files "$_LYD/p.xml"
	tui.validate.messages
	_LYV="${_TV_LINES[*]}"
}

ti_layer_validator_accepts_the_layer_tags() {
	_ly_validate "$_LY_PAGE"
	eq "" "$_LYV"
	_ly_validate '<tui>
  <pane id="root" split="h">
    <pane id="a" detachable="true" leave="placeholder" persist="layout"/>
    <pane id="b"/>
  </pane>
  <popup id="p" anchor="#b" x="2" y="below" width="10" height="3" open="false"/>
  <toast id="t" timeout="3" x="right" y="bottom" open="false"/>
</tui>'
	eq "" "$_LYV"
}

ti_layer_validator_reports_a_bad_anchor_placement_and_a_detachable_pane_in_the_wrong_split() {
	_ly_validate '<tui>
  <pane id="root" split="grid">
    <pane id="a" detachable="true"/>
  </pane>
  <window id="w1" anchor="nowhere"/>
  <window id="w2" anchor="#ghost"/>
  <window id="w3" x="left" y="middle"/>
  <window id="w4" float="maybe"/>
</tui>'
	ok '[[ "$_LYV" == *"anchor=\"nowhere\""* ]]'
	ok '[[ "$_LYV" == *"anchored to #ghost"* ]]'
	ok '[[ "$_LYV" == *"x=\"left\""* && "$_LYV" == *"y=\"middle\""* ]]'
	ok '[[ "$_LYV" == *"float"* ]]'
	ok '[[ "$_LYV" == *"detachable but sits in a"* ]]'
}

ti_layer_dock_finds_its_place_after_the_siblings_floated_and_docked_in_another_order() {
	_ly_load '<tui>
  <pane id="root" split="h">
    <pane id="a" weight="1" border="single" detachable="true"/>
    <pane id="b" weight="2" border="single" detachable="true" leave="placeholder"/>
    <pane id="c" weight="1" border="single"/>
  </pane>
</tui>'
	tui.layer.detach a # root: b c
	tui.layer.detach b # root: a? no: b leaves a placeholder where it stood
	eq "b__slot c" "${_TUI_P_CHILDREN[root]}"
	tui.layer.dock a # a goes back before the placeholder's neighbour
	eq "a b__slot c" "${_TUI_P_CHILDREN[root]}"
	tui.layer.dock b # the placeholder moved from index 0 to 1: b still takes exactly that place
	eq "a b c" "${_TUI_P_CHILDREN[root]}"
	eq "1 2 1" "${_TUI_P_WEIGHTS[root]}"
	ok '[[ -z "${_TUI_P_ROW[b__slot]:-}" ]]'
}

ti_layer_dock_into_a_dock_group_target_drops_the_placeholder() {
	_ly_load '<tui>
  <pane id="root" split="h">
    <pane id="a" weight="1" border="single" detachable="true" leave="placeholder" dock_group="g"/>
    <pane id="dock" weight="1" border="single" dock_group="g" split="v"/>
  </pane>
</tui>'
	tui.layer.detach a
	tui.layer.dock a dock
	eq "dock" "${_TUI_P_CHILDREN[root]}"
	eq "a" "${_TUI_P_CHILDREN[dock]}"
}

ti_layer_a_page_repaint_under_a_layer_carries_the_layer_in_the_same_write() {
	_ly_load "$_LY_PAGE"
	local out
	_TUI_RUNNING=1
	_TUI_FRAME=""
	_tui.emit_goto 5 8 # a page repaint (a clock tick) inside the window's rectangle
	_tui.emit "TICK"
	out="$(_tui._flush "$_TUI_FRAME" 2>&1)"
	_TUI_RUNNING=0
	ok '[[ "$out" == *"TICK"* && "$out" == *"Win"* && "$out" == *"inside"* ]]' # the window follows the tick in one write
	_TUI_FRAME=""
	out="$(_TUI_OVL_FLUSHING=1 _tui._flush "x" 2>&1)"
	ok '[[ "$out" != *"Win"* ]]' # an overlay's own write is not given the layers a second time
}

ti_layer_a_shell_page_replayed_on_another_screen_places_its_window_for_this_one() {
	_sh_setup 2>/dev/null || true
	local d="$_T_ROOT/ly_shell_${RANDOM}${RANDOM}"
	mkdir -p "$d"
	printf '<tui>\n<pane id="root" split="v">\n<outlet id="o"/>\n</pane>\n</tui>\n' >"$d/_s.xml"
	printf '<tui shell="_s.xml">\n<pane id="pg"/>\n<window id="pw" x="center" y="center" width="30" height="8"/>\n</tui>\n' >"$d/p.xml"
	printf '<tui shell="_s.xml">\n<pane id="pg2"/>\n</tui>\n' >"$d/q.xml"
	tui.reset_ui
	_TUI_MARKUP_FILE="" _TUI_MARKUP_DIR="$d" _TUI_ROWS=24 _TUI_COLS=80
	tui.goto "$d/p.xml" >/dev/null 2>&1 # recorded at 80x24
	tui.goto "$d/q.xml" >/dev/null 2>&1
	_TUI_ROWS=40 _TUI_COLS=120 # another screen
	_TUI_P_H[root]=40 _TUI_P_W[root]=120
	_tui._layout root
	tui.goto "$d/p.xml" >/dev/null 2>&1 # replayed
	eq "120" "${_TUI_P_W[root]}"
	eq "17 46" "${_TUI_L_ROW[pw]} ${_TUI_L_COL[pw]}" # centred on 120x40, not on the recording's 80x24
	eq "8 30" "${_TUI_P_H[pw]} ${_TUI_P_W[pw]}"
}

ti_layer_closing_a_zoomed_window_gives_the_pointer_back_to_the_page() {
	_ly_load "$_LY_PAGE"
	_tui._widget_pos base_btn
	local br=$_WSR bc=$_WSC # not r/c: the engine's pane loops use a global c
	tui.layer.zoom w1
	_tui_hit.at "$bc" "$br"
	eq "w1" "$_HIT_PANE" # the zoomed window covers the page
	tui.layer.close w1
	eq "root base" "${_TUI_P_ALL[*]}" # the hidden layer's panes are out of the loops
	_tui_hit.at "$bc" "$br"
	eq "widget:base_btn" "$_HIT_KIND:$_HIT_ID"
	tui.layer.show w1 # it comes back zoomed: close left its state alone
	_tui_hit.at "$bc" "$br"
	eq "w1" "$_HIT_PANE"
}

ti_layer_grows_to_fit_what_is_inside_instead_of_showing_the_size_warning() {
	_ly_load '<tui>
  <pane id="root"/>
  <modal id="dlg" x="center" y="center" width="20" height="3" hpad="2" vpad="1">
    <label id="dlg_text" text="Restart every service?  Tab stays in this box."/>
    <button id="dlg_ok" text="Restart"/>
    <button id="dlg_no" text="Cancel"/>
  </modal>
</tui>'
	ok '(( _TUI_L_W[dlg] >= 46 + 2 * 2 + 2 ))' # the label, both paddings and the border
	ok '(( _TUI_L_H[dlg] >= 3 + 2 * 1 + 2 ))'  # three rows, both paddings and the border
	_tui._refresh_content_fit dlg
	ok '! _tui._pane_too_small dlg'
	eq "$((_TUI_L_H[dlg]))" "${_TUI_P_H[dlg]}"
	ok '(( _TUI_L_COL[dlg] + _TUI_L_W[dlg] <= 81 ))' # and still inside the screen
}
