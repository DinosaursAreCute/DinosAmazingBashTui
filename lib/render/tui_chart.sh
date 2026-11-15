#!/usr/bin/env bash
# tui_chart.sh - charts and text renderers as strings, for labels, panes and the widgets bound to datasets.
#
#   tui.chart.spark VAR [-w N] [-n MIN] [-m MAX] VALUE...      one block glyph per value (fork-free)
#   tui.chart.gauge VAR VALUE [MAX] [-w N]                     a bar and a percent, MAX defaults to 100 (fork-free)
#   tui.chart KIND VAR [--data NAME --col COL [--label COL] [--last N]] [--class CLASS] [RENDERER ARG...]   any renderer, lines in VAR
#
# KIND is one of box divider alert table kv hbar vbar gauge sparkline linechart csv_hbar csv_vbar csv_linechart scatter boxplot
# forest heatmap histogram banner tree columns badges list quote: the renderers of lib/terminal_renderer.sh, which is read on
# the first use. Its arguments and flags are the ones its own usage lists (tui.chart hbar out "A:3" "B:5" -w 30). With
# --data the arguments are built from a dataset (tui.data.*) instead:
#   sparkline histogram        the values of COL                 hbar vbar     LABEL:VALUE per row (LABEL defaults to column 0)
#   linechart boxplot forest   one series NAME:v,v,v per --col   table         the --cols header and the rows
#   list                       the cells of COL
# The result is one string, lines joined by newlines, no trailing newline; tui.output PANE "$VAR" shows it. Colours are the
# renderers' (-c RED).
# requires: tui_data

declare -g _TC_LOADED=0
declare -gA _TC_KINDS=([box]=1 [divider]=1 [alert]=1 [table]=1 [kv]=1 [hbar]=1 [vbar]=1 [gauge]=1 [sparkline]=1 [linechart]=1
	[csv_hbar]=1 [csv_vbar]=1 [csv_linechart]=1 [scatter]=1 [boxplot]=1 [forest]=1 [heatmap]=1 [histogram]=1 [banner]=1 [tree]=1
	[columns]=1 [badges]=1 [list]=1 [quote]=1)

# _tc.load - reads lib/terminal_renderer.sh once (about 3000 lines, so not at startup)
_tc.load() {
	((_TC_LOADED)) && return 0
	if declare -F _sparkline_build >/dev/null; then # an app that already read it (tui.require terminal_renderer) keeps its copy
		_TC_LOADED=1
		return 0
	fi
	# shellcheck source=../terminal_renderer.sh
	source "${SCRIPT_DIR:-${BASH_SOURCE[0]%/*}/..}/terminal_renderer.sh" || return 1
	_TC_LOADED=1
}

# The functions that fill a caller's variable keep their own locals under a _ prefix, so a caller's `out` or `n` is never shadowed.

# tui.chart.spark VAR [-w N] [-n MIN] [-m MAX] VALUE... - one block glyph (▁ to █) per value, scaled between the smallest and
# the largest value (or MIN and MAX). With -w only the newest N values show and fewer values leave the left side blank. A value
# that is not a number counts as 0. Fork-free. rc 1 without VAR.
tui.chart.spark() {
	local _var="${1:-}" _w=0 _lo="" _hi="" _v _n _mn="" _mx="" _range _out=""
	[[ -n "$_var" ]] || return 1
	shift
	while [[ "${1:-}" == -[wnm] ]]; do
		case "$1" in
			-w) _w="${2:-0}" ;;
			-n) _td.num "${2:-}" && _lo=$_TDN ;;
			-m) _td.num "${2:-}" && _hi=$_TDN ;;
		esac
		shift 2
	done
	local -a _nums=() _glyph=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
	for _v in "$@"; do
		_td.num "$_v" || _TDN=0
		_nums+=("$_TDN")
	done
	_n=${#_nums[@]}
	((_w > 0 && _n > _w)) && {
		_nums=("${_nums[@]: -_w}")
		_n=$_w
	}
	for _v in "${_nums[@]}"; do
		{ [[ -z "$_mn" ]] || ((_v < _mn)); } && _mn=$_v
		{ [[ -z "$_mx" ]] || ((_v > _mx)); } && _mx=$_v
	done
	[[ -n "$_lo" ]] && _mn=$_lo
	[[ -n "$_hi" ]] && _mx=$_hi
	_mn="${_mn:-0}" _mx="${_mx:-0}"
	_range=$((_mx - _mn))
	((_w > _n)) && printf -v _out '%*s' $((_w - _n)) ''
	for _v in "${_nums[@]}"; do
		((_v < _mn)) && _v=$_mn
		((_v > _mx)) && _v=$_mx
		if ((_range > 0)); then _out+="${_glyph[$(((_v - _mn) * 7 / _range))]}"; else _out+="${_glyph[3]}"; fi
	done
	printf -v "$_var" '%s' "$_out"
}

