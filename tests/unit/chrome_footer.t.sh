# chrome_footer.t.sh - lib/chrome/tui_footer.sh buffer-mode footer draw path (stage 0.3).

t_footer_draw_appends_to_frame_when_shown() {
	_TUI_FOOTER_ON=1
	_TUI_FOOTER_ITEMS="ctrl+q|Quit"
	_TUI_FOOTER_STAMP=""
	_TUI_ROWS=24
	_TUI_COLS=80
	_TUI_FRAME="prefix:"
	_tui_footer.draw
	ok '[[ "$_TUI_FRAME" == prefix:$'"'"'\e7\e[?7l\e[24;1H'"'"'*$'"'"'\e[K\e[?7h\e8'"'"' ]]'
	ok '[[ "$_TUI_FRAME" == *"Quit"* ]]'
}

t_footer_draw_appends_nothing_when_hidden() {
	_TUI_FOOTER_ON=0
	_TUI_FRAME="prefix:"
	_tui_footer.draw
	eq "prefix:" "$_TUI_FRAME"
}
