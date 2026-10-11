# plugin: meter
# title: Meter widget
# version: 1.0
# description: A new widget type, <meter>: a gauge that turns yellow and red as it fills. Ships as a plugin to show that the widget contract (tui.register widget) needs no change in lib/.
# author: Dino
# default: off
#
#   <meter id="cpu" pane="main" row="2" label="CPU" value="42"/>      markup
#   tui.widget.new ID meter PANE ROW; tui.meter.set ID VALUE [MAX]    code
#
# VALUE is a percentage (0-100) unless MAX is given: tui.meter.set cpu 3 8 shows 37%. Colours come from the theme classes
# .meter_ok, .meter_warn and .meter_hot (below 60%, below 85%, above), with green / yellow / red as the fallback.
# Layout: "LABEL ▕██████░░░░░▏ 42%". The type has no HIT or KEY handler (the contract makes both optional), so it is
# display-only and never takes focus.

_METER_WARN=60 _METER_HOT=85

# _meter.measure ID WIDTH -> _R - always one row.
_meter.measure() { _R=1; }

# _meter.draw ID SR SC SW SH FOCUSED HOVERED STYLE_KEY PANE_KEY - the DRAW handler.
_meter.draw() {
	local id="$1" sr="$2" sc="$3" sw="$4"
	local label pct fill bw lw=0 class fallback bar_fill bar_rest
	tui.widget.get "$id" label
	label=$TUI_WIDGET_V
	tui.widget.get "$id" value
	pct=$TUI_WIDGET_V
	[[ "$pct" =~ ^[0-9]+$ ]] || pct=0
	((pct > 100)) && pct=100
	if ((pct < _METER_WARN)); then
		class=meter_ok fallback=$'\e[0;32m'
	elif ((pct < _METER_HOT)); then
		class=meter_warn fallback=$'\e[0;33m'
	else
		class=meter_hot fallback=$'\e[0;31m'
	fi
	tui.class.sgr "$class"
	[[ -n "$label" ]] && lw=$((${#label} + 1))
	bw=$((sw - lw - 7))
	((bw < 3)) && bw=3
	fill=$((bw * pct / 100))
	printf -v bar_fill '%*s' "$fill" ''
	printf -v bar_rest '%*s' "$((bw - fill))" ''
	tui.widget.emit "$sr" "$sc" '%s%s▕%s%s%s%s%s▏ %3d%%' "${label:+$label }" "" "${TUI_SGR:-$fallback}" "${bar_fill// /█}" $'\e[2m' "${bar_rest// /░}" $'\e[0m' "$pct"
}

# _meter.tag NODE - the <meter> markup tag.
_meter.tag() { tui.widget.from_node "$1"; }

# tui.meter.set ID VALUE [MAX] - sets the gauge (percent of MAX, default 100) and repaints it.
tui.meter.set() {
	local v=$2 m=${3:-100}
	((m > 0)) || m=100
	((v = v * 100 / m))
	((v < 0)) && v=0
	((v > 100)) && v=100
	tui.widget.set "$1" value "$v"
	tui.widget.redraw "$1"
}

plugin.meter.on_enable() {
	tui.register widget meter _meter.measure _meter.draw -
	tui.register tag meter _meter.tag
	tui.register.style_contract meter "states:" "classes:.meter_ok .meter_warn .meter_hot"
}
