# shell.t.sh - lib/markup/tui_shell.sh: pages of one shell swap inside its outlet; the shell stays (stage 3D-3).
# Builds real pages, so every case is ti_.

_sh_pages() { # DIR - one shell, two pages of it, one page without a shell
	local d="$1"
	mkdir -p "$d"
	cat >"$d/_shell.xml" <<'XML'
<tui>
  <pane id="root" split="v">
    <pane id="head" border="single" weight="1">
      <input id="search" placeholder="s"/>
    </pane>
    <outlet id="body" weight="4"/>
    <pane id="foot" border="single" weight="1">
      <button id="quit" text="quit"/>
    </pane>
  </pane>
</tui>
XML
	cat >"$d/pa.xml" <<'XML'
<tui shell="_shell.xml">
  <pane id="pa_main" border="single">
    <button id="pa_btn" text="a"/>
    <input id="pa_in" placeholder="x" keep_value="true"/>
  </pane>
</tui>
XML
	cat >"$d/pb.xml" <<'XML'
<tui shell="_shell.xml">
  <pane id="pb_main" border="single">
    <button id="pb_btn" text="b"/>
  </pane>
</tui>
XML
	cat >"$d/pc.xml" <<'XML'
<tui shell="_shell.xml" on_visit="_sh_visit">
  <pane id="pc_main" border="single">
    <button id="pc_btn" text="c"/>
  </pane>
</tui>
XML
	cat >"$d/pn.xml" <<'XML'
<tui>
  <pane id="root" border="single">
    <button id="pn_btn" text="n"/>
  </pane>
</tui>
XML
}

_sh_visit() { tui.button vis_btn pc_main 5 "made in on_visit" ""; } # what a page's on_visit does: widgets built after the page

_sh_setup() {
	TUI_HOME="$_T_ROOT/sh_home"
	_TUI_STORE=() _TUI_STORE_DEFAULT=() _TUI_STORE_DEFAULTED=() _TUI_STORE_FILE=() _TUI_STORE_LOADED=1
	tui.reset_ui
	_TUI_MARKUP_FILE=""
	_SHD="$_T_ROOT/sh_pages_${RANDOM}${RANDOM}"
	_sh_pages "$_SHD"
	_TUI_MARKUP_DIR="$_SHD"
	_TUI_ROWS=24 _TUI_COLS=80
}
_sh_go() { tui.goto "$_SHD/$1" >/dev/null 2>>"$_SHD/err"; }

ti_shell_pages_build_into_the_outlet_and_swap_without_touching_the_shell() {
	_sh_setup
	_sh_go pa.xml
	eq "$_SHD/_shell.xml" "$(tui.shell.file)"
	eq "head body foot" "${_TUI_P_CHILDREN[root]}"
	eq "pa_main" "${_TUI_P_CHILDREN[body]}"
	eq "search pa_btn pa_in quit" "${_TUI_W_ORDER[*]}"
	_TUI_W_VALUE[search]="query"
	_TUI_W_VALUE[pa_in]="typed"
	_tui_focus.ensure
	_TUI_FOCUS_ID=search
	_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[search]}"
	_sh_go pb.xml
	eq "pb_main" "${_TUI_P_CHILDREN[body]}"
	eq "query" "${_TUI_W_VALUE[search]}"
	eq search "$_TUI_FOCUS_ID"
	eq "search pb_btn quit" "${_TUI_W_ORDER[*]}"
	ok '[[ -z "${_TUI_W_TYPE[pa_btn]:-}" && -z "${_TUI_P_ROW[pa_main]:-}" ]]'
	_sh_go pa.xml
	eq "pa_main" "${_TUI_P_CHILDREN[body]}"
	eq "search pa_btn pa_in quit" "${_TUI_W_ORDER[*]}"
	eq "typed" "${_TUI_W_VALUE[pa_in]}"
	eq "" "$(<"$_SHD/err")"
}

ti_shell_a_page_without_a_shell_rebuilds_from_scratch() {
	_sh_setup
	_sh_go pa.xml
	_sh_go pn.xml
	eq "" "$(tui.shell.file)"
	eq "pn_btn" "${_TUI_W_ORDER[*]}"
	_sh_go pb.xml
	eq "$_SHD/_shell.xml" "$(tui.shell.file)"
	eq "search pb_btn quit" "${_TUI_W_ORDER[*]}"
}

# ── validator ─────────────────────────────────────────────────────────────

# _sh_validate FILE -> _SHV: the findings of one page as "severity message" lines
_sh_validate() {
	tui.validate.files "$1"
	tui.validate.messages
	_SHV="${_TV_LINES[*]}"
}

ti_shell_validator_accepts_a_shell_and_its_pages() {
	_sh_setup
	_sh_validate "$_SHD/pa.xml"
	eq "" "$_SHV"
	_sh_validate "$_SHD/_shell.xml"
	eq "" "$_SHV"
}

