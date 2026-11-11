# goto_paint.t.sh - a page switch paints once: draws made while the page loads are covered by the frame tui.goto renders.

_gp_capture() { # CMD... -> _GP_OUT: what CMD sent through _tui.write
	local saved
	saved="$(declare -f _tui.write)"
	_GP_OUT=""
	_tui.write() { _GP_OUT+="$1"; }
	"$@"
	eval "$saved"
}

ti_goto_flush_is_dropped_while_the_page_loads_and_counted() {
	local gen=$_TUI_FLUSH_GEN
	_TUI_RUNNING=1 _TUI_DEFER_RENDER=1
	_gp_capture _tui._flush "abc"
	eq "" "$_GP_OUT"
	eq "$((gen + 1))" "$_TUI_FLUSH_GEN" # the paint diff still sees that something drew
	_TUI_DEFER_RENDER=0
	_gp_capture _tui._flush "abc"
	eq "abc" "$_GP_OUT"
	_TUI_RUNNING=0
}

ti_goto_flush_is_kept_when_nothing_renders_afterwards() {
	_TUI_RUNNING=0 _TUI_DEFER_RENDER=1 # before tui.run: tui.goto does not render, so nothing may be dropped
	_gp_capture _tui._flush "abc"
	eq "abc" "$_GP_OUT"
	_TUI_DEFER_RENDER=0
}

ti_render_settles_the_output_queued_before_it() {
	tui.reset_ui
	_TUI_PENDING_OUTPUT[root]=1
	_gp_capture tui.render
	eq "0" "${#_TUI_PENDING_OUTPUT[@]}" # the full frame drew every pane's content: no second repaint of it
}

# while a page loads under tui.goto, the draw entry points return before building anything: the frame tui.goto renders
# afterwards covers them, so composing their bytes only to drop them is wasted work
_gp_probe() { # ENTRY ARG... -> _GP_BUILT: how many times ENTRY composed a widget, pane border or output
	_GP_BUILT=0
	local saved
	saved="$(declare -f _tui._draw_widget_buf _tui._draw_pane_border_buf _tui._render_output_buf)"
	_tui._draw_widget_buf() { ((_GP_BUILT++)); }
	_tui._draw_pane_border_buf() { ((_GP_BUILT++)); }
	_tui._render_output_buf() { ((_GP_BUILT++)); }
	"$@"
	eval "$saved"
}

ti_goto_draw_entries_build_nothing_while_the_page_loads() {
	# other tests stub these one-line wrappers and leave the stub behind: put the library's definitions back
	_tui._draw_widgets_now() { _tui._draw_ids_now _tui._draw_widget_buf "$@"; }
	_tui._draw_pane_borders_now() { _tui._draw_ids_now _tui._draw_pane_border_buf "$@"; }
	_TUI_RUNNING=1 _TUI_DEFER_RENDER=1
	_gp_probe _tui._draw_widget w1
	eq "0" "$_GP_BUILT"
	_gp_probe _tui._draw_widgets_now w1 w2
	eq "0" "$_GP_BUILT"
	_gp_probe _tui._draw_pane_borders_now root
	eq "0" "$_GP_BUILT"
	_gp_probe _tui._draw_batch_now w1 w2
	eq "0" "$_GP_BUILT"
	_gp_probe _tui._render_output root
	eq "0" "$_GP_BUILT"
	_TUI_DEFER_RENDER=0
	_gp_probe _tui._draw_widgets_now w1
	eq "1" "$_GP_BUILT"
	_gp_probe _tui._draw_pane_borders_now root
	eq "1" "$_GP_BUILT"
	_TUI_RUNNING=0
}

# tui.focus composes the old and new widget and the pane borders itself, then flushes: while a page loads it keeps the focus
# state (and any scroll the reveal moved) but composes nothing
ti_goto_focus_keeps_the_state_and_composes_nothing_while_the_page_loads() {
	tui.reset_ui
	_TUI_W_TYPE[fb1]=button _TUI_W_PANE[fb1]=root
	_TUI_W_ORDER+=(fb1)
	_TUI_FOCUS_ID="" _TUI_PANE_FOCUS=""
	_TUI_RUNNING=1 _TUI_DEFER_RENDER=1
	_gp_probe tui.focus fb1
	eq "0" "$_GP_BUILT"
	eq "fb1" "$_TUI_FOCUS_ID"
	_TUI_FOCUS_ID=""
	_TUI_DEFER_RENDER=0
	_gp_probe tui.focus fb1
	ok '((_GP_BUILT > 0))' # outside a load it still draws
	_TUI_RUNNING=0
}

# an action that renders the whole screen has drawn the released button already, in its final state: the un-press redraw
# that follows would paint it, its pane's border and the old hover target a second time
ti_button_release_skips_the_unpress_redraw_after_a_full_render() {
	local saved
	saved="$(declare -f _tui._draw_widgets_now _tui._draw_pane_borders_now)"
	_GP_REDRAWS=0
	_tui._draw_widgets_now() { ((_GP_REDRAWS++)); }
	_tui._draw_pane_borders_now() { ((_GP_REDRAWS++)); }
	tui.reset_ui
	_TUI_W_TYPE[rb1]=button _TUI_W_PANE[rb1]=root
	_TUI_RUNNING=1
	_gp_act_renders() { ((_TUI_RENDER_SEQ++)); }
	_gp_act_quiet() { :; }
	_HIT=rb1
	_TUI_W_ACTION[rb1]=_gp_act_renders
	_tui_input.button_held release rb1
	eq "0" "$_GP_REDRAWS"
	_TUI_W_ACTION[rb1]=_gp_act_quiet
	_HIT=rb1
	_tui_input.button_held release rb1
	ok '((_GP_REDRAWS > 0))' # nothing was rendered: the un-press is still drawn
	_TUI_RUNNING=0
	eval "$saved"
}
