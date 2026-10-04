# widget_contract.t.sh - lib/widgets/tui_widget_contract.sh: widget types registered as measure/draw/hit/key handlers.

_wc_reset() {
	unset '_TUI_WT_MEASURE[wc_t]' '_TUI_WT_DRAW[wc_t]' '_TUI_WT_HIT[wc_t]' '_TUI_WT_KEY[wc_t]' '_TUI_REGISTRY[widget:wc_t]'
	_TUI_WPC=() _TUI_WPC_N=0
}

t_widget_contract_register_binds_four_handlers() {
	_wc_reset
	tui.register widget wc_t m_fn d_fn h_fn k_fn
	ok '[[ "${_TUI_WT_MEASURE[wc_t]}" == m_fn && "${_TUI_WT_DRAW[wc_t]}" == d_fn && "${_TUI_WT_HIT[wc_t]}" == h_fn && "${_TUI_WT_KEY[wc_t]}" == k_fn ]]'
	_wc_reset
}

t_widget_contract_dash_and_missing_key_mean_none() {
	_wc_reset
	tui.register widget wc_t - d_fn -
	ok '[[ -z "${_TUI_WT_MEASURE[wc_t]:-}" && "${_TUI_WT_DRAW[wc_t]}" == d_fn && -z "${_TUI_WT_HIT[wc_t]:-}" && -z "${_TUI_WT_KEY[wc_t]:-}" ]]'
	_wc_reset
}

t_widget_contract_dash_is_not_a_registry_handler() {
	_wc_reset
	tui.register widget wc_t - d_fn -
	tui.registered widget wc_t
	eq "d_fn" "$_TUI_REGISTERED"
	_wc_reset
}

t_widget_contract_unregister_plugin_drops_its_handlers() {
	_wc_reset
	_TUI_REGISTRY_CURRENT_PLUGIN=wc_plug
	tui.register widget wc_t m_fn d_fn h_fn k_fn
	_TUI_REGISTRY_CURRENT_PLUGIN=""
	_tui_registry.unregister_plugin wc_plug
	ok '[[ -z "${_TUI_WT_MEASURE[wc_t]:-}${_TUI_WT_DRAW[wc_t]:-}${_TUI_WT_HIT[wc_t]:-}${_TUI_WT_KEY[wc_t]:-}" ]]'
	_wc_reset
}

# a registered type is drawn by its DRAW handler: ID SR SC SW SH FOCUSED HOVERED STYLE_KEY PANE_KEY
wc_draw() { _WC_ARGS="$*"; }
t_widget_contract_draw_dispatches_registered_type() {
	_wc_reset
	_TUI_REGISTRY_CURRENT_PLUGIN=""
	tui.register widget wc_t - wc_draw -
	_TUI_P_ROW[wcp]=2 _TUI_P_COL[wcp]=3 _TUI_P_H[wcp]=10 _TUI_P_W[wcp]=24
	unset '_TUI_P_CHILDREN[wcp]'
	_TUI_P_BORDER[wcp]=none _TUI_P_BORDER_EXPL[wcp]=1 _TUI_P_HPAD[wcp]=0 _TUI_P_VPAD[wcp]=0
	_ps.widgets.set wc_w type wc_t
	_ps.widgets.set wc_w pane wcp
	_ps.widgets.set wc_w row 0
	_WC_ARGS=""
	_TUI_FRAME=""
	_tui._draw_widget_buf wc_w
	ok '[[ "$_WC_ARGS" == "wc_w 2 "* ]]'
	_wc_reset
}

# MEASURE ID WIDTH -> _R rows
wc_measure() { _R=3; }
t_widget_contract_measure_sets_widget_height() {
	_wc_reset
	tui.register widget wc_t wc_measure wc_draw -
	_TUI_P_ROW[wcp]=2 _TUI_P_COL[wcp]=3 _TUI_P_H[wcp]=10 _TUI_P_W[wcp]=24
	unset '_TUI_P_CHILDREN[wcp]'
	_TUI_P_BORDER[wcp]=none _TUI_P_BORDER_EXPL[wcp]=1 _TUI_P_HPAD[wcp]=0 _TUI_P_VPAD[wcp]=0
	_ps.widgets.set wc_w type wc_t
	_ps.widgets.set wc_w pane wcp
	_ps.widgets.set wc_w row 0
	_TUI_WP_LAST="" _TUI_WP_REUSE=0
	_tui._widget_pos wc_w
	eq 3 "$_WSH"
	_wc_reset
}

# KEY ID NAME: with _TUI_WT_PROBE=1 only answers "do you want NAME?" (rc 0 = yes), else acts and rc 0 = handled
wc_key() {
	[[ "$2" == space ]] || return 1
	((_TUI_WT_PROBE)) || _WC_KEYED="$1"
}
t_widget_contract_key_probe_and_deliver() {
	_wc_reset
	tui.register widget wc_t - wc_draw - wc_key
	_ps.widgets.set wc_w type wc_t
	_WC_KEYED=""
	_tui_wx.consumes wc_w space
	ok '(( $? == 0 )) && [[ -z "$_WC_KEYED" ]]'
	_tui_wx.consumes wc_w left && return 1
	_tui_wx.key wc_w space
	eq wc_w "$_WC_KEYED"
	_wc_reset
}

# HIT ID X Y KIND: rc 0 = handled
wc_hit() { _WC_HIT="$1 $2 $3 $4"; }
t_widget_contract_mouse_dispatches_hit_handler() {
	_wc_reset
	tui.register widget wc_t - wc_draw wc_hit
	_ps.widgets.set wc_w type wc_t
	_WC_HIT=""
	_tui_wx.mouse wc_w 7 4 press
	eq "wc_w 7 4 press" "$_WC_HIT"
	_wc_reset
}
