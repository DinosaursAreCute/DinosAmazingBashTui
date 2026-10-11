# store_disk.t.sh - page-state store, disk persistence and focus keeping (lib/state/tui_store.sh): the data-only
# file, load / flush rules, persist="disk", keep_focus, focus_on_enter, and the validator rules for them.

# _sd_setup - an empty store and a fresh TUI_HOME inside the runner root; _SDH is its path
_sd_setup() {
	_SDH="$_T_ROOT/sd_home_${RANDOM}${RANDOM}"
	mkdir -p "$_SDH"
	TUI_HOME="$_SDH"
	_TUI_STORE=() _TUI_STORE_DEFAULT=() _TUI_STORE_DEFAULTED=() _TUI_STORE_FILE=()
	_TUI_STORE_LOADED="" _TUI_STORE_DIRTY="" _TUI_STORE_ARMED=""
	_TUI_W_KEEP=() _TUI_W_DISK=() _TUI_P_DISK=() _TUI_P_DISK_STATE="" _TUI_P_KEEP_STATE="" _TUI_W_KEEPFOCUS=()
	_TUI_P_FOCUS_ON_ENTER="" _TUI_FOCUS_ID=""
	_TUI_MARKUP_FILE="/app/pa.xml"
}
# _sd_w ID TYPE - a widget as the builders leave it
_sd_w() {
	_TUI_W_TYPE[$1]="$2" _TUI_W_VALUE[$1]=""
	[[ " ${_TUI_W_ORDER[*]} " == *" $1 "* ]] || _TUI_W_ORDER+=("$1")
}
# _sd_file LINE... - writes the disk file with the current header and the given raw lines
_sd_file() {
	mkdir -p "$_SDH/state"
	{
		printf '# dabt-state 1\n'
		printf '%s\n' "$@"
	} >"$_SDH/state/store"
}
_sd_tab() {
	local IFS=$'\t'
	printf '%s' "$*"
}

# ── escaping ─────────────────────────────────────────────────────────────

t_store_disk_escape_round_trip() {
	local v
	for v in "" " lead" "trail " "a	b" $'a\nb' $'a\r\nb' 'back\slash' '\n' '\\' 'a|b' 'p%q' 'häß €' $'\\\t\n' 'end\'; do
		_tui_store.esc "$v"
		[[ "$_SE" != *$'\t'* && "$_SE" != *$'\n'* && "$_SE" != *$'\r'* ]] || _t_fail "esc left a control char in [$_SE]"
		_tui_store.unesc "$_SE"
		eq "$v" "$_SE"
	done
}

t_store_disk_unesc_keeps_an_unknown_escape() {
	_tui_store.unesc 'a\qb\'
	eq 'a\qb\' "$_SE"
}

# ── load ─────────────────────────────────────────────────────────────────

ti_store_disk_missing_file_is_an_empty_store() {
	_sd_setup
	_tui_store.load_disk
	eq 0 "${#_TUI_STORE_FILE[@]}"
	eq 1 "$_TUI_STORE_LOADED"
}

ti_store_disk_unreadable_file_is_an_empty_store() {
	_sd_setup
	mkdir -p "$_SDH/state/store"
	_tui_store.load_disk
	eq 0 "${#_TUI_STORE_FILE[@]}"
}

ti_store_disk_load_keeps_only_the_valid_lines() {
	_sd_setup
	local big
	printf -v big '%*s' 102400 ''
	_sd_file "$(_sd_tab pa.xml name value hello)" \
		"$(_sd_tab pa.xml name cursor 3 extra)" \
		"$(_sd_tab pa.xml name)" \
		"$(_sd_tab pa.xml name bogus 1)" \
		"$(_sd_tab pa.xml name 'value cursor' 1)" \
		"$(_sd_tab '' name value 1)" \
		"$(_sd_tab pa.xml big value "$big")" \
		"" "not a record" \
		"$(_sd_tab pb.xml '' focus b2)" \
		"$(_sd_tab pa.xml empty value '')"
	_tui_store.load_disk
	eq 3 "${#_TUI_STORE_FILE[@]}"
	_tui_store.key pa.xml name value
	eq hello "${_TUI_STORE_FILE[$_SK]}"
	_tui_store.key pb.xml "" focus
	eq b2 "${_TUI_STORE_FILE[$_SK]}"
	_tui_store.key pa.xml empty value
	eq "" "${_TUI_STORE_FILE[$_SK]-x}"
}

