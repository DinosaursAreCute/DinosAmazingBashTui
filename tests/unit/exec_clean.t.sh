# Output cleaning for tui.exec panes: SGR stays, everything else goes, widths exclude the SGR bytes.

t_exec_clean_keeps_sgr_and_drops_other_csi() {
	_exec_clean_line $'a\033[1;31mred\033[0m\033[2Jb\033[K'
	eq $'a\033[1;31mred\033[0mb' "$_EXEC_CLEAN"
}

t_exec_clean_drops_osc_dcs_cr_and_two_byte_escapes() {
	_exec_clean_line $'\033]0;title\a1\033P9\033\\2\033M3\r4'
	eq "1234" "$_EXEC_CLEAN"
}

t_exec_clean_width_excludes_sgr() {
	_exec_clean_line $'\033[31mabc\033[0mde'
	eq 5 "$_EXEC_CLEAN_W"
}

t_exec_clean_unterminated_escape_is_dropped_not_hung() {
	_exec_clean_line $'x\033[12'
	eq "x[12" "$_EXEC_CLEAN"
}

t_fillrow_repeats_char_including_ampersand() {
	local out
	out="$(fillrow 1 1 '&' 3)"
	[[ "$out" == *'&&&' ]] || {
		echo "got: $out"
		return 1
	}
}

t_exec_clean_drops_charset_keypad_and_cursor_save_escapes() {
	_exec_clean_line $'\033(B\033[mdone\033=menu\033>\0337s\0338\033cx'
	eq $'\033[mdonemenusx' "$_EXEC_CLEAN"
}

_exec_wait_done() { # IID : tick until the instance has left "running" (max ~3 s)
	local i
	for ((i = 0; i < 60; i++)); do
		_exec_tick_one "$1" 2>/dev/null
		[[ "${_EXEC_STATUS[$1]}" != running ]] && return 0
		read -rt 0.05 <> <(:)
	done
	return 1
}

ti_exec_pipe_mode_streams_lines_and_exit_status_without_script() {
	TUI_EXEC_PTY=off
	tui.exec $'printf "one\\ntwo\\n"; exit 3' xp_out
	_exec_wait_done "$_TUI_EXEC_LAST_ID"
	local -n buf=_EXEC_PANE_BUF_xp_out
	eq "one" "${buf[0]}"
	eq "two" "${buf[1]}"
	eq 3 "${_EXEC_EXIT[$_TUI_EXEC_LAST_ID]}"
}

ti_exec_pipe_mode_forwards_stdin_through_the_fifo() {
	TUI_EXEC_PTY=off
	tui.exec 'read -r x; echo "got $x"' xp_in
	local iid="$_TUI_EXEC_LAST_ID"
	printf 'hello\n' >&"${_EXEC_FIFO_FD[$iid]}"
	_exec_wait_done "$iid"
	local -n buf=_EXEC_PANE_BUF_xp_in
	eq "got hello" "${buf[0]}"
}

t_exec_auto_mode_falls_back_to_pipes_without_script() {
	TUI_EXEC_PTY=auto
	_EXEC_PTY_KIND=none
	_exec_use_pty && return 1
	return 0
}