# tui.chart.gauge VAR VALUE [MAX] [-w N] - a bar of N cells (default 20) filled by VALUE of MAX (default 100) and the percent:
# "████████░░░░ 67%". A value outside 0..MAX is clamped. Fork-free. rc 1 without VAR.
tui.chart.gauge() {
	local _var="${1:-}" _value="${2:-0}" _max=100 _w=20 _pct _filled _out="" _i _val=0 _m=100000
	[[ -n "$_var" ]] || return 1
	shift 2
	[[ "${1:-}" != -w && -n "${1:-}" ]] && {
		_max="$1"
		shift
	}
	[[ "${1:-}" == -w ]] && _w="${2:-20}"
	[[ "$_w" =~ ^[0-9]+$ ]] && ((_w > 0)) || _w=20
	_td.num "$_value" && _val=$_TDN
	_td.num "$_max" && _m=$_TDN
	((_m > 0)) || _m=1000
	((_val < 0)) && _val=0
	((_val > _m)) && _val=$_m
	_pct=$((_val * 100 / _m))
	_filled=$((_val * _w / _m))
	for ((_i = 0; _i < _w; _i++)); do ((_i < _filled)) && _out+="█" || _out+="░"; done
	printf -v "$_var" '%s %d%%' "$_out" "$_pct"
}

# _tc.feed KIND NAME COLS LABEL LAST -> _TC_FEED: the renderer arguments that show the dataset as KIND; rc 1 when the kind does
# not take data
declare -ga _TC_FEED=()
_tc.feed() {
	local kind="$1" name="$2" cols="$3" label="$4" last="$5" c i
	local -a vals=() labs=() colv=()
	_TC_FEED=()
	_td.need "$name" || return 1
	local -a opt=()
	((last > 0)) && opt=(--last "$last")
	read -ra colv <<<"${cols//,/ }"
	((${#colv[@]})) || colv=(0)
	case "$kind" in
		sparkline | histogram)
			tui.data.col "$name" "${colv[0]}" vals "${opt[@]}" || return 1
			((${#vals[@]})) && _TC_FEED=("${vals[*]}")
			;;
		list)
			tui.data.col "$name" "${colv[0]}" vals "${opt[@]}" || return 1
			_TC_FEED=("${vals[@]}")
			;;
		hbar | vbar)
			tui.data.col "$name" "${colv[0]}" vals "${opt[@]}" || return 1
			tui.data.col "$name" "${label:-0}" labs "${opt[@]}" || return 1
			for i in "${!vals[@]}"; do _TC_FEED+=("${labs[i]}:${vals[i]}"); done
			;;
		linechart | boxplot | forest)
			local s
			for c in "${colv[@]}"; do
				tui.data.col "$name" "$c" vals "${opt[@]}" || return 1
				s="${vals[*]}"
				_TC_FEED+=("$c:${s// /,}")
			done
			;;
		table)
			local -a rows=()
			tui.data.rows "$name" rows "${opt[@]}"
			_TC_FEED=("${_TD_COLS[$name]:-}" "${rows[@]}")
			;;
		*) return 1 ;;
	esac
	return 0
}

# tui.chart KIND VAR [--data NAME --col COL [--label COL] [--last N]] [--class CLASS] [RENDERER ARG...] - renders KIND into VAR (lines joined
# by newlines). rc 1 for an unknown KIND, a KIND that does not take --data, an unknown dataset or a renderer that refuses its
# arguments.
tui.chart() {
	local _kind="${1:-}" _var="${2:-}" _data="" _cols="" _label="" _last=0 _class=""
	[[ -n "${_TC_KINDS[$_kind]:-}" && -n "$_var" ]] || return 1
	shift 2
	local -a _args=()
	while (($#)); do
		case "$1" in
			--data) _data="${2:-}" ;;
			--col) _cols+="${_cols:+,}${2:-}" ;;
			--label) _label="${2:-}" ;;
			--last) _last="${2:-0}" ;;
			--class) _class="${2:-}" ;;
			*)
				_args+=("$1")
				shift
				continue
				;;
		esac
		shift 2
	done
	# a size or scale flag with a value that is not a number would send the renderers into a loop that never ends
	local _i
	for _i in "${!_args[@]}"; do
		[[ "$_kind" == list && "${_args[_i]}" == -n ]] && continue # list -n is a flag (numbered), not a scale
		case "${_args[_i]}" in
			-w | -h | -lw | -cw | -tw | -n | -m | -xn | -xm | -yn | -ym | -p)
				[[ "${_args[_i + 1]:-}" =~ ^-?[0-9]+([.,][0-9]+)?$ ]] || {
					echo "tui.chart: ${_args[_i]} needs a number, got '${_args[_i + 1]:-}'" >&2
					return 1
				}
				;;
		esac
	done
	_tc.load || return 1
	if [[ -n "$_data" ]]; then
		_tc.feed "$_kind" "$_data" "$_cols" "$_label" "$_last" || return 1
		((${#_TC_FEED[@]})) || { # nothing to chart: the renderers would read stdin for their text
			printf -v "$_var" '%s' ""
			return 0
		}
		_args=("${_TC_FEED[@]}" "${_args[@]}")
	fi
	TR_RESULT=()
	"_${_kind}_build" "${_args[@]}" || return 1
	local IFS=$'\n' _out
	_out="${TR_RESULT[*]}"
	_out="${_out//\\033/$'\e'}" # some renderers write their colours as the text \033
	if [[ -n "$_class" ]]; then # the class's colours come back after every reset, so the chart keeps the background of the pane it is in
		tui.class.sgr "$_class"
		_out="${_out//$'\e[0m'/$'\e[0m'$TUI_SGR}"
		_out="$TUI_SGR${_out//$'\n'/$'\n'$TUI_SGR}"
	fi
	printf -v "$_var" '%s' "$_out"
}