ti_store_disk_unknown_header_loads_nothing() {
	_sd_setup
	mkdir -p "$_SDH/state"
	printf '# dabt-state 2\n%s\n' "$(_sd_tab pa.xml name value x)" >"$_SDH/state/store"
	_tui_store.load_disk
	eq 0 "${#_TUI_STORE_FILE[@]}"
	_sd_setup
	mkdir -p "$_SDH/state"
	printf '%s\n' "$(_sd_tab pa.xml name value x)" >"$_SDH/state/store"
	_tui_store.load_disk
	eq 0 "${#_TUI_STORE_FILE[@]}"
}

ti_store_disk_last_line_without_newline_is_read() {
	_sd_setup
	mkdir -p "$_SDH/state"
	printf '# dabt-state 1\n%s' "$(_sd_tab pa.xml name value tail)" >"$_SDH/state/store"
	_tui_store.load_disk
	_tui_store.key pa.xml name value
	eq tail "${_TUI_STORE_FILE[$_SK]}"
}

ti_store_disk_loads_once() {
	_sd_setup
	_sd_file "$(_sd_tab pa.xml name value one)"
	tui.store.get pa.xml name value
	_sd_file "$(_sd_tab pa.xml name value two)"
	tui.store.get pa.xml name value
	tui.store.set pa.xml x value 1
	_tui_store.key pa.xml name value
	eq one "${_TUI_STORE_FILE[$_SK]}"
}

# ── security: the file is data ───────────────────────────────────────────

ti_store_disk_hostile_text_is_stored_and_loaded_as_text() {
	_sd_setup
	local mark="$_SDH/PWNED" v id n=0 line="" i
	local -a vals=('$(touch '"$mark"')' '`touch '"$mark"'`' 'a; touch '"$mark" '${x[$(touch '"$mark"')]}' '$((a[$(touch '"$mark"')]))' '"; touch '"$mark"'; "')
	_TUI_P_DISK_STATE=1
	for v in "${vals[@]}"; do
		id="$v"
		_tui_store.key "p$n.xml" "$id" value
		_tui_store.disk_put "$v"
		((n++))
	done
	tui.store.flush
	_TUI_STORE_FILE=() _TUI_STORE_LOADED=""
	_tui_store.load_disk
	eq "${#vals[@]}" "${#_TUI_STORE_FILE[@]}"
	n=0
	for v in "${vals[@]}"; do
		_tui_store.key "p$n.xml" "$v" value
		eq "$v" "${_TUI_STORE_FILE[$_SK]-MISSING}"
		((n++))
	done
	tui.page.reset p0.xml 2>/dev/null
	_tui_store.disk_drop p1.xml "${vals[1]}"
	_tui_store.disk_drop p2.xml
	ok '[[ ! -e "$mark" ]]'
	for i in "$_SDH"/PWNED*; do [[ -e "$i" ]] && _t_fail "marker created: $i"; done
}

ti_store_disk_load_never_executes_anything() {
	_sd_setup
	local mark="$_SDH/PWNED"
	_sd_file "$(_sd_tab 'pa.xml$(touch '"$mark"')' '`touch '"$mark"'`' value '$(touch '"$mark"')')" \
		"$(_sd_tab pa.xml '${x[$(touch '"$mark"')]}' value 'x')"
	tui.store.get pa.xml name value
	tui.store.has pa.xml name
	_tui_store.disk_drop 'pa.xml$(touch '"$mark"')'
	_tui_store.disk_drop pa.xml '${x[$(touch '"$mark"')]}'
	ok '[[ ! -e "$mark" ]]'
	eq 0 "${#_TUI_STORE_FILE[@]}"
}

