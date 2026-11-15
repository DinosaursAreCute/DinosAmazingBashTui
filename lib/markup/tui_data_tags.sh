#!/usr/bin/env bash
# tui_data_tags.sh - the markup of datasets: <data>, <spark>, <gauge>, <chart> and the from= attribute of <table>, <list> and <label>.
#
#   <data name="lat" cols="ms|code" key="" max="60" scope="page|session|disk"/>   declares a dataset (see tui.data.new)
#   <table|list|label ... from="lat" col="ms" .../>      shows a dataset (the options of tui.data.bind are attributes; table keeps its own data= for literal rows)
#   <spark id= from= col= last= width=/>  <gauge id= from= col= max= width=/>  one-line widgets, labels bound to a dataset
#   <chart id= from= type="linechart" col= label= last= args="-h 8"/>   a pane holding tui.chart output
# A page replay skips tag handlers, so every declaration and binding is also recorded as a call (_TUI_CACHE_REC_GOTOS).
# requires: tui_registry tui_build tui_data

# _td.record CALL ARG... - runs a tui.data.* call and records it for a page replay
_td.record() {
	local _rec="$1" _q _a
	shift
	for _a in "$@"; do
		printf -v _q '%q' "$_a"
		_rec+=" $_q"
	done
	_TUI_CACHE_REC_GOTOS+=("$_rec")
	"${_rec%% *}" "$@"
}

# _td.node_bind NODE ID KIND - binds widget ID to the dataset named by NODE's data= attribute (nothing without one)
_td.node_bind() {
	local node="$1" id="$2" kind="$3" d k v
	local -a opts=("${@:4}") # options the tag took off the node before the label handler could mistake them for its own
	_tui_build.attrv "$node" from d
	[[ -n "$d" ]] || return 0
	for k in col last max width format type label args show levels heat class key; do
		_tui_build.attrv "$node" "$k" v
		[[ -n "$v" ]] && opts+=("$k=$v")
	done
	_td.record tui.data.bind "$d" "$id" "$kind" "${opts[@]}"
}

_tui_build.tag.data() {
	local node="$1" n c k m s
	local -a flags=()
	_tui_build.attrv "$node" name n
	_tui_build.attrv "$node" cols c
	_tui_build.attrv "$node" key k
	_tui_build.attrv "$node" max m
	_tui_build.attrv "$node" scope s
	[[ -n "$c" ]] && flags+=(--cols "$c")
	[[ -n "$k" ]] && flags+=(--key "$k")
	[[ -n "$m" ]] && flags+=(--max "$m")
	[[ -n "$s" ]] && flags+=(--scope "$s")
	_td.record tui.data.new "$n" "${flags[@]}"
}
_tui_build.tag.spark() {
	local id w
	_tui_build.attrv "$1" width w
	tui_node.attr_set "$1" width "" # width= is the sparkline's length here, not the label's size
	_tui_build.tag.label "$1"
	_tui_build.attrv "$1" id id
	_td.node_bind "$1" "$id" spark "width=$w"
}
_tui_build.tag.gauge() {
	local id w
	_tui_build.attrv "$1" width w
	tui_node.attr_set "$1" width "" # width= is the bar's length here, not the label's size
	_tui_build.tag.label "$1"
	_tui_build.attrv "$1" id id
	_td.node_bind "$1" "$id" gauge "width=$w"
}
_tui_build.tag.chart() {
	local id
	_tui_build.tag.pane "$1"
	_tui_build.attrv "$1" id id
	_td.node_bind "$1" "$id" chart
}
tui.register tag data _tui_build.tag.data
tui.register tag spark _tui_build.tag.spark
tui.register tag gauge _tui_build.tag.gauge
tui.register tag chart _tui_build.tag.chart
