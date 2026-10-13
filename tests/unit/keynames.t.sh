# Key decoding (lib/input/tui_input.sh, _tui_input.name_seq): what a terminal's byte sequence is called.

# _kn SEQ -> _N : the key name of the bytes after ESC
_kn() {
	_tui_input.name_seq "$1"
	_N=$_KEY
}

t_keys_esc_plus_char_is_alt_char() {
	_kn "/"
	eq "alt+/" "$_N"
	_kn "7"
	eq "alt+7" "$_N"
}

t_keys_csi_u_with_modifiers() {
	_kn "[55;3u"
	eq "alt+7" "$_N"
	_kn "[55;4u"
	eq "alt+shift+7" "$_N"
	_kn "[97;5u"
	eq "ctrl+a" "$_N"
}

t_keys_a_reported_shifted_key_replaces_the_shifted_chord() {
	_kn "[55:47;4u" # alt+shift+7 on a German layout: the terminal says it made "/"
	eq "alt+/" "$_N"
	_kn "[55:47;2u" # shift+7
	eq "/" "$_N"
}

t_keys_a_shifted_letter_keeps_the_shift_chord() {
	_kn "[97:65;4u"
	eq "alt+shift+a" "$_N"
	_kn "[97:65;2u"
	eq "A" "$_N"
}

t_keys_event_type_suffix_does_not_drop_the_modifiers() {
	_kn "[55;4:1u"
	eq "alt+shift+7" "$_N"
	_kn "[55;3:2u"
	eq "alt+7" "$_N"
}

t_keys_a_release_event_is_not_a_key() {
	_kn "[55;3:3u"
	eq "" "$_N"
}

t_keys_modify_other_keys_form() {
	_kn "[27;3;47~"
	eq "alt+/" "$_N"
}

# ── the Settings page lists every binding (share/defaults/pages/settings_callbacks.sh) ──

_kn_settings_rows() {
	source "$TUI_DEFAULTS_DIR/pages/settings_callbacks.sh"
	_dset_build
}

t_settings_keybinds_lists_default_bindings_without_being_told() {
	_kn_settings_rows
	local i found=0
	for i in "${!S_KEY[@]}"; do
		[[ "${S_CAT[i]}" == keybinds && "${S_KEY[i]}" == bind.* && "${S_TITLE[i]}" == "Next link" ]] || continue
		_dset_value "${S_KEY[i]}"
		match "$_DSET_V" 'alt\+j'
		found=1
	done
	eq 1 "$found"
}

t_settings_keybinds_lists_code_and_user_bindings() {
	tui.bind ctrl+e "my_fn" --desc "My own action"
	tui.bind ctrl+f "other_fn" --user --desc "yours"
	_kn_settings_rows
	local i titles=" "
	for i in "${!S_KEY[@]}"; do
		[[ "${S_CAT[i]}" == keybinds && "${S_KEY[i]}" == bind.* ]] && titles+="${S_TITLE[i]}|"
	done
	match "$titles" 'My own action'
	match "$titles" 'yours'
}

t_settings_keybinds_row_shows_the_keys_of_one_command_together() {
	tui.bind ctrl+e "my_fn" --desc "Two keys"
	tui.bind ctrl+r "my_fn" --desc "Two keys"
	_kn_settings_rows
	local i
	for i in "${!S_KEY[@]}"; do
		[[ "${S_CAT[i]}" == keybinds && "${S_KEY[i]}" == bind.* && "${S_TITLE[i]}" == "Two keys" ]] || continue
		_dset_value "${S_KEY[i]}"
		match "$_DSET_V" 'ctrl\+e'
		match "$_DSET_V" 'ctrl\+r'
		return 0
	done
	_t_fail "no row for the command"
}

# ── the raw bytes of the last input (tui.get.raw_input) ──

t_raw_input_shows_an_escape_sequence_in_caret_notation() {
	_tui_input.key_event "" "[55;4u"
	eq '^[[55;4u' "$(tui.get.raw_input)"
}

t_raw_input_shows_a_plain_key_and_control_characters() {
	_tui_input.key_event "a" ""
	eq 'a' "$(tui.get.raw_input)"
	_tui_input.key_event $'\x01' ""
	eq '^A' "$(tui.get.raw_input)"
	_tui_input.key_event $'\x7f' ""
	eq '^?' "$(tui.get.raw_input)"
}

t_raw_input_shows_a_bare_escape() {
	_tui_input.key_event "" ""
	eq '^[' "$(tui.get.raw_input)"
}

# ── mouse buttons beyond left/middle/right (SGR bit 128: buttons 8-11) ──

_km() { # BTN END -> _N
	_tui_input.name_mouse "$1" "$2"
	_N=$_KEY
}

t_mouse_side_buttons_are_not_left_or_middle() {
	_km 128 M
	eq "mouse:side1" "$_N"
	eq "side1" "$TUI_EVENT_BUTTON"
	_km 129 M
	eq "mouse:side2" "$_N"
	_km 130 M
	eq "mouse:side3" "$_N"
	_km 131 M
	eq "mouse:side4" "$_N"
}

t_mouse_side_button_drag_and_release() {
	_km 160 M # 128 + 32: motion with side button 1 held
	eq "drag:side1" "$_N"
	_km 128 m
	eq "release" "$_N"
}

t_mouse_the_three_classic_buttons_are_unchanged() {
	_km 0 M
	eq "mouse:left" "$_N"
	_km 1 M
	eq "mouse:middle" "$_N"
	_km 2 M
	eq "mouse:right" "$_N"
	_km 64 M
	eq "wheel:up" "$_N"
	_km 35 M
	eq "" "$_N"
}

t_mouse_a_side_button_press_does_not_jump_the_scrollbar() {
	_scroll_pane_setup p 10 20 v
	_TUI_P_CHILDREN[p]=""
	_TUI_W_ORDER=(w)
	_TUI_W_PANE[w]=p _TUI_W_ROW[w]=29 _TUI_W_HEIGHT[w]=1
	unset "_TUI_PANE_CONTENT[p]" "_TUI_P_LINES[p]"
	_TUI_P_CONTENT_H[p]=30
	_TUI_RUNNING=0
	TUI_EVENT_ZONE=scrollbar TUI_EVENT_ZONE_ID=p TUI_EVENT_ZONE_ARG=v TUI_EVENT_KEY=mouse:left
	TUI_EVENT_X=20 TUI_EVENT_Y=6 TUI_EVENT_PANE=p TUI_EVENT_WIDGET="" TUI_EVENT_RAWBTN=128
	tui.action.click
	eq 0 "${_TUI_P_SOFF_V[p]:-0}"
	TUI_EVENT_RAWBTN=0
	tui.action.click
	ok '((_TUI_P_SOFF_V[p] > 0))'
}