# ── write ────────────────────────────────────────────────────────────────

ti_store_disk_flush_writes_a_private_file_in_a_private_folder() {
	_sd_setup
	_TUI_P_DISK_STATE=1
	_tui_store.key pa.xml name value
	_tui_store.disk_put $'a\tb\nc\\'
	tui.store.flush
	local f
	tui.store.file >/dev/null
	f="$_SDH/state/store"
	eq "$f" "$(tui.store.file)"
	ok '[[ -f "$f" ]]'
	eq 600 "$(stat -c %a "$f")"
	eq 700 "$(stat -c %a "$_SDH/state")"
	local l1 l2
	{
		IFS= read -r l1
		IFS= read -r l2
	} <"$f"
	eq "# dabt-state 1" "$l1"
	eq "pa.xml"$'\t'"name"$'\t'"value"$'\t''a\tb\nc\\' "$l2"
	eq "" "$(compgen -G "$_SDH/state/store.tmp.*")"
}

ti_store_disk_flush_round_trips_through_load() {
	_sd_setup
	_TUI_P_DISK_STATE=1
	local -a vals=("" " x " $'a\tb' $'l1\nl2' '\\' 'a|b' 'ü€')
	local n=0 v
	for v in "${vals[@]}"; do
		_tui_store.key "p|$n%.xml" "i|$n" value
		_tui_store.disk_put "$v"
		((n++))
	done
	tui.store.flush
	_TUI_STORE_FILE=() _TUI_STORE_LOADED=""
	_tui_store.load_disk
	n=0
	for v in "${vals[@]}"; do
		_tui_store.key "p|$n%.xml" "i|$n" value
		eq "$v" "${_TUI_STORE_FILE[$_SK]-MISSING}"
		((n++))
	done
}

ti_store_disk_flush_only_when_dirty() {
	_sd_setup
	_tui_store.load_disk
	_tui_store.flush_disk
	ok '[[ ! -e "$_SDH/state/store" ]]'
	_TUI_P_DISK_STATE=1
	_tui_store.disk_set pa.xml name value x
	eq 1 "$_TUI_STORE_DIRTY"
	_tui_store.flush_disk
	eq "" "$_TUI_STORE_DIRTY"
	ok '[[ -f "$_SDH/state/store" ]]'
	rm -f "$_SDH/state/store"
	_tui_store.disk_set pa.xml name value x # same value: not a change
	eq "" "$_TUI_STORE_DIRTY"
	_tui_store.flush_disk
	ok '[[ ! -e "$_SDH/state/store" ]]'
	_tui_store.disk_set pa.xml name value y
	_tui_store.flush_disk
	ok '[[ -f "$_SDH/state/store" ]]'
}

ti_store_disk_default_value_is_not_written() {
	_sd_setup
	_TUI_P_DISK_STATE=1
	_tui_store.key pa.xml name value
	_TUI_STORE_DEFAULT["$_SK"]=dflt
	_tui_store.disk_set pa.xml name value dflt
	eq "" "$_TUI_STORE_DIRTY"
	_tui_store.disk_set pa.xml name value other
	eq 1 "$_TUI_STORE_DIRTY"
	_TUI_STORE_DIRTY=""
	_tui_store.disk_set pa.xml name value dflt # overwrites what the file holds
	eq 1 "$_TUI_STORE_DIRTY"
	eq dflt "${_TUI_STORE_FILE[$_SK]}"
}

