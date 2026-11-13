# Escape-sequence assembly (lib/tui.sh, _tui._read_escape_seq): where the bytes after ESC end.
# Input is fed through _TUI_PENDING_INPUT: a sequence that is not complete after its last byte would read on into the
# trailing X, so the leftover shows whether the reader stopped there instead of waiting for more.

# _es BYTES -> _SEQ _REST : the sequence read after ESC and what stays unread
_es() {
	_TUI_PENDING_INPUT="$1"
	_tui._read_escape_seq
	_SEQ="$_TUI_SEQ_BUF" _REST="$_TUI_PENDING_INPUT"
}

t_escape_seq_alt_digit_ends_after_the_digit() {
	_es "2X"
	eq "2" "$_SEQ"
	eq "X" "$_REST"
}

t_escape_seq_alt_with_any_plain_byte_ends_after_it() {
	local b
	for b in 0 9 / . , ';' - = ' ' '!' '~' $'\x7f' $'\r' $'\x01'; do
		_es "${b}X"
		eq "$b" "$_SEQ"
		eq "X" "$_REST"
	done
}

t_escape_seq_alt_letter_still_ends_after_the_letter() {
	_es "sX"
	eq "s" "$_SEQ"
	eq "X" "$_REST"
}

t_escape_seq_csi_runs_to_its_final_byte() {
	_es "[1;5AX"
	eq "[1;5A" "$_SEQ"
	eq "X" "$_REST"
	_es "[200~X"
	eq "[200~" "$_SEQ"
	_es "[55;3uX"
	eq "[55;3u" "$_SEQ"
}

t_escape_seq_sgr_mouse_report_is_read_whole() {
	_es "[<0;5;3MX"
	eq "[<0;5;3M" "$_SEQ"
	eq "X" "$_REST"
}

t_escape_seq_ss3_key_is_two_bytes() {
	_es "OPX"
	eq "OP" "$_SEQ"
	eq "X" "$_REST"
}

t_escape_seq_prefixed_escape_keeps_the_sequence_together() {
	_es $'\e[AX'
	eq $'\e[A' "$_SEQ"
	eq "X" "$_REST"
}
