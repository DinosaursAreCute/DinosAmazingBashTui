# refresh.t.sh - lib/markup/tui_refresh.sh: tui.page.refresh rebuilds only the panes whose content changed.
# Loads the real demo pages (a build costs ~250 ms), so every case is ti_.

_rf_load() { # PAGE [EXAMPLE...] : load a demo page with these example addons already on disk
	local page="$1" n
	shift
	TUI_APP_CONF="$_T_ROOT/rf"
	rm -rf "$TUI_APP_CONF"
	mkdir -p "$TUI_APP_CONF/addons"
	_TUI_ADDON_DIRS=()
	for n; do cp "$REPO/share/demo/addon_examples/$n.xml" "$TUI_APP_CONF/addons/$n.xml"; done
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

ti_refresh_enabling_an_addon_is_fast_and_touches_only_what_it_changes() {
	_rf_load addons
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
}

ti_refresh_result_equals_a_full_load_for_all_five_addons_and_for_none() {
	local n all=(banner toolbar retitle shout tidy)
	_rf_load addons
	_rf_state
	local none="$_RF_STATE"
	for n in "${all[@]}"; do _rf_enable "$n"; done
	_rf_time tui.page.refresh
	_rf_state
	local refreshed="$_RF_STATE"
	for n in "${all[@]}"; do _rf_disable "$n"; done
	tui.page.refresh
	_rf_state
	eq "$none" "$_RF_STATE" # all five on, then all off: back to the page as written
	_rf_load addons "${all[@]}"
	_rf_state
	eq "$_RF_STATE" "$refreshed"
}

ti_refresh_generated_page_equals_a_full_load_and_keeps_the_control_panel() {
	local f="$_T_ROOT/gen_values.xml" refreshed
	_rf_load generated
	tui.set inp_cards "typed by the user"
	cat >"$f" <<'XML'
<addon id="gen_values" target="generated.xml" prefix="false">
  <set ref="#cards" attr="count" value="5"/>
  <set ref="#cards > use" attr="title" value="Many"/>
  <set ref="#cards > use" attr="items" value="3"/>
  <set ref="#cards > use" attr="compact" value="true"/>
</addon>
XML
	cp "$f" "$TUI_APP_CONF/addons/gen_values.xml"
	tui.page.refresh
	_rf_state
	refreshed="$_RF_STATE"
	eq "typed by the user" "$(tui.get inp_cards)" # the control panel is not part of the regenerated pane
	tui.reset_ui                                  # a full load with the same addon file still on disk
	tui.load "$REPO/share/demo/generated.xml" 2>/dev/null
	_rf_state
	eq "$_RF_STATE" "$refreshed"
	match "$refreshed" "_TUI_P_TITLE\\[card4_c\\]=Many #4"
}

ti_refresh_falls_back_to_a_rebuild_when_something_outside_the_panes_changes() {
	local called="" saved
	_rf_load addons
	cat >"$TUI_APP_CONF/addons/outside.xml" <<'XML'
<addon id="outside" target="addons.xml" prefix="false">
  <append ref="tui"><button id="flat_btn" pane="body" row="9" text="flat" action="on_addon_click"/></append>
</addon>
XML
	saved="$(declare -f tui.page.rebuild)"
	tui.page.rebuild() { called="$*"; }
	tui.page.refresh
	eval "$saved"
	match "$called" "addons.xml"
}

ti_nested_widgets_are_placed_from_the_panes_first_line() {
	printf '<tui><pane id="p"><label id="a" text="A"/><label id="b" text="B"/><button id="c" text="C" row="5"/><label id="d" text="D"/></pane></tui>' >"$_T_ROOT/nested.xml"
	tui.reset_ui
	tui.load "$_T_ROOT/nested.xml" 2>/dev/null
	eq "0 1 5 3" "${_TUI_W_ROW[a]} ${_TUI_W_ROW[b]} ${_TUI_W_ROW[c]} ${_TUI_W_ROW[d]}" # an explicit row wins; the next one follows document order
}
