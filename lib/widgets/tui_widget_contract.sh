#!/usr/bin/env bash
# tui_widget_contract.sh - widget types as registered handlers: a type is four functions, not a branch in the engine.
#
#   tui.register widget TYPE MEASURE DRAW HIT [KEY]     "-" (or an omitted KEY) = the type has no such handler
#   tui.widget.new ID TYPE PANE ROW                     creates a widget of a registered type
#   tui.widget.get ID FIELD                             a widget field -> $TUI_WIDGET_V
#   tui.widget.set ID FIELD VALUE                       sets a widget field (label, value, action, ...)
#   tui.widget.from_node NODE                           markup tag handler body: builds the node's widget -> $TUI_WIDGET_V (the id)
#   tui.widget.emit ROW COL FORMAT [ARG...]             DRAW helper: moves to ROW COL and appends printf output to the frame
#   tui.widget.redraw ID                                repaints one widget now (when the app is running)
#
# Handlers (all optional, a type needs at least DRAW to appear):
#   MEASURE ID WIDTH           -> _R   rows the widget wants when height= / expand= do not decide it
#   DRAW ID SR SC SW SH FOCUSED HOVERED STYLE_KEY PANE_KEY    appends to _TUI_FRAME; the engine has already cleared the
#                                      widget's cells and clipped it to its pane
#   HIT ID X Y KIND            rc 0    a left press (KIND press) or drag on the widget; _tui._widget_pos has run
#   KEY ID NAME                rc 0    the focused widget is offered a key. With _TUI_WT_PROBE=1 it only answers "do you
#                                      want NAME?" without acting; otherwise it acts and rc 0 = handled
# The handlers are cached per type at registration (_TUI_WT_*), so the engine pays one array lookup, not a registry
# split. A later registration of the same type wins; unregistering a plugin drops what it registered.
# requires: tui_registry

declare -gA _TUI_WT_MEASURE=() _TUI_WT_DRAW=() _TUI_WT_HIT=() _TUI_WT_KEY=()
declare -g _TUI_WT_PROBE=0 TUI_WIDGET_V=""
declare -gA _TUI_WPC=() # widget position cache (tui.sh); declared here too because binding a type clears it

# _tui_widget.bind TYPE MEASURE DRAW HIT [KEY] - caches the handlers of TYPE; "-" clears one.
_tui_widget.bind() {
	local type="$1"
	_TUI_WT_MEASURE[$type]=${2:--} _TUI_WT_DRAW[$type]=${3:--} _TUI_WT_HIT[$type]=${4:--} _TUI_WT_KEY[$type]=${5:--}
	[[ ${_TUI_WT_MEASURE[$type]} == - ]] && _TUI_WT_MEASURE[$type]=""
	[[ ${_TUI_WT_DRAW[$type]} == - ]] && _TUI_WT_DRAW[$type]=""
	[[ ${_TUI_WT_HIT[$type]} == - ]] && _TUI_WT_HIT[$type]=""
	[[ ${_TUI_WT_KEY[$type]} == - ]] && _TUI_WT_KEY[$type]=""
	_TUI_WPC=() _TUI_WPC_N=0 # cached widget positions were computed without these handlers
}

# _tui_widget.unbind_missing TYPE - after handlers left the registry, forgets cached handlers no longer registered.
_tui_widget.unbind_missing() {
	local type="$1" words
	words=" ${_TUI_REGISTRY[widget:$type]:-} "
	[[ $words == *" ${_TUI_WT_MEASURE[$type]:-.} "* ]] || _TUI_WT_MEASURE[$type]=""
	[[ $words == *" ${_TUI_WT_DRAW[$type]:-.} "* ]] || _TUI_WT_DRAW[$type]=""
	[[ $words == *" ${_TUI_WT_HIT[$type]:-.} "* ]] || _TUI_WT_HIT[$type]=""
	[[ $words == *" ${_TUI_WT_KEY[$type]:-.} "* ]] || _TUI_WT_KEY[$type]=""
}

# tui.widget.new ID TYPE PANE ROW - creates a widget; its handlers come from `tui.register widget TYPE ...`.
tui.widget.new() {
	_tui_wx.new "$1" "$2" "$3" "${4:-0}"
}

# tui.widget.get ID FIELD -> $TUI_WIDGET_V - a widget field ("" when unset).
tui.widget.get() {
	_ps.widgets.get "$1" "$2"
	TUI_WIDGET_V=$_V
}

# tui.widget.set ID FIELD VALUE - sets a widget field.
tui.widget.set() {
	_ps.widgets.set "$1" "$2" "$3"
}

# tui.widget.from_node NODE -> $TUI_WIDGET_V - builds the widget a markup node describes (id, pane and row from the node,
# label / value / action attributes copied); register it as the tag handler: tui.register tag TYPE FN.
tui.widget.from_node() {
	local node="$1" wid wpane wrow attr
	_tui_build.attrv "$node" id wid
	_tui_build.pane_ofv "$node" wpane
	_tui_build.row_ofv "$node" wrow
	tui.widget.new "$wid" "${_N_TYPE[$node]}" "$wpane" "$wrow" || return 1
	for attr in label value action; do
		_tui_build.attrv "$node" "$attr" _N_ATTR_V
		[[ -n "$_N_ATTR_V" ]] && tui.widget.set "$wid" "$attr" "$_N_ATTR_V"
	done
	TUI_WIDGET_V=$wid
}

# tui.widget.emit ROW COL FORMAT [ARG...] - moves the cursor to ROW COL and appends printf FORMAT ARG... to the frame.
tui.widget.emit() {
	_tui.emit_goto "$1" "$2"
	_tui.emit_printf "$3" "${@:4}"
}

# tui.widget.redraw ID - repaints one widget now.
tui.widget.redraw() {
	_tui_wx.redraw "$1"
}

# _tui_widget.label.draw ID SR SC SW SH FOCUSED HOVERED STYLE_KEY PANE_KEY - the label type's DRAW handler.
_tui_widget.label.draw() {
	local id="$1" sr="$2" sc="$3" sw="$4" style_key="$8" pane_key="$9"
	local calign text pad rem
	_tui._widget_align_v "$id"
	calign="$_R"
	_tui._resolve_text_v "${_TUI_W_VALUE[$id]}" # state:direct
	text="$_R"
	text="${text:0:$sw}"
	_tui.emit_style "$style_key" "$pane_key"
	if [[ "$calign" == "fill" ]]; then
		pad=$(((sw - ${#text}) / 2))
		((pad < 0)) && pad=0
		rem=$((sw - pad - ${#text}))
		((rem < 0)) && rem=0
		_tui.emit_goto "$sr" "$sc"
		_tui.emit_printf '%*s%s%*s' "$pad" "" "$text" "$rem" ""
	else
		_tui.emit_goto "$sr" "$sc"
		_tui.emit_printf '%*s' "$sw" ""
		_tui._align_pad_v "$calign" "${#text}" "$sw"
		pad=$_R
		_tui.emit_goto "$sr" $((sc + pad))
		_tui.emit "$text"
	fi
	_tui.emit_reset
}
tui.register widget label - _tui_widget.label.draw -