ti_store_disk_session_items_never_reach_the_file() {
	_sd_setup
	_sd_w sess input
	_sd_w disk input
	_tui_store.build_widget sess true ""
	_tui_store.build_widget disk true disk
	_TUI_W_VALUE[sess]=s _TUI_W_VALUE[disk]=d
	_tui_store.save_page
	tui.store.get pa.xml sess value
	eq s "$REPLY"
	_tui_store.flush_disk
	local text
	text="$(<"$_SDH/state/store")"
	match "$text" $'pa.xml\tdisk\tvalue\td'
	[[ "$text" != *sess* ]] || _t_fail "session item in the file"
}

ti_store_disk_persist_disk_implies_keeping() {
	_sd_setup
	_sd_w a input
	_tui_store.build_widget a "" disk
	ok '[[ -n "${_TUI_W_KEEP[a]:-}" && -n "${_TUI_W_DISK[a]:-}" ]]'
	_tui_store.build_widget b false disk
	ok '[[ -z "${_TUI_W_KEEP[b]:-}" ]]'
	_tui_store.build_pane p "" disk
	ok '[[ -n "${_TUI_P_KEEP_SIZE[p]:-}" && -n "${_TUI_P_KEEP_COLLAPSED[p]:-}" && -n "${_TUI_P_DISK[p]:-}" ]]'
	_tui_store.build_page "" disk ""
	eq "1 1" "$_TUI_P_KEEP_STATE $_TUI_P_DISK_STATE"
}

ti_store_disk_restore_merges_the_file_for_disk_items_only() {
	_sd_setup
	_sd_file "$(_sd_tab pa.xml dk value fromfile)" "$(_sd_tab pa.xml se value fromfile)"
	_sd_w dk input
	_sd_w se input
	_tui_store.build_widget dk true disk
	_tui_store.build_widget se true ""
	_tui_store.restore_page
	eq "fromfile " "${_TUI_W_VALUE[dk]} ${_TUI_W_VALUE[se]}"
	ok '! tui.store.get pa.xml se value'
}

ti_store_disk_a_session_value_wins_over_the_file() {
	_sd_setup
	_sd_file "$(_sd_tab pa.xml dk value fromfile)"
	_sd_w dk input
	_tui_store.build_widget dk true disk
	tui.store.set pa.xml dk value fromsession
	_tui_store.restore_page
	eq fromsession "${_TUI_W_VALUE[dk]}"
}

ti_store_disk_the_whole_page_with_persist_disk_on_tui() {
	_sd_setup
	_sd_file "$(_sd_tab pa.xml a value A)" "$(_sd_tab pa.xml b value B)"
	_sd_w a input
	_sd_w b input
	_tui_store.build_page "" disk ""
	_tui_store.restore_page
	eq "A B" "${_TUI_W_VALUE[a]} ${_TUI_W_VALUE[b]}"
}

# ── reset ────────────────────────────────────────────────────────────────

_sd_two_pages_on_disk() {
	_sd_file "$(_sd_tab pa.xml a value A)" "$(_sd_tab pa.xml b value B)" "$(_sd_tab pb.xml a value C)"
	_sd_w a input
	_sd_w b input
	_tui_store.build_widget a true disk
	_tui_store.build_widget b true disk
	_tui_store.restore_page
}

ti_store_disk_reset_removes_the_current_pages_entries() {
	_sd_setup
	_sd_two_pages_on_disk
	_TUI_STORE_DIRTY=""
	tui.page.reset 2>/dev/null
	eq 1 "$_TUI_STORE_DIRTY"
	eq 1 "${#_TUI_STORE_FILE[@]}"
	_tui_store.key pb.xml a value
	eq C "${_TUI_STORE_FILE[$_SK]}"
}

ti_store_disk_reset_field_removes_one_items_entries() {
	_sd_setup
	_sd_two_pages_on_disk
	tui.page.reset_field a 2>/dev/null
	eq 2 "${#_TUI_STORE_FILE[@]}"
	_tui_store.key pa.xml b value
	eq B "${_TUI_STORE_FILE[$_SK]}"
}

