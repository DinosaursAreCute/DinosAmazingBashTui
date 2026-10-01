# rowcache.t.sh - lib/render/tui_rowcache.sh content-addressed fragment cache.

_rc_pane() {
	_TUI_P_ROW[p]=2 _TUI_P_COL[p]=3 _TUI_P_H[p]=10 _TUI_P_W[p]=24
	unset '_TUI_P_CHILDREN[p]'
	_TUI_P_BORDER[p]=none
	_TUI_P_BORDER_EXPL[p]=1
	_TUI_P_HPAD[p]=0 _TUI_P_VPAD[p]=0
}

_rc_draw_widget() { # ID -> bytes in _RC_OUT
	_TUI_FRAME=""
	_tui._draw_widget_buf "$1"
	_RC_OUT="$_TUI_FRAME"
}

t_rowcache_miss_then_hit_replays_stored_bytes() {
	_tui_rowcache.reset
	_TUI_FRAME="head"
	_tui_rowcache.replay k && return 1
	_TUI_FRAME+="body"
	_tui_rowcache.store k 4
	_TUI_FRAME="head"
	_tui_rowcache.replay k
	eq "headbody" "$_TUI_FRAME"
}

t_rowcache_disabled_never_hits() {
	_tui_rowcache.reset
	_TUI_FRAME="xy"
	_tui_rowcache.store k 0
	_TUI_ROWCACHE=0
	_TUI_FRAME=""
	_tui_rowcache.replay k && return 1
	eq "" "$_TUI_FRAME"
}

t_rowcache_is_bounded() {
	_tui_rowcache.reset
	_TUI_RC_MAX=3
	local i
	for i in 1 2 3 4; do
		_TUI_FRAME="v$i"
		_tui_rowcache.store "k$i" 0
	done
	ok "((_TUI_RC_N <= 3))"
}

t_style_write_bumps_epoch() {
	local before=$_TUI_STYLE_EPOCH
	tui.style x "#ffffff" "" "" normal
	ok "((_TUI_STYLE_EPOCH > $before))"
}

t_widget_cached_draw_is_byte_identical_to_uncached() {
	_rc_pane
	tui.label l1 p 0 "Hello" ""
	_tui_rowcache.reset
	_TUI_ROWCACHE=0
	_rc_draw_widget l1
	local plain="$_RC_OUT"
	_TUI_ROWCACHE=1
	_rc_draw_widget l1 # miss, stores
	_rc_draw_widget l1 # hit
	eq "$plain" "$_RC_OUT"
}

t_widget_changed_value_is_not_served_stale() {
	_rc_pane
	tui.label l1 p 0 "Hello" ""
	_tui_rowcache.reset
	_rc_draw_widget l1
	_TUI_W_VALUE[l1]="World"
	_rc_draw_widget l1
	match "$_RC_OUT" 'World'
}

t_widget_style_change_is_not_served_stale() {
	_rc_pane
	tui.label l1 p 0 "Hello" ""
	_tui_rowcache.reset
	_rc_draw_widget l1
	local before="$_RC_OUT"
	tui.style l1 "#ff0000" "" "" normal
	_rc_draw_widget l1
	ok '[[ "$before" != "$_RC_OUT" ]]'
}

t_widget_expression_text_bypasses_cache() {
	_rc_pane
	tui.label l1 p 0 'v=${echo A}' ""
	_tui_rowcache.reset
	_rc_draw_widget l1
	eq 0 "$_TUI_RC_N"
}

t_widget_pos_cache_is_exact_and_not_stale() {
	_rc_pane
	tui.button b1 p 0 "Go" ""
	_tui._widget_pos b1
	local first="$_WSR $_WSC $_WSW $_WSH $_WSW_AVAIL"
	_tui._widget_pos b1 # served from the geometry cache
	eq "$first" "$_WSR $_WSC $_WSW $_WSH $_WSW_AVAIL"
	tui.width b1 10 # an attribute change is a different key
	_tui._widget_pos b1
	eq 10 "$_WSW"
	_TUI_P_W[p]=40 # a pane resize too
	_tui._widget_pos b1
	eq 10 "$_WSW"
	tui.width b1 "100%"
	_tui._widget_pos b1
	eq 38 "$_WSW_AVAIL" # 40 columns minus the one-column inset of a borderless leaf
}

t_vslice_memo_returns_the_same_slice() {
	_tui._vslice "hello" 1 3
	local a="$_VS"
	_tui._vslice "hello" 1 3 # memo hit
	eq "$a" "$_VS"
	eq $'ell\e[0m' "$_VS"
	_tui._vslice "hello" 0 3 # other offset, other key
	eq $'hel\e[0m' "$_VS"
}

t_vslice_memo_keeps_escape_sequences() {
	_tui._vslice $'\e[31mred\e[0m' 0 2
	eq $'\e[31mre\e[0m' "$_VS"
}
