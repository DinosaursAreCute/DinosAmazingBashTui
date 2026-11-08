# validate_focus.t.sh - validator rules for focus attributes (lib/markup/tui_validate_rules.sh).

# _vf_check BODY (one element per line) -> findings in _VF (one "severity message" per line)
_vf_check() {
	local f="$HOME/vf.xml" i
	printf '<tui>\n<pane id="p">\n%s\n</pane>\n</tui>\n' "$1" >"$f"
	tui.validate.files "$f"
	_VF=""
	for i in "${!_TV_F_MSG[@]}"; do _VF+="${_TV_F_SEV[i]} ${_TV_F_MSG[i]}"$'\n'; done
}

ti_validate_tab_order_gap_warns() {
	_vf_check '<button id="a" pane="p" row="0" text="a" tab_order="1"/>
<button id="b" pane="p" row="1" text="b" tab_order="3"/>'
	match "$_VF" "warn tab_order skips 2"
}

ti_validate_tab_order_duplicate_warns() {
	_vf_check '<button id="a" pane="p" row="0" text="a" tab_order="1"/>
<button id="b" pane="p" row="1" text="b" tab_order="1"/>'
	match "$_VF" 'warn tab_order="1" is used by 2 widgets'
}

ti_validate_tab_order_clean_sequence_is_silent() {
	_vf_check '<button id="a" pane="p" row="0" text="a" tab_order="2"/>
<button id="b" pane="p" row="1" text="b" tab_order="1"/>
<button id="c" pane="p" row="2" text="c" tab_order="-1"/>
<button id="d" pane="p" row="3" text="d" tab_order="0"/>'
	eq "" "$_VF"
}

ti_validate_tabbable_without_focusable_is_an_error() {
	_vf_check "$(printf '%s\n' '<label id="l" pane="p" row="0" text="x" tabbable="true"/>')"
	match "$_VF" "error 'l' is tabbable but not focusable"
	_vf_check "$(printf '%s\n' '<label id="l" pane="p" row="0" text="x" tabbable="true" focusable="true"/>')"
	eq "" "$_VF"
}

ti_validate_focus_nav_value_is_checked() {
	_vf_check "$(printf '%s\n' '<button id="a" pane="p" row="0" text="a" focus_nav="sideways"/>')"
	match "$_VF" "error"
}