ti_store_disk_reset_all_rewrites_the_file_empty() {
	_sd_setup
	_sd_two_pages_on_disk
	tui.page.reset_all 2>/dev/null
	eq 0 "${#_TUI_STORE_FILE[@]}"
	eq "# dabt-state 1" "$(<"$_SDH/state/store")"
}

# ── the real seam: tui.goto ──────────────────────────────────────────────

# _sd_pages DIR - the pages of the goto tests
_sd_pages() {
	local d="$1" foe
	mkdir -p "$d"
	cat >"$d/pa.xml" <<'XML'
<tui>
  <pane id="root" border="single">
    <input id="name" persist="disk" placeholder="x"/>
    <button id="b1" text="one"/>
    <button id="b2" text="two" keep_focus="true"/>
  </pane>
</tui>
XML
	cat >"$d/pb.xml" <<'XML'
<tui>
  <pane id="root" border="single">
    <button id="b1" text="one"/>
    <button id="b2" text="two"/>
  </pane>
</tui>
XML
	cat >"$d/pn.xml" <<'XML'
<tui>
  <pane id="root" border="single"><button id="b1" text="one"/><button id="b3" text="three"/></pane>
</tui>
XML
	for foe in keep first b2 nope; do
		cat >"$d/pf_$foe.xml" <<XML
<tui focus_on_enter="$foe">
  <pane id="root" border="single">
    <button id="b1" text="one"/>
    <button id="b2" text="two"/>
  </pane>
</tui>
XML
	done
}
# _sd_focus ID - puts the focus on a widget of the current page
_sd_focus() {
	_tui_focus.ensure
	_TUI_FOCUS_ID="$1"
	_TUI_FOCUS_IDX="${_TUI_FOCUS_POS[$1]}"
}
_sd_go() { tui.goto "$_SDD/$1" >/dev/null 2>>"$_SDD/err"; }
_sd_go_setup() {
	_sd_setup
	_TUI_MARKUP_FILE=""
	_SDD="$_T_ROOT/sd_pages_${RANDOM}${RANDOM}"
	_sd_pages "$_SDD"
	_TUI_MARKUP_DIR="$_SDD"
	_TUI_ROWS=24 _TUI_COLS=80
}

ti_store_disk_goto_writes_on_leave_and_reads_back_after_a_restart() {
	_sd_go_setup
	_sd_go pa.xml
	_TUI_W_VALUE[name]="typed text"
	_sd_go pb.xml
	ok '[[ -f "$_SDH/state/store" ]]'
	match "$(<"$_SDH/state/store")" $'pa.xml\tname\tvalue\ttyped text'
	# a new run: nothing in memory but the file
	_TUI_STORE=() _TUI_STORE_DEFAULT=() _TUI_STORE_DEFAULTED=() _TUI_STORE_FILE=() _TUI_STORE_LOADED="" _TUI_STORE_DIRTY=""
	_sd_go pa.xml
	eq "typed text" "${_TUI_W_VALUE[name]}"
	eq "" "$(<"$_SDD/err")"
}

ti_store_disk_exit_flushes_the_current_page() {
	_sd_go_setup
	_sd_go pa.xml
	_TUI_W_VALUE[name]="at exit"
	ok '[[ ! -e "$_SDH/state/store" ]]'
	_tui_store.exit
	match "$(<"$_SDH/state/store")" $'pa.xml\tname\tvalue\tat exit'
}

ti_store_keep_focus_lands_on_the_same_id_on_the_next_page() {
	_sd_go_setup
	_sd_go pa.xml
	_sd_focus b2
	_sd_go pb.xml
	eq b2 "$_TUI_FOCUS_ID"
	_sd_go pa.xml
	eq b2 "$_TUI_FOCUS_ID"
}

