# validate_size.t.sh - the validator on size tokens: bad tokens are errors, a bare number beside a unit or an unsized sibling is a warning.

ti_validator_warns_for_a_bare_number_beside_an_unsized_or_unit_sibling() {
	_validate_size_validate '<tui>
  <pane id="root" split="v">
    <pane id="a" height="6"/>
    <pane id="b"/>
    <pane id="c" height="8"/>
  </pane>
</tui>'
	ok '[[ "$_LYV" == *"size \"6\" is 6 shares"* && "$_LYV" == *"size \"8\" is 8 shares"* ]]'
	ok '[[ "$_LYV" == *"6c"* ]]'
}

ti_validator_accepts_cell_units_and_all_bare_siblings() {
	_validate_size_validate '<tui>
  <pane id="root" split="v">
    <pane id="a" height="6c"/>
    <pane id="b" height="1fr"/>
    <pane id="c" height="clamp(2,2,2)"/>
  </pane>
  <pane id="r2" split="h">
    <pane id="x" width="1"/>
    <pane id="y" width="3"/>
  </pane>
</tui>'
	eq "" "$_LYV"
}

ti_validator_rejects_a_size_that_is_not_a_token() {
	_validate_size_validate '<tui>
  <pane id="root" split="v">
    <pane id="a" height="six"/>
    <pane id="b" width="6px"/>
  </pane>
</tui>'
	ok '[[ "$_LYV" == *"height=\"six\""*"is not a size"* && "$_LYV" == *"width=\"6px\""* ]]'
}

# _validate_size_validate XML -> _LYV: the findings of one page
_validate_size_validate() {
	local d="$_T_ROOT/validate_size_v_$RANDOM$RANDOM"
	mkdir -p "$d"
	printf '%s\n' "$1" >"$d/p.xml"
	tui.validate.files "$d/p.xml"
	tui.validate.messages
	_LYV="${_TV_LINES[*]}"
}

ti_startup_check_skips_a_component_body_that_a_page_names() {
	local d="$_T_ROOT/vs_frag_$RANDOM"
	mkdir -p "$d"
	printf '%s\n' '<tui>' '  <component name="tile" src="tile.xml"/>' '  <pane id="root"/>' '</tui>' >"$d/home.xml"
	printf '%s\n' '<pane id="box"><label id="l" text="x"/></pane>' >"$d/tile.xml"
	printf '%s\n' '<pane id="orphan"/>' >"$d/orphan.xml" # no <tui> and nobody names it: still checked, and reported
	TUI_VALIDATE=1 _tui_validate.begin 0 "$d/home.xml" "$d/orphan.xml" "$d/tile.xml"
	eq "home.xml orphan.xml" "${_TV_PAGES[*]//$d\//}"
	_TV_PENDING=0
}

ti_text_captions_an_input_a_checkbox_and_a_select_like_label() {
	local d="$_T_ROOT/vs_text_$RANDOM"
	mkdir -p "$d"
	printf '%s\n' '<tui>' '  <pane id="root" split="v">' '    <checkbox id="c" text="Poll"/>' '    <input id="i" text="Name:"/>' '    <select id="s" text="Mode:" items="a|b" value="a"/>' '  </pane>' '</tui>' >"$d/p.xml"
	tui.reset_ui >/dev/null
	_TUI_MARKUP_DIR="$d"
	tui.load "$d/p.xml" >/dev/null 2>&1
	eq "Poll|Name:|Mode:" "${_TUI_W_LABEL[c]}|${_TUI_W_LABEL[i]}|${_TUI_W_LABEL[s]}"
	eq "a" "${_TUI_W_VALUE[s]}"
	tui.reset_ui >/dev/null # the runner shares state between tests: leave no page or layer behind
}

ti_update_puts_the_cursor_of_an_input_after_the_new_text() {
	local d="$_T_ROOT/vs_cur_$RANDOM"
	mkdir -p "$d"
	printf '%s\n' '<tui>' '  <pane id="root" split="v">' '    <input id="i" label="Name:"/>' '  </pane>' '</tui>' >"$d/p.xml"
	tui.reset_ui >/dev/null
	_TUI_MARKUP_DIR="$d"
	tui.load "$d/p.xml" >/dev/null 2>&1
	tui.update i "/api/items"
	eq 10 "${_TXC[i]}"
	tui.update i ""
	eq 0 "${_TXC[i]}"
	tui.reset_ui >/dev/null # the runner shares state between tests: leave no page or layer behind
}

ti_exists_answers_for_widgets_panes_and_layers() {
	local d="$_T_ROOT/vs_ex_$RANDOM"
	mkdir -p "$d"
	printf '%s\n' '<tui>' '  <pane id="root" split="v">' '    <pane id="inner"><label id="l" text="x"/></pane>' '  </pane>' '  <window id="w" width="10" height="4"/>' '</tui>' >"$d/p.xml"
	tui.reset_ui >/dev/null
	_TUI_MARKUP_DIR="$d"
	tui.load "$d/p.xml" >/dev/null 2>&1
	ok 'tui.exists l'
	ok 'tui.exists inner'
	ok 'tui.exists root'
	ok 'tui.exists w'
	ok '! tui.exists nothing'
	ok '! tui.exists ""'
	tui.reset_ui >/dev/null # the runner shares state between tests: leave no page or layer behind
}

ti_restyle_swaps_the_class_and_forgets_the_old_states() {
	local d="$_T_ROOT/vs_rs_$RANDOM"
	mkdir -p "$d"
	printf '%s\n' '.rs_a { fg: red; bg: black; }' '.rs_a:hover { bg: blue; }' '.rs_b { fg: green; }' >"$d/t.css"
	printf '%s\n' '<tui>' '  <theme src="t.css"/>' '  <pane id="root" split="v">' '    <button id="b" text="x" class="rs_a"/>' '  </pane>' '</tui>' >"$d/p.xml"
	tui.reset_ui >/dev/null
	_TUI_MARKUP_DIR="$d"
	tui.load "$d/p.xml" >/dev/null 2>&1
	eq "blue" "${_TUI_STYLE_BG[b_hover]:-}"
	tui.restyle b rs_b
	eq "green" "${_TUI_STYLE_FG[b_normal]}"
	eq "" "${_TUI_STYLE_BG[b_hover]:-}"
	ok '! tui.restyle nothing rs_b'
	ok '! tui.restyle b ""'
	tui.reset_ui >/dev/null # the runner shares state between tests: leave no page or layer behind
}
