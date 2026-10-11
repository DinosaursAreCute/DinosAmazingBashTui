# chrome_footer.t.sh - lib/chrome/tui_footer.sh buffer-mode footer draw path (stage 0.3).

t_footer_draw_appends_to_frame_when_shown() {
	_TUI_FOOTER_ON=1
	_TUI_FOOTER_ITEMS="ctrl+q|Quit"
	_TUI_FOOTER_STAMP=""
	_TUI_FTR_PAINTED=""
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

# The bottom row belongs to the footer: once painted, an unchanged footer adds nothing until an erase, a resize or new content.
_footer_setup() {
	_TUI_FOOTER_ON=1
	_TUI_FOOTER_ITEMS="ctrl+q|Quit"
	_TUI_FOOTER_STAMP=""
	_TUI_FTR_PAINTED=""
	_TUI_ROWS=24
	_TUI_COLS=80
}

t_footer_second_draw_adds_nothing_while_unchanged() {
	_footer_setup
	_TUI_FRAME=""
	_tui_footer.draw
	ok '[[ -n "$_TUI_FRAME" ]]'
	_TUI_FRAME=""
	_tui_footer.draw
	eq "" "$_TUI_FRAME"
}

t_footer_redraws_after_an_erase() {
	_footer_setup
	_TUI_FRAME=""
	_tui_footer.draw
	erase.all >/dev/null
	_TUI_FRAME=""
	_tui_footer.draw
	ok '[[ "$_TUI_FRAME" == *"Quit"* ]]'
}

t_footer_redraws_when_the_content_or_the_size_changes() {
	_footer_setup
	_TUI_FRAME=""
	_tui_footer.draw
	_TUI_FOOTER_ITEMS="ctrl+q|Exit"
	_TUI_FRAME=""
	_tui_footer.draw
	ok '[[ "$_TUI_FRAME" == *"Exit"* ]]'
	_TUI_ROWS=30
	_TUI_FRAME=""
	_tui_footer.draw
	ok '[[ "$_TUI_FRAME" == *$'"'"'\e[30;1H'"'"'* ]]'
}

t_layer_draw_all_without_output_does_not_flush() {
	_footer_setup
	_TUI_FL_ORDER=(_tui_footer.draw) _TUI_FL_AMBIENT=([_tui_footer.draw]=1)
	_tui_layer.draw_all >/dev/null # paints the footer
	local gen=$_TUI_FLUSH_GEN out
	_tui_layer.draw_all >"$_T_ROOT/ov.out"
	out="$(<"$_T_ROOT/ov.out")"
	eq "" "$out" # no synchronized frame either
	eq "$gen" "$_TUI_FLUSH_GEN"
}

t_reverse_keys_default_tier_follows_its_inputs() {
	_tui_input.reverse_keys
	local before="${_REVK[tui.action.quit]:-}"
	ok '[[ -n "$before" ]]'
	local g="${_TUI_BIND_DEF_GROUP[$before]:-}"
	_tui_input.reverse_keys
	eq "$before" "${_REVK[tui.action.quit]:-}" # memo hit: same result
	_TUI_DEF_OFF[$g]=1 # the group is switched off: the memo must notice
	_tui_input.reverse_keys
	[[ "${_REVK[tui.action.quit]:-}" != "$before" || -z "$g" ]] || _t_fail "a switched-off default group was still shown"
}
