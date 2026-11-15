# nav.t.sh - <nav>: items become page buttons; the one for the current page wears the active class (lib/chrome/tui_nav.sh).

# _nv_site - a shell with a nav of three items and two pages, written to $_NVD
_nv_site() {
	_NVD="$_T_ROOT/nv_${RANDOM}${RANDOM}"
	mkdir -p "$_NVD"
	printf '%s\n' '.tst_item { fg: white; bg: #111111; }' '.tst_item:hover { bg: #222222; }' '.tst_on { fg: black; bg: #eeeeee; }' >"$_NVD/theme.css"
	printf '%s\n' '<tui>
  <theme src="theme.css"/>
  <pane id="root" split="h">
    <nav id="nv" weight="1" border="single" item_class="tst_item" active_class="tst_on">
      <item page="a.xml" text="Alpha" icon="A" shortcut="alt+1"/>
      <item page="b.xml" text="Beta" badge="(2)"/>
      <item page="c.xml" id="custom" text="Gamma" collapsed_text="G" class="tst_item"/>
    </nav>
    <outlet id="body" weight="4"/>
  </pane>
</tui>' >"$_NVD/shell.xml"
	printf '%s\n' '<tui shell="shell.xml"><pane id="pa"><label id="la" text="a"/></pane></tui>' >"$_NVD/a.xml"
	printf '%s\n' '<tui shell="shell.xml"><pane id="pb"><label id="lb" text="b"/></pane></tui>' >"$_NVD/b.xml"
	tui.reset_ui >/dev/null
	_TUI_ROWS=24 _TUI_COLS=80
	_TUI_MARKUP_DIR="$_NVD"
}

ti_nav_items_become_page_buttons_named_after_the_nav_and_the_page() {
	_nv_site
	tui.load "$_NVD/a.xml" >/dev/null 2>"$_NVD/err"
	eq "" "$(<"$_NVD/err")"
	eq "button button button" "${_TUI_W_TYPE[nv_a]} ${_TUI_W_TYPE[nv_b]} ${_TUI_W_TYPE[custom]}"
	eq "A Alpha" "${_TUI_W_LABEL[nv_a]}"
	eq "Beta (2)" "${_TUI_W_LABEL[nv_b]}"
	eq "A|Be|G" "${_TUI_W_COLLAPSED_TEXT[nv_a]}|${_TUI_W_COLLAPSED_TEXT[nv_b]}|${_TUI_W_COLLAPSED_TEXT[custom]}"
	eq "0 1 2 nv" "${_TUI_W_ROW[nv_a]} ${_TUI_W_ROW[nv_b]} ${_TUI_W_ROW[custom]} ${_TUI_W_PANE[nv_a]}"
	tui.reset_ui >/dev/null # the runner shares state between tests: leave no page or layer behind
}

ti_nav_item_of_the_current_page_wears_the_active_class_and_follows_goto() {
	_nv_site
	tui.load "$_NVD/a.xml" >/dev/null 2>&1
	eq "#eeeeee" "${_TUI_STYLE_BG[nv_a_normal]}"
	eq "#111111" "${_TUI_STYLE_BG[nv_b_normal]}"
	ok '[[ -z "${_TUI_STYLE_BG[nv_a_hover]:-}" ]]' # the active class has no :hover, so the base class's must not linger
	tui.goto "$_NVD/b.xml" >/dev/null 2>&1
	eq "#111111" "${_TUI_STYLE_BG[nv_a_normal]}"
	eq "#eeeeee" "${_TUI_STYLE_BG[nv_b_normal]}"
	eq "#222222" "${_TUI_STYLE_BG[nv_a_hover]:-}" # a got its base class back, hover included
	ok '[[ -z "${_TUI_STYLE_BG[nv_b_hover]:-}" ]]'
	tui.goto "$_NVD/a.xml" >/dev/null 2>&1
	eq "#eeeeee" "${_TUI_STYLE_BG[nv_a_normal]}"
	tui.reset_ui >/dev/null # the runner shares state between tests: leave no page or layer behind
}

ti_nav_item_shortcut_opens_the_page_and_outlives_a_page_switch() {
	_nv_site
	tui.load "$_NVD/a.xml" >/dev/null 2>&1
	match "$(tui.bind.list)" 'alt\+1.*_tui_goto_nv_a'
	tui.goto "$_NVD/b.xml" >/dev/null 2>&1
	match "$(tui.bind.list)" 'alt\+1.*_tui_goto_nv_a'
	tui.reset_ui >/dev/null # the runner shares state between tests: leave no page or layer behind
}

ti_nav_validator_checks_the_enums_and_dead_items() {
	_nav_validate '<tui>
  <nav id="n" orientation="x" active="sometimes">
    <item page="a.xml" text="A"/>
    <item text="Dead"/>
  </nav>
  <nav orientation="v"/>
</tui>'
	ok '[[ "$_LYV" == *"orientation"* && "$_LYV" == *"active"* ]]'
	ok '[[ "$_LYV" == *"Dead"* && "$_LYV" == *"does nothing"* ]]'
	ok '[[ "$_LYV" == *"nav"*"id"* ]]'
	_nav_validate '<tui>
  <nav id="n">
    <item page="a.xml" text="A" icon="i" shortcut="alt+1"/>
  </nav>
</tui>'
	eq "" "$_LYV"
}

# _nav_validate XML -> _LYV: the findings of one page
_nav_validate() {
	local d="$_T_ROOT/nav_v_$RANDOM$RANDOM"
	mkdir -p "$d"
	printf '%s\n' "$1" >"$d/p.xml"
	tui.validate.files "$d/p.xml"
	tui.validate.messages
	_LYV="${_TV_LINES[*]}"
}