ti_store_keep_focus_comes_back_when_the_other_page_lacks_the_id() {
	_sd_go_setup
	_sd_go pa.xml
	_sd_focus b2
	_sd_go pn.xml
	[[ "$_TUI_FOCUS_ID" != b2 ]] || _t_fail "b2 does not exist on pn.xml"
	_sd_go pa.xml
	eq b2 "$_TUI_FOCUS_ID"
}

ti_store_keep_focus_needs_the_attribute() {
	_sd_go_setup
	_sd_go pa.xml
	_sd_focus b1
	_sd_go pb.xml
	_sd_focus b2
	_sd_go pa.xml
	[[ "$_TUI_FOCUS_ID" != b2 ]] || _t_fail "b2 is not a keep_focus widget on pb.xml"
}

ti_store_focus_on_enter_keep_restores_the_last_focused_id() {
	_sd_go_setup
	_sd_go pf_keep.xml
	_sd_focus b2
	_sd_go pb.xml
	_sd_go pf_keep.xml
	eq b2 "$_TUI_FOCUS_ID"
}

ti_store_focus_on_enter_first_ignores_what_was_stored() {
	_sd_go_setup
	_sd_go pf_first.xml
	_sd_focus b2
	_tui_store.save_focus
	_sd_go pb.xml
	_sd_go pf_first.xml
	[[ "$_TUI_FOCUS_ID" != b2 ]] || _t_fail "first must not restore"
}

ti_store_focus_on_enter_id_focuses_that_widget() {
	_sd_go_setup
	_sd_go pb.xml
	_sd_go pf_b2.xml
	eq b2 "$_TUI_FOCUS_ID"
}

ti_store_focus_on_enter_unknown_id_falls_back_to_first() {
	_sd_go_setup
	_sd_go pb.xml
	_sd_go pf_nope.xml
	[[ "$_TUI_FOCUS_ID" != nope ]] || _t_fail "unknown id focused"
	eq "" "$(<"$_SDD/err")"
}

# ── validator ────────────────────────────────────────────────────────────

# _sd_check TUI_ATTRS BODY -> findings in _VF
_sd_check() {
	local f="$HOME/sd.xml" i
	printf '<tui %s>\n<pane id="p">\n%s\n</pane>\n</tui>\n' "$1" "$2" >"$f"
	tui.validate.files "$f"
	_VF=""
	for i in "${!_TV_F_MSG[@]}"; do _VF+="${_TV_F_SEV[i]} ${_TV_F_MSG[i]}"$'\n'; done
}

ti_validate_persist_keep_focus_and_focus_on_enter_accept_cases() {
	_sd_check 'focus_on_enter="keep" persist="disk"' '<input id="a" persist="disk" keep_focus="true"/>'
	eq "" "$_VF"
	_sd_check 'focus_on_enter="first"' '<button id="a" text="a" keep_focus="false"/>'
	eq "" "$_VF"
	_sd_check 'focus_on_enter="a"' '<button id="a" text="a"/>'
	eq "" "$_VF"
}

ti_validate_focus_on_enter_must_be_keep_first_or_an_id() {
	_sd_check 'focus_on_enter="nowhere"' '<button id="a" text="a"/>'
	match "$_VF" 'error focus_on_enter="nowhere" is not keep, first or the id of a widget'
}

ti_validate_keep_focus_must_be_true_or_false() {
	_sd_check '' '<button id="a" text="a" keep_focus="yes"/>'
	match "$_VF" 'error '
}

ti_validate_keep_focus_on_a_non_focusable_widget_warns() {
	_sd_check '' '<label id="l" text="a" keep_focus="true"/>'
	match "$_VF" "warn 'l' has keep_focus but is not focusable"
	_sd_check '' '<label id="l" text="a" keep_focus="true" focusable="true"/>'
	eq "" "$_VF"
}

ti_validate_persist_value_is_checked() {
	_sd_check 'persist="forever"' '<button id="a" text="a"/>'
	match "$_VF" 'error '
}
