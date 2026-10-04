# plugin_meter.t.sh - share/plugins/meter.plugin.sh: a widget type shipped as a plugin, no lib/ change.

_pm_enable() {
	source "$TUI_ROOT/share/plugins/meter.plugin.sh"
	plugin.meter.on_enable
}
_pm_disable() {
	unset '_TUI_WT_MEASURE[meter]' '_TUI_WT_DRAW[meter]' '_TUI_REGISTRY[widget:meter]' '_TUI_REGISTRY[tag:meter]'
}

t_plugin_meter_registers_the_four_handler_slots() {
	_pm_enable
	ok '[[ "${_TUI_WT_MEASURE[meter]}" == _meter.measure && "${_TUI_WT_DRAW[meter]}" == _meter.draw && -z "${_TUI_WT_HIT[meter]:-}" ]]'
	_pm_disable
}

t_plugin_meter_draws_percent_and_fill() {
	_pm_enable
	_TUI_P_ROW[pmp]=2 _TUI_P_COL[pmp]=3 _TUI_P_H[pmp]=10 _TUI_P_W[pmp]=30
	unset '_TUI_P_CHILDREN[pmp]'
	_TUI_P_BORDER[pmp]=none _TUI_P_BORDER_EXPL[pmp]=1 _TUI_P_HPAD[pmp]=0 _TUI_P_VPAD[pmp]=0
	tui.widget.new pm_w meter pmp 0
	tui.widget.set pm_w label CPU
	tui.meter.set pm_w 3 8
	_TUI_FRAME=""
	_tui._draw_widget_buf pm_w
	ok '[[ "$_TUI_FRAME" == *"CPU "* && "$_TUI_FRAME" == *" 37%"* && "$_TUI_FRAME" == *"█"* && "$_TUI_FRAME" == *"░"* ]]'
	_pm_disable
}

t_plugin_meter_turns_hot_above_threshold() {
	_pm_enable
	_TUI_P_ROW[pmp]=2 _TUI_P_COL[pmp]=3 _TUI_P_H[pmp]=10 _TUI_P_W[pmp]=30
	unset '_TUI_P_CHILDREN[pmp]'
	_TUI_P_BORDER[pmp]=none _TUI_P_BORDER_EXPL[pmp]=1 _TUI_P_HPAD[pmp]=0 _TUI_P_VPAD[pmp]=0
	tui.widget.new pm_w meter pmp 0
	tui.meter.set pm_w 95
	_TUI_FRAME=""
	_tui._draw_widget_buf pm_w
	ok '[[ "$_TUI_FRAME" == *$'"'"'\e[0;31m'"'"'* ]]'
	_pm_disable
}