ti_shell_validator_reports_a_missing_shell_a_stray_outlet_and_shared_ids() {
	_sh_setup
	printf '<tui shell="nope.xml">\n<pane id="p"/>\n</tui>\n' >"$_SHD/x1.xml"
	_sh_validate "$_SHD/x1.xml"
	match "$_SHV" "cannot be read"
	printf '<tui shell="_shell.xml">\n<outlet id="o2"/>\n</tui>\n' >"$_SHD/x2.xml"
	_sh_validate "$_SHD/x2.xml"
	match "$_SHV" "outlet belongs in the shell file"
	ok '[[ "$_SHV" != *"this one has"* ]]'
	printf '<tui shell="_shell.xml">\n<pane id="head"/>\n</tui>\n' >"$_SHD/x3.xml"
	_sh_validate "$_SHD/x3.xml"
	match "$_SHV" "pane id 'head' is already used"
	printf '<tui>\n<outlet id="o1"/>\n<outlet id="o2"/>\n</tui>\n' >"$_SHD/x4.xml"
	_sh_validate "$_SHD/x4.xml"
	ok '[[ "$_SHV" == *"exactly one <outlet/>"* ]]'
	printf '<tui shell="_shell.xml">\n<pane id="z"/>\n</tui>\n' >"$_SHD/x5.xml"
	printf '<tui shell="x5.xml">\n<pane id="y"/>\n</tui>\n' >"$_SHD/x6.xml"
	_sh_validate "$_SHD/x6.xml"
	match "$_SHV" "cannot name a shell"
}

# ── tui.shell.file / tui.page.refresh ─────────────────────────────────────

t_shell_file_stores_prints_and_reports_through_its_status() {
	local v=x
	_TUI_SHELL_FILE=""
	tui.shell.file v && _t_fail "status 0 without a shell"
	eq "" "$v"
	eq "" "$(tui.shell.file)"
	_TUI_SHELL_FILE="/app/_shell.xml"
	tui.shell.file v
	eq "/app/_shell.xml" "$v"
	eq "/app/_shell.xml" "$(tui.shell.file)"
}

t_shell_page_refresh_hands_a_shell_page_to_a_background_rebuild() {
	local got="" saved
	saved="$(declare -f tui.page.rebuild)"
	tui.page.rebuild() { got="$*"; }
	_TUI_MARKUP_FILE="/app/pa.xml" _TUI_SHELL_FILE="/app/_shell.xml" _TUI_P_RAW="raw"
	tui.page.refresh
	eval "$saved"
	eq "--label Updating page... /app/pa.xml" "$got"
}

t_shell_scan_ignores_a_shell_attribute_quoted_in_a_comment() {
	local f="$_T_ROOT/sh_scan.xml"
	printf '<!-- a page opts in with <tui shell="_x.xml"> -->\n<tui>\n<pane id="a"/>\n</tui>\n' >"$f"
	_tui_shell.scan "$f" 1
	eq "" "$_SH_OF"
	printf '<!-- note -->\n<tui shell="_x.xml">\n</tui>\n' >"$f"
	_tui_shell.scan "$f" 1
	eq "$_T_ROOT/_x.xml" "$_SH_OF"
}

ti_shell_widgets_made_in_on_visit_are_neither_doubled_on_replay_nor_left_behind() {
	_sh_setup
	_sh_go pc.xml
	_sh_go pb.xml
	ok '[[ -z "${_TUI_W_TYPE[vis_btn]:-}" ]]'
	_sh_go pc.xml
	_sh_go pb.xml
	_sh_go pc.xml
	local -a hits=()
	local id
	for id in "${_TUI_W_ORDER[@]}"; do [[ "$id" == vis_btn ]] && hits+=("$id"); done
	eq 1 "${#hits[@]}"
	_sh_go pb.xml
	eq "search pb_btn quit" "${_TUI_W_ORDER[*]}"
}

ti_shell_first_goto_from_a_page_without_a_shell_builds_the_shell_and_the_page() {
	_sh_setup
	_sh_go pn.xml
	_sh_go pa.xml
	eq "$_SHD/_shell.xml" "$(tui.shell.file)"
	eq "pa_main" "${_TUI_P_CHILDREN[body]}"
	eq "search pa_btn pa_in quit" "${_TUI_W_ORDER[*]}"
}

ti_shell_demo_pages_all_use_the_shell_whose_menu_is_collapsible_and_resizable() {
	local p bad=""
	for p in "$REPO"/share/demo/*.xml; do
		[[ "$p" == @(*/_*|*/commands.xml) ]] || grep -q 'shell="_shell.xml"' "$p" || bad+="${p##*/} "
	done
	eq "" "$bad"
	tui.reset_ui
	tui.load "$REPO/share/demo/docu.xml" 2>/dev/null
	eq 1 "${_TUI_P_COLLAPSIBLE[nav]:-}"
	eq rail "${_TUI_P_COLLAPSE_TO[nav]:-}"
	eq x "${_TUI_P_RESIZABLE[nav]:-}"
}
