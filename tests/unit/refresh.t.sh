# refresh.t.sh - lib/markup/tui_refresh.sh: tui.page.refresh rebuilds only the panes whose content changed.
# Loads the real demo pages (a build costs ~250 ms), so every case is ti_.

source "$REPO/share/demo/compose_callbacks.sh"

_rf_state_xml() { # VIEW : the compose page's state addon (seed tasks, default workspace) showing VIEW
	_CP_VIEW="$1" _CP_ENV=dev _CP_ROLE=guest _CP_BETA=false
	_cp_seed
	_cp_save
}

_rf_load() { # PAGE [EXAMPLE...] : load a demo page with these example addons already on disk
	local page="$1" n
	shift
	TUI_APP_CONF="$_T_ROOT/rf"
	rm -rf "$TUI_APP_CONF"
	mkdir -p "$TUI_APP_CONF/addons"
	_TUI_ADDON_DIRS=()
	for n; do cp "$REPO/share/demo/addon_examples/$n.xml" "$TUI_APP_CONF/addons/$n.xml"; done
	[[ "$page" == compose ]] && _rf_state_xml "${_RF_VIEW:-addons}"
	tui.reset_ui
	tui.load "$REPO/share/demo/$page.xml" 2>"$_T_ROOT/rf.err"
	_TUI_MARKUP_FILE="$REPO/share/demo/$page.xml"
}

_rf_enable() { cp "$REPO/share/demo/addon_examples/$1.xml" "$TUI_APP_CONF/addons/$1.xml"; }
_rf_disable() { : >"$TUI_APP_CONF/addons/$1.xml"; }

