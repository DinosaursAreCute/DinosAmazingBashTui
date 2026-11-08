# output_style.t.sh - text painted into a pane (tui.set_text / tui.output) keeps the pane's style after an embedded reset.

t_output_pane_style_comes_back_after_a_reset_inside_the_text() {
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_P_ROW[po]=1 _TUI_P_COL[po]=1 _TUI_P_H[po]=5 _TUI_P_W[po]=30
	_TUI_P_BORDER[po]=none _TUI_P_BORDER_EXPL[po]=1 _TUI_P_HPAD[po]=0 _TUI_P_VPAD[po]=0 _TUI_P_SCROLL[po]=none
	_TUI_STYLE_FG[po_normal]="#dddddd"
	_TUI_STYLE_BG[po_normal]="#102030"
	tui.set_text po $'ab\e[1;31mCD\e[0mef\e[mgh'
	_tui._style_v po_normal
	local sty="$_SGR" res=$'\e[0m'
	_TUI_FRAME=""
	_tui._render_output_buf po
	ok '[[ -n "$sty" && "$_TUI_FRAME" == *"CD${res}${sty}ef"* ]]' # the bold red ends, the pane's colours return
	ok '[[ "$_TUI_FRAME" == *"ef${res}${sty}gh"* ]]'              # also for the short form ESC [ m
	ok '[[ "$_TUI_FRAME" == *"${sty}ab"* ]]'                      # and the line starts in them
}