# _rf_time CMD... -> _RF_US : microseconds the command took
_rf_time() {
	local a=${EPOCHREALTIME//[!0-9]/}
	"$@"
	_RF_US=$((${EPOCHREALTIME//[!0-9]/} - a))
}

# _rf_state -> _RF_STATE : the built panes and widgets as sorted text (what a full load and a refresh must agree on)
_rf_state() {
	local a k out="" name
	for name in _TUI_W_TYPE _TUI_W_PANE _TUI_W_ROW _TUI_W_LABEL _TUI_W_ACTION _TUI_P_CHILDREN _TUI_P_TITLE _TUI_P_BORDER _TUI_P_HPAD _TUI_P_VPAD; do
		local -n arr="$name"
		for k in "${!arr[@]}"; do out+="$name[$k]=${arr[$k]}"$'\n'; done
		unset -n arr
	done
	_RF_STATE="$(sort <<<"$out")"$'\norder='"${_TUI_W_ORDER[*]}"
}

ti_refresh_example_addons_equal_a_full_load_and_a_change_outside_the_panes_falls_back_to_a_rebuild() {
	local n all=(banner toolbar retitle shout tidy) none refreshed called="" saved
	_rf_load compose
	_rf_state
	none="$_RF_STATE"
	ok '[[ -n "$_TUI_P_RAW" && -n "${_TUI_P_SIG_OWN[body]:-}" ]]' # the page carries what a refresh needs
	_TUI_W_VALUE[chk_banner]=1                                    # the user ticked a box: in a pane the addon does not touch
	_rf_enable banner
	_rf_time tui.page.refresh
	eq "label" "${_TUI_W_TYPE[banner_msg]:-}"
	eq 1 "${_TUI_W_VALUE[chk_banner]}" # outside the rebuilt pane: kept
	eq "$(cat "$_T_ROOT/rf.err")" ""
	ok '(( _RF_US < 100000 ))' # the page-switch budget, for the compute part (the redraw comes on top)
	# nothing changed since: nothing is rebuilt (the marker below would be replaced by the label's text from the page)
	_TUI_W_VALUE[banner_msg]="marker"
	tui.page.refresh
	eq "marker" "${_TUI_W_VALUE[banner_msg]}"
	# focus on a widget that an addon removes does not dangle
	_TUI_FOCUS_ID=btn_page
	_rf_enable tidy # replaces btn_page
	tui.page.refresh
	eq "" "$_TUI_FOCUS_ID"
	eq "button" "${_TUI_W_TYPE[tidy_swapped]}"
	eq "" "${_TUI_W_TYPE[btn_page]:-}"
	for n in "${all[@]}"; do _rf_enable "$n"; done
	tui.page.refresh
	_rf_state
	refreshed="$_RF_STATE"
	for n in "${all[@]}"; do _rf_disable "$n"; done
	tui.page.refresh
	_rf_state
	eq "$none" "$_RF_STATE" # all five on, then all off: back to the page as written
	_rf_load compose "${all[@]}"
	_rf_state
	eq "$_RF_STATE" "$refreshed" # the refreshed page is the page a full load builds
	# something outside the panes changed: the work goes to a rebuild of the whole page
	cat >"$TUI_APP_CONF/addons/outside.xml" <<'XML'
<addon id="outside" target="compose.xml" prefix="false">
  <append ref="tui"><button id="flat_btn" pane="body" row="9" text="flat" action="on_addon_click"/></append>
</addon>
XML
	saved="$(declare -f tui.page.rebuild)"
	tui.page.rebuild() { called="$*"; }
	tui.page.refresh
	eval "$saved"
	match "$called" "compose.xml"
}

_rf_full_load_state() { # PAGE -> _RF_STATE : a full load of PAGE with the addon files still on disk
	tui.reset_ui
	tui.load "$REPO/share/demo/$1.xml" 2>/dev/null
	_rf_state
}

ti_refresh_view_and_board_changes_equal_a_full_load() {
	local refreshed
	_RF_VIEW=board _rf_load compose
	tui.set inp_title "typed by the user"
	_CP_VIEW=cond _CP_ENV=prod _CP_ROLE=admin _CP_BETA=true # swap the whole view pane tree
	_cp_save
	tui.page.refresh
	eq "labellabellabel" "${_TUI_W_TYPE[acct_env_prod]:-}${_TUI_W_TYPE[acct_adm_prod]:-}${_TUI_W_TYPE[acct_beta_on]:-}" # the Workspace's conditionals took the values
	eq "" "${_TUI_W_TYPE[t0_st_open]:-}${_TUI_W_TYPE[btn_add]:-}"                                                       # the board is gone
	_CP_VIEW=board                                                                                                      # and back, with changed cards
	_cp_add "New card" "" high true
	_cp_complete_next
	_cp_toggle_block_next
	_cp_save
	tui.page.refresh
	_rf_state
	refreshed="$_RF_STATE"
	_rf_full_load_state compose
	eq "$_RF_STATE" "$refreshed"
	match "$refreshed" "_TUI_P_TITLE\\[t4_card\\]=New card"
	eq "$(cat "$_T_ROOT/rf.err")" ""
}

ti_nested_widgets_are_placed_from_the_panes_first_line() {
	printf '<tui><pane id="p"><label id="a" text="A"/><label id="b" text="B"/><button id="c" text="C" row="5"/><label id="d" text="D"/></pane></tui>' >"$_T_ROOT/nested.xml"
	tui.reset_ui
	tui.load "$_T_ROOT/nested.xml" 2>/dev/null
	eq "0 1 5 3" "${_TUI_W_ROW[a]} ${_TUI_W_ROW[b]} ${_TUI_W_ROW[c]} ${_TUI_W_ROW[d]}" # an explicit row wins; the next one follows document order
}

ti_nested_textarea_password_select_progress_list_table_are_built_like_the_four_basic_widgets() {
	printf '<tui><pane id="p"><label id="a" text="A"/><textarea id="t"/><password id="pw" label="P:"/><select id="s" items="x|y"/><progress id="pr" value="0"/><list id="li" items="a|b"/><table id="tb" columns="A|B" data="1|2"/></pane></tui>' >"$_T_ROOT/nested_wx.xml"
	tui.reset_ui
	tui.load "$_T_ROOT/nested_wx.xml" 2>"$_T_ROOT/nested_wx.err"
	eq "a t pw s pr li tb" "${_TUI_W_ORDER[*]}"
	eq "0 1 2 3 4 5 6" "${_TUI_W_ROW[a]} ${_TUI_W_ROW[t]} ${_TUI_W_ROW[pw]} ${_TUI_W_ROW[s]} ${_TUI_W_ROW[pr]} ${_TUI_W_ROW[li]} ${_TUI_W_ROW[tb]}"
	eq "p p" "${_TUI_W_PANE[t]} ${_TUI_W_PANE[tb]}"
	eq "" "$(cat "$_T_ROOT/nested_wx.err")" # no "missing id or pane" warning
}

ti_refresh_hands_its_expanded_tree_to_the_cache_rebuild_which_equals_a_full_build_without_parsing() {
	local file="$_T_ROOT/small.xml" marks="$_T_ROOT/parse.marks" called="" saved rebuild_saved tree full
	cat >"$file" <<'XML'
<tui>
  <template name="card"><label id="l" text="{{@t}}"/><if test="{{@t}}==b"><label id="only_b" text="b"/></if></template>
  <pane id="root" split="v">
    <pane id="a" weight="50"><for each="a b" as="t"><use template="card" id="c_{{@t}}" t="{{@t}}"/></for></pane>
    <pane id="z" weight="50"><label id="zl" text="before"/></pane>
  </pane>
</tui>
XML
	TUI_APP_CONF="$_T_ROOT/small"
	mkdir -p "$TUI_APP_CONF/addons"
	_TUI_ADDON_DIRS=()
	tui.reset_ui
	tui.load "$file" 2>/dev/null
	_TUI_MARKUP_FILE="$file"
	printf '<addon id="x" target="small.xml" prefix="false"><set ref="#zl" attr="text" value="after"/></addon>' >"$TUI_APP_CONF/addons/x.xml"
	saved="$(declare -f tui.page.rebuild)"
	tui.page.rebuild() { called="$*"; }
	_TUI_RUNNING=1 tui.page.refresh >/dev/null
	_TUI_RUNNING=0
	eval "$saved"
	eq "--quiet --expanded $file" "$called" # the refresh hands over the tree it just expanded
	: >"$marks"
	tree="$( # the background job's work, forked from this state, must not parse again
		tui.parse.file() { echo parsed >>"$marks"; }
		TUI_JOB_PREFIX="$_T_ROOT/tree."
		_tui_job.page_rebuild_expanded "$file" 2>/dev/null
		cat "${TUI_JOB_PREFIX}blob"
	)"
	eq "" "$(<"$marks")"
	full="$( # the entry a build from the page files makes
		TUI_JOB_PREFIX="$_T_ROOT/full."
		_tui_job.page_build "$file" 2>/dev/null
		cat "${TUI_JOB_PREFIX}blob"
	)"
	ok '[[ -n "$tree" ]]'
	eq "$full" "$tree"
	called=""
	rebuild_saved="$(declare -f tui.page.rebuild)"
	tui.page.rebuild() { called="$*"; }
	printf '<addon id="y" target="small.xml" prefix="false"><set ref="#zl" attr="text" value="again"/></addon>' >"$TUI_APP_CONF/addons/y.xml"
	_TUI_RUNNING=1 TUI_REFRESH_CACHE_JOB=0 tui.page.refresh >/dev/null
	_TUI_RUNNING=0
	eval "$rebuild_saved"
	eq "" "$called" # TUI_REFRESH_CACHE_JOB=0: no background job, the screen is still updated
	eq "again" "${_TUI_W_VALUE[zl]:-${_TUI_W_LABEL[zl]:-}}"
	rm -f "$TUI_APP_CONF/addons/y.xml"
}
