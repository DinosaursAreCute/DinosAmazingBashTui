#!/usr/bin/env bash
# tui_widgets.sh - the richer widgets: password, textarea, list, table, select, progress. (Text editing itself lives in
# tui_text.sh; input, password and textarea share it.) All of them are ordinary widgets: they take part in focus
# (Tab, arrows), theming (class=), tui.get / tui.set / tui.update, hover and click like a button does.
#
#   tui.password ID PANE ROW [PLACEHOLDER] [LABEL] [SUBMIT_FN]    masked single-line input (value via tui.get)
#   tui.textarea ID PANE ROW [PLACEHOLDER] [ROWS] [SUBMIT_FN]     multi-line editor; ROWS omitted / 0 = fill the pane
#   tui.list     ID PANE ROW [ACTION_FN] [ROWS]                   scrollable single-choice list
#   tui.table    ID PANE ROW [ACTION_FN] [ROWS]                   columns with a header row, single-choice
#   tui.select   ID PANE ROW LABEL [ACTION_FN]                    one row; Enter / click / Down opens a picker
#   tui.progress ID PANE ROW [LABEL]                              a bar; value 0-100 via tui.update or tui.progress.set
#
#   tui.list.set ID ITEM...          tui.list.add ID ITEM...      tui.list.clear ID
#   tui.list.select ID INDEX         tui.list.selected ID -> index (-1 none)     tui.list.item ID [INDEX] -> text
#   tui.list.count ID
#   tui.table.set ID "H1|H2|H3" "a|b|c" "d|e|f" ...   tui.table.add ID ROW...   tui.table.clear ID
#   tui.table.select ID INDEX        tui.table.selected ID -> row index          tui.table.row ID [INDEX] -> "a|b|c"
#   tui.table.count ID
#   tui.select.set ID ITEM...        tui.select.index ID -> index of the value (-1 none)      tui.select.pick ID INDEX
#   tui.progress.set ID VALUE [MAX]
#   tui.on_change ID FN              list/table: selection moved; select: value changed; text: edited   (FN ID)
#   ACTION_FN ID runs on Enter / double-click (list, table), when a new value is picked (select).
#
# Keys: list/table  up down pgup pgdn home end (at the first/last row up/down fall through so focus can leave), Enter.
#       select      Enter / space / down open the picker.        Mouse: click selects, double-click activates, wheel scrolls.
# Theme classes (all optional): .list_sel .table_head .table_sel .progress .progress_fill .select .selection
#   .field_label (+ :focus) - the label in front of an input, password, select or progress bar

declare -gA _TUI_W_ROWSPAN=() _WXSEL=() _WXTOP=() _WXCOLS=() _WXH=() _WXPCT=() _WXF=()
declare -g _WX_TARGET="" _WX_CLICK_T=0 _WX_CLICK_ID="" _WX_CLICK_I=-1

# _tui_wx.new ID TYPE PANE ROW FOCUSABLE : common widget bookkeeping (the same fields tui.button sets)
_tui_wx.new() {
	local id="$1" type="$2"
	if [[ -z "$id" || -z "$3" ]]; then
		echo "tui.$type: missing id or pane, skipping widget" >&2
		return 1
	fi
	_ps.widgets.set "$id" type "$type"
	_ps.widgets.set "$id" pane "$3"
	_ps.widgets.set "$id" row "$4"
	_ps.widgets.set "$id" label ""
	_ps.widgets.set "$id" value ""
	_ps.widgets.set "$id" action ""
	_TUI_W_ORDER+=("$id")
	_tui_w.changed
	return 0
}

tui.password() {
	_tui_wx.new "$1" password "$2" "$3" 1 || return 1
	_ps.widgets.set "$1" ph "${4:-}"
	_ps.widgets.set "$1" label "${5:-}"
	_ps.widgets.set "$1" submit "${6:-}"
}
tui.textarea() {
	_tui_wx.new "$1" textarea "$2" "$3" 1 || return 1
	_ps.widgets.set "$1" ph "${4:-}"
	_ps.widgets.set "$1" rowspan "${5:-0}"
	_ps.widgets.set "$1" submit "${6:-}"
	_ps.widgets.set "$1" expand y
}
tui.list() {
	_tui_wx.new "$1" list "$2" "$3" 1 || return 1
	_ps.widgets.set "$1" action "${4:-}"
	_ps.widgets.set "$1" rowspan "${5:-0}"
	_WXSEL[$1]=-1
	_WXTOP[$1]=0
	_ps.widgets.set "$1" expand y
	_tui_wx.arr "$1"
	_WXA=()
}
tui.table() {
	_tui_wx.new "$1" table "$2" "$3" 1 || return 1
	_ps.widgets.set "$1" action "${4:-}"
	_ps.widgets.set "$1" rowspan "${5:-0}"
	_WXSEL[$1]=-1
	_WXTOP[$1]=0
	_WXCOLS[$1]=""
	_ps.widgets.set "$1" expand y
	_tui_wx.arr "$1"
	_WXA=()
}
tui.select() {
	_tui_wx.new "$1" select "$2" "$3" 1 || return 1
	_ps.widgets.set "$1" label "${4:-}"
	_ps.widgets.set "$1" action "${5:-}"
	_WXSEL[$1]=-1
	_tui_wx.arr "$1"
	_WXA=()
}
tui.progress() {
	_tui_wx.new "$1" progress "$2" "$3" 0 || return 1
	_ps.widgets.set "$1" label "${4:-}"
	_ps.widgets.set "$1" value 0
}

# per-widget item array: _tui_wx.arr ID -> nameref-able array _WXA (declared once per widget)
_tui_wx.arr() {
	local n="_WXI_${1//[^A-Za-z0-9_]/_}"
	declare -ga "$n"
	unset -n _WXA 2>/dev/null
	declare -gn _WXA="$n"
}

# ── data setters ─────────────────────────────────────────────────────────
_tui_wx.redraw() {
	((_TUI_RUNNING)) && _tui._draw_widget "$1"
	return 0
}
_tui_wx.changed() {
	local fn="${_TUI_W_CHANGE[$1]:-}"
	[[ -n "$fn" ]] && "$fn" "$1"
	return 0
}

tui.list.set() {
	local id="$1"
	shift
	_tui_wx.arr "$id"
	_WXA=("$@")
	((${#_WXA[@]})) && _WXSEL[$id]=0 || _WXSEL[$id]=-1
	_WXTOP[$id]=0
	_tui_wx.redraw "$id"
}
tui.list.add() {
	local id="$1"
	shift
	_tui_wx.arr "$id"
	_WXA+=("$@")
	((${_WXSEL[$id]:--1} < 0)) && _WXSEL[$id]=0
	_tui_wx.redraw "$id"
}
tui.list.clear() {
	_tui_wx.arr "$1"
	_WXA=()
	_WXSEL[$1]=-1
	_WXTOP[$1]=0
	_tui_wx.redraw "$1"
}
tui.list.count() {
	_tui_wx.arr "$1"
	printf '%s\n' "${#_WXA[@]}"
}
# tui.list.selected ID [VAR] - the selected index (-1 = none): printed, or stored in VAR without a subshell
tui.list.selected() {
	if [[ -n "${2:-}" ]]; then
		local -n _ls_out="$2"
		_ls_out="${_WXSEL[$1]:--1}"
	else
		printf '%s\n' "${_WXSEL[$1]:--1}"
	fi
}
tui.list.item() {
	_tui_wx.arr "$1"
	local i="${2:-${_WXSEL[$1]:--1}}"
	((i >= 0 && i < ${#_WXA[@]})) && printf '%s\n' "${_WXA[i]}"
	return 0
}
tui.list.select() {
	_tui_wx.arr "$1"
	local n=${#_WXA[@]} i=$2
	((i >= n)) && i=$((n - 1))
	((i < 0)) && i=-1
	_WXSEL[$1]=$i
	_tui_wx.redraw "$1"
}
tui.table.set() {
	local id="$1" head="$2"
	shift 2
	_tui_wx.arr "$id"
	_WXCOLS[$id]="$head"
	_WXA=("$@")
	((${#_WXA[@]})) && _WXSEL[$id]=0 || _WXSEL[$id]=-1
	_WXTOP[$id]=0
	_tui_wx.redraw "$id"
}
tui.table.add() { tui.list.add "$@"; }
tui.table.clear() { tui.list.clear "$1"; }
tui.table.count() { tui.list.count "$1"; }
tui.table.select() { tui.list.select "$@"; }
tui.table.selected() { tui.list.selected "$@"; }
tui.table.row() { tui.list.item "$@"; }
tui.select.set() {
	local id="$1"
	shift
	_tui_wx.arr "$id"
	_WXA=("$@")
	_WXSEL[$id]=-1
	local i
	for i in "${!_WXA[@]}"; do [[ "${_WXA[i]}" == "${_TUI_W_VALUE[$id]}" ]] && _WXSEL[$id]=$i; done
	_tui_wx.redraw "$id"
}
tui.select.index() { printf '%s\n' "${_WXSEL[$1]:--1}"; }
tui.select.pick() {
	_tui_wx.arr "$1"
	local i=$2
	((i >= 0 && i < ${#_WXA[@]})) || return 1
	_WXSEL[$1]=$i
	_ps.widgets.set "$1" value "${_WXA[i]}"
	_tui_wx.redraw "$1"
	_tui_wx.changed "$1"
	local fn="${_TUI_W_ACTION[$1]:-}"
	[[ -n "$fn" ]] && "$fn" "$1"
	return 0
}
tui.progress.set() {
	local v=$2 m=${3:-100}
	((m > 0)) || m=100
	((v = v * 100 / m))
	((v < 0)) && v=0
	((v > 100)) && v=100
	_ps.widgets.set "$1" value "$v"
	_tui_wx.redraw "$1"
}

# select: open the picker (a tui.choose dialog); picking sets the value
_tui_wx.select_open() {
	local id="$1"
	_tui_wx.arr "$id"
	((${#_WXA[@]})) || return 0
	_WX_TARGET="$id"
	tui.choose "${_TUI_W_LABEL[$id]:-Choose}" _tui_wx.select_picked "${_WXA[@]}" --selected "${_WXSEL[$id]:-0}"
}
_tui_wx.select_picked() { tui.select.pick "$_WX_TARGET" "$1"; }

# ── geometry helpers ─────────────────────────────────────────────────────
_tui_wx.multirow() {
	case "${_TUI_W_TYPE[$1]:-}" in textarea | list | table) return 0 ;; esac
	return 1
}

# _tui_wx.move ID up|down|... : list / table selection; keeps it in view. rc 1 when nothing moved
_tui_wx.move() {
	local id="$1" k="$2" sel=${_WXSEL[$1]:--1} n h old
	_tui._widget_pos "$id"
	h=$_WSH
	_WXH[$id]=$h
	_tui_wx.arr "$id"
	n=${#_WXA[@]}
	((n)) || return 1
	old=$sel
	[[ "${_TUI_W_TYPE[$id]}" == table ]] && ((h--))
	((h < 1)) && h=1
	case "$k" in
		up) ((sel > 0)) && ((sel--)) || { ((sel < 0)) && sel=0; } ;;
		down) ((sel < n - 1)) && ((sel++)) ;;
		pgup)
			((sel -= h - 1))
			((sel < 0)) && sel=0
			;;
		pgdn)
			((sel += h - 1))
			((sel >= n)) && sel=$((n - 1))
			;;
		home) sel=0 ;;
		end) sel=$((n - 1)) ;;
	esac
	((sel == old)) && return 1
	_WXSEL[$id]=$sel
	_WXF[$id]=1
	_tui_wx.changed "$id"
	return 0
}

# ── keys / mouse hooks used by tui_input.sh ─────────────────────────────

# rc 0 when the focused widget wants NAME (so default binds on it are skipped)
_tui_wx.consumes() {
	local id="$1" name="$2" type="${_TUI_W_TYPE[$1]:-}" sel n
	case "$type" in
		input | password | textarea)
			_tui_text.consumes "$id" "$name"
			return
			;;
		list | table)
			_tui_wx.arr "$id"
			n=${#_WXA[@]}
			sel=${_WXSEL[$id]:--1}
			case "$name" in
				up)
					((n && sel > 0))
					return
					;;
				down)
					((n && sel < n - 1))
					return
					;;
				pgup | pgdn | home | end)
					((n))
					return
					;;
			esac
			;;
		select) case "$name" in down | space) return 0 ;; esac ;;
		*) # contract type: its KEY handler, asked in probe mode
			local _wt_key="${_TUI_WT_KEY[$type]-}" _TUI_WT_PROBE=1
			[[ -n "$_wt_key" ]] && {
				"$_wt_key" "$id" "$name"
				return
			}
			;;
	esac
	return 1
}

_tui_wx.key() {
	local id="$1" name="$2" type="${_TUI_W_TYPE[$1]:-}"
	case "$type" in
		input | password | textarea) _tui_text.key "$id" "$name" ;;
		list | table)
			_tui_wx.move "$id" "$name"
			_tui_wx.redraw "$id"
			;;
		select) _tui_wx.select_open "$id" ;;
		*) [[ -n "${_TUI_WT_KEY[$type]-}" ]] && "${_TUI_WT_KEY[$type]}" "$id" "$name" ;;
	esac
	return 0
}

# a left press / drag on a widget. Returns 0 when handled here.
_tui_wx.mouse() { # ID X Y KIND(press|drag)
	local id="$1" x="$2" y="$3" kind="$4" type="${_TUI_W_TYPE[$1]:-}" i now
	case "$type" in
		input | password | textarea)
			if [[ "$kind" == press ]]; then _tui_text.press "$id" "$x" "$y"; else _tui_text.drag "$id" "$x" "$y"; fi
			return 0
			;;
		list | table)
			[[ "$kind" == press ]] || return 0
			_tui._widget_pos "$id"
			i=$((_WXTOP[$id] + y - _WSR))
			[[ "$type" == table ]] && ((i--))
			_tui_wx.arr "$id"
			((i >= 0 && i < ${#_WXA[@]})) || return 0
			now=${EPOCHREALTIME//[.,]/}
			now=$((now / 1000))
			local same=0
			[[ "$_WX_CLICK_ID" == "$id" && "$_WX_CLICK_I" == "$i" ]] && ((now - _WX_CLICK_T < 450)) && same=1
			_WX_CLICK_T=$now
			_WX_CLICK_ID="$id"
			_WX_CLICK_I=$i
			if ((_WXSEL[$id] != i)); then
				_WXSEL[$id]=$i
				_tui_wx.changed "$id"
			fi
			_tui_wx.redraw "$id"
			if ((same)); then
				local fn="${_TUI_W_ACTION[$id]:-}"
				[[ -n "$fn" ]] && "$fn" "$id"
				_WX_CLICK_T=0
			fi
			return 0
			;;
		select)
			_tui_wx.select_open "$id"
			return 0
			;;
		*) # contract type: its HIT handler
			[[ -n "${_TUI_WT_HIT[$type]-}" ]] && {
				"${_TUI_WT_HIT[$type]}" "$id" "$x" "$y" "$kind"
				return
			}
			;;
	esac
	return 1
}

# wheel (or the scroll keys) over a textarea / list / table scrolls it. rc 0 when it did; rc 1 when the widget cannot scroll
# that way, so the same binding scrolls the pane instead.
_tui_wx.wheel() { # DIRECTION N
	local id="${TUI_EVENT_WIDGET:-}" n="${2:-3}" c=${TUI_EVENT_COUNT:-1}
	[[ "$TUI_EVENT_TYPE" == mouse && -n "$id" ]] || return 1
	_tui_wx.multirow "$id" || return 1
	_tui._widget_pos "$id"
	_WXH[$id]=$_WSH
	_TXH[$id]=$_WSH
	local total top h old area=0
	[[ "${_TUI_W_TYPE[$id]}" == textarea ]] && area=1
	if ((area)); then
		_tui_text.line_count "$id"
		total=$_LC
		top=${_TXT[$id]:-0}
		h=$_WSH
	else
		_tui_wx.arr "$id"
		total=${#_WXA[@]}
		top=${_WXTOP[$id]:-0}
		h=$_WSH
		[[ "${_TUI_W_TYPE[$id]}" == table ]] && ((h--))
	fi
	old=$top
	case "$1" in
		up) ((top -= n * c)) ;;
		down) ((top += n * c)) ;;
		left | right)
			((area)) || return 1
			local l=${_TXS[$id]:-0}
			old=$l
			[[ "$1" == left ]] && ((l -= n * c)) || ((l += n * c))
			((l < 0)) && l=0
			((l == old)) && return 1
			_TXS[$id]=$l
			_TXF[$id]=0
			_tui_wx.redraw "$id"
			return 0
			;;
		*) return 1 ;;
	esac
	((top > total - h)) && top=$((total - h))
	((top < 0)) && top=0
	((top == old)) && return 1
	if ((area)); then
		_TXT[$id]=$top
		_TXF[$id]=0
	else
		_WXTOP[$id]=$top
		_WXF[$id]=0
	fi
	((_TUI_RUNNING)) && _tui._draw_widget "$id"
	return 0
}

# ── drawing ──────────────────────────────────────────────────────────────

# _tui_wx.draw_buf ID TYPE SR SC SW SH FOCUSED HOVERED STYLE_KEY PANE_KEY - appends
# to _TUI_FRAME (called by _tui._draw_widget_buf; no caller outside the render path).
_tui_wx.draw_buf() {
	local id="$1" type="$2" sr="$3" sc="$4" sw="$5" sh="$6" focused="$7" hovered="$8" sk="$9" pk="${10}"
	case "$type" in
		input | password) _tui_text.draw_line "$id" "$sr" "$sc" "$sw" "$focused" "$sk" "$pk" ;;
		textarea) _tui_text.draw_area "$id" "$sr" "$sc" "$sw" "$sh" "$focused" "$sk" "$pk" ;;
		list | table) _tui_wx.draw_rows "$id" "$type" "$sr" "$sc" "$sw" "$sh" "$focused" "$sk" "$pk" ;;
		select) _tui_wx.draw_select "$id" "$sr" "$sc" "$sw" "$focused" "$sk" "$pk" ;;
		progress) _tui_wx.draw_progress "$id" "$sr" "$sc" "$sw" "$sk" "$pk" ;;
	esac
}

# _tui_wx.label_sgr FOCUSED PANE_KEY -> _LSGR : style of a widget label (input, password, select, progress).
#   Theme class .field_label (.field_label:focus while the widget has focus) sets fg / mods; whatever it leaves
#   out comes from the pane the widget sits in (bg always, unless the class sets one), so the label never shows
#   a different background than its pane. No class: the pane's colours in bold.
_tui_wx.label_sgr() {
	local focused="$1" pk="$2" fg bg mods
	fg="${_TUI_STYLE_FG[$pk]:-}" bg="${_TUI_STYLE_BG[$pk]:-}" mods="bold"
	if [[ -n "${_TUI_CLASS_FG[field_label]:-}${_TUI_CLASS_BG[field_label]:-}${_TUI_CLASS_MOD[field_label]:-}" ]]; then
		if ((focused)); then tui.class.style field_label focus; else tui.class.style field_label; fi
		[[ -n "$TUI_FG" ]] && fg="$TUI_FG"
		[[ -n "$TUI_BG" ]] && bg="$TUI_BG"
		mods="$TUI_MODS"
	fi
	if _tui._sgr_from "$fg" "$bg" "$mods"; then _LSGR="$_SGR"; else
		_tui._style_v "$pk"
		_LSGR="$_SGR"$'\e[1m'
	fi
}

# state:direct
_tui_wx.draw_select() {
	local id="$1" sr="$2" sc="$3" sw="$4" focused="$5" sk="$6" pk="$7"
	local label="${_TUI_W_LABEL[$id]:-}" v="${_TUI_W_VALUE[$id]:-}" lw=0 line
	[[ -z "$v" ]] && v="(none)"
	[[ -n "$label" ]] && {
		lw=$((${#label} + 1))
		_tui_wx.label_sgr "$focused" "$pk"
		_tui.emit_printf '%s%s ' "$_LSGR" "$label"
		_tui.emit_reset
	}
	_tui.emit_style "$sk" "$pk"
	((focused)) && _tui.emit_sgr 7 || { [[ -z "${_TUI_STYLE_FG[$sk]:-}" ]] && _tui.emit_sgr 2; }
	local fw=$((sw - lw))
	line="[ ${v} ▾ ]"
	_tui_text.padc "$line" "$fw"
	_tui.emit "$_PADC"
	_tui.emit_reset
}

# state:direct
_tui_wx.draw_progress() {
	local id="$1" sr="$2" sc="$3" sw="$4" sk="$5" pk="$6"
	local label="${_TUI_W_LABEL[$id]:-}" pct=${_TUI_W_VALUE[$id]:-0} lw=0 bw fill
	[[ "$pct" =~ ^[0-9]+$ ]] || pct=0
	((pct > 100)) && pct=100
	[[ -n "$label" ]] && {
		lw=$((${#label} + 1))
		_tui_wx.label_sgr 0 "$pk"
		_tui.emit_printf '%s%s ' "$_LSGR" "$label"
		_tui.emit_reset
	}
	bw=$((sw - lw - 5))
	((bw < 3)) && bw=3
	fill=$((bw * pct / 100))
	tui.class.sgr progress_fill
	local f="${TUI_SGR:-$'\e[0;32m'}"
	tui.class.sgr progress
	local e="${TUI_SGR:-$'\e[2;37m'}"
	local fs es
	printf -v fs '%*s' "$fill" ''
	printf -v es '%*s' "$((bw - fill))" ''
	_tui.emit_printf '%s%s%s%s%s %3d%%' "$f" "${fs// /█}" "$e" "${es// /░}" $'\e[0m' "$pct"
}

# list / table rows
_tui_wx.draw_rows() {
	local id="$1" type="$2" sr="$3" sc="$4" sw="$5" sh="$6" focused="$7" sk="$8" pk="$9"
	local i n row top sel=${_WXSEL[$id]:--1} fw=$sw hdr=0 line idx
	_tui_wx.arr "$id"
	n=${#_WXA[@]}
	[[ "$type" == table ]] && hdr=1
	((sh < 1)) && sh=1
	_WXH[$id]=$sh
	local rows=$((sh - hdr))
	((rows < 1)) && rows=1
	top=${_WXTOP[$id]:-0}
	if ((${_WXF[$id]:-1})); then # keep the selection in view (not after a wheel scroll)
		((sel >= 0 && sel < top)) && top=$sel
		((sel >= top + rows)) && top=$((sel - rows + 1))
	fi
	((top > n - rows)) && top=$((n - rows))
	((top < 0)) && top=0
	_WXTOP[$id]=$top
	((n > rows && fw > 2)) && fw=$((sw - 1)) # scroll indicator column

	# table: column widths = widest cell, shrunk (widest first) to fit
	local -a cw=() cells
	if ((hdr)); then
		local r c maxc=0 total
		IFS='|' read -ra cells <<<"${_WXCOLS[$id]}"
		for c in "${!cells[@]}"; do cw[c]=${#cells[c]}; done
		for r in "${_WXA[@]}"; do
			IFS='|' read -ra cells <<<"$r"
			for c in "${!cells[@]}"; do ((${#cells[c]} > ${cw[c]:-0})) && cw[c]=${#cells[c]}; done
		done
		total=0
		for c in "${!cw[@]}"; do ((total += cw[c] + 2)); done
		while ((total > fw)); do
			maxc=0
			for c in "${!cw[@]}"; do ((cw[c] > cw[maxc])) && maxc=$c; done
			((cw[maxc] > 3)) || break
			((cw[maxc]--))
			((total--))
		done
	fi

	_tui.emit_style "$sk" "$pk"
	_tui._style_v "$sk" "$pk"
	local base="$_SGR"
	local cls=list_sel
	((hdr)) && cls=table_sel
	tui.class.sgr "$cls"
	local selsgr="${TUI_SGR:-$'\e[0;97;48;2;62;92;138m'}"
	local rowi=0
	if ((hdr)); then
		_tui.emit_goto "$sr" "$sc"
		tui.class.sgr table_head
		local hs="${TUI_SGR:-$'\e[1;4m'}"
		IFS='|' read -ra cells <<<"${_WXCOLS[$id]}"
		line=""
		for c in "${!cw[@]}"; do
			_tui_text.padc "${cells[c]}" "${cw[c]}"
			line+="$_PADC  "
		done
		_tui_text.padc "$line" "$fw"
		line="$_PADC"
		_tui.emit_printf '%s%s%s%s' "$hs" "$line" $'\e[0m' "$base"
		rowi=1
	fi
	for ((i = 0; i < rows; i++)); do
		_tui.emit_goto $((sr + rowi + i)) "$sc"
		idx=$((top + i))
		if ((idx < n)); then
			if ((hdr)); then
				IFS='|' read -ra cells <<<"${_WXA[idx]}"
				line=""
				for c in "${!cw[@]}"; do
					_tui_text.padc "${cells[c]}" "${cw[c]}"
					line+="$_PADC  "
				done
			else line=" ${_WXA[idx]}"; fi
			_tui_text.padc "$line" "$fw"
			line="$_PADC"
			if ((idx == sel)); then
				if ((focused)); then
					_tui.emit_printf '%s%s%s%s' "$selsgr" "$line" $'\e[0m' "$base"
				else _tui.emit_printf '%s%s%s%s' $'\e[7m' "$line" $'\e[27m' "$base"; fi
			else _tui.emit_printf '%s' "$line"; fi
		else _tui.emit_printf '%*s' "$fw" ""; fi
		if ((sw > fw)); then # scroll indicator
			local thumb=$((top * (rows - 1) / (n - rows > 0 ? n - rows : 1)))
			_tui.emit_goto $((sr + rowi + i)) $((sc + fw))
			((i == thumb)) && _tui.emit '▐' || _tui.emit ' '
		fi
	done
	_tui.emit_reset
}

# page reset / factory clear: drop widget-only state
_tui_wx.reset() {
	_TUI_W_ROWSPAN=()
	_WXSEL=()
	_WXTOP=()
	_WXCOLS=()
	_WXH=()
	_TUI_W_CHANGE=()
	_TXC=()
	_TXA=()
	_TXS=()
	_TXT=()
	_TXW=()
	_TXH=()
	_TXUV=()
	_TXUC=()
	_TXUN=()
	_TXRV=()
	_TXRC=()
	_TXRN=()
	_TXLK=()
	_TXLP=()
	_TXG_R=()
	_TXG_C=()
	_TXG_W=()
	_TXG_H=()
	_TX_DRAG=""
}
_tui_wx.forget() {
	local id="$1"
	unset '_TUI_W_ROWSPAN[$id]' '_WXSEL[$id]' '_WXTOP[$id]' '_WXCOLS[$id]' '_WXH[$id]' '_TUI_W_CHANGE[$id]' \
		'_TXC[$id]' '_TXA[$id]' '_TXS[$id]' '_TXT[$id]' '_TXW[$id]' '_TXH[$id]' '_TXUN[$id]' '_TXRN[$id]' '_TXLK[$id]' '_TXLP[$id]'
}

# markup: <password|textarea|list|table|select|progress ...>  (called by tui_markup.sh)
_markup_wx() {
	local tag="$1" line="$2" id pane row rows items data _ma1 _ma2 _ma3
	_markup_attrv "$line" id id
	_markup_attrv "$line" pane pane
	_markup_attrv "$line" row row
	_markup_attrv "$line" rows rows
	local -a arr=()
	case "$tag" in
		password)
			_markup_attrv "$line" placeholder _ma1
			_markup_attrv "$line" label _ma2
			_markup_attrv "$line" submit _ma3
			tui.password "$id" "$pane" "$row" "$_ma1" "$_ma2" "$_ma3"
			_markup_attrv "$line" label_align _ma1
			tui.label_align "$id" "$_ma1"
			_markup_attrv "$line" label_width _ma1
			tui.label_width "$id" "$_ma1"
			;;
		textarea)
			_markup_attrv "$line" placeholder _ma1
			_markup_attrv "$line" submit _ma2
			tui.textarea "$id" "$pane" "$row" "$_ma1" "${rows:-0}" "$_ma2"
			local v
			_markup_attrv "$line" value v
			[[ -n "$v" ]] && tui.set "$id" "${v//\\n/$'\n'}"
			;;
		list)
			_markup_attrv "$line" action _ma1
			tui.list "$id" "$pane" "$row" "$_ma1" "${rows:-0}"
			_markup_attrv "$line" items items
			if [[ -n "$items" ]]; then
				IFS='|' read -ra arr <<<"$items"
				tui.list.set "$id" "${arr[@]}"
			fi
			;;
		table)
			_markup_attrv "$line" action _ma1
			tui.table "$id" "$pane" "$row" "$_ma1" "${rows:-0}"
			_markup_attrv "$line" data data
			if [[ -n "$data" ]]; then IFS=';' read -ra arr <<<"$data"; fi
			_markup_attrv "$line" columns _ma1
			tui.table.set "$id" "$_ma1" "${arr[@]}"
			;;
		select)
			_markup_attrv "$line" label _ma1
			_markup_attrv "$line" action _ma2
			tui.select "$id" "$pane" "$row" "$_ma1" "$_ma2"
			local sv
			_markup_attrv "$line" value sv
			[[ -n "$sv" ]] && tui.set "$id" "$sv"
			_markup_attrv "$line" items items
			if [[ -n "$items" ]]; then
				IFS='|' read -ra arr <<<"$items"
				tui.select.set "$id" "${arr[@]}"
			fi
			;;
		progress)
			_markup_attrv "$line" label _ma1
			tui.progress "$id" "$pane" "$row" "$_ma1"
			local pv
			_markup_attrv "$line" value pv
			[[ -n "$pv" ]] && tui.set "$id" "$pv"
			;;
	esac
	local oc
	_markup_attrv "$line" on_change oc
	[[ -n "$oc" ]] && tui.on_change "$id" "$oc"
	_markup_attrv "$line" align _ma1
	tui.align "$id" "$_ma1"
	_markup_attrv "$line" valign _ma1
	tui.valign "$id" "$_ma1"
	_markup_attrv "$line" min_width _ma1
	_markup_attrv "$line" min_height _ma2
	tui.minsize "$id" "$_ma1" "$_ma2"
	_markup_attrv "$line" max_width _ma1
	_markup_attrv "$line" max_height _ma2
	tui.maxsize "$id" "$_ma1" "$_ma2"
	local wx_expand wx_width wx_height wx_padding wx_hpad wx_vpad
	_markup_attrv "$line" expand wx_expand
	_markup_attrv "$line" width wx_width
	_markup_attrv "$line" height wx_height
	_markup_attrv "$line" padding wx_padding
	_markup_attrv "$line" hpad wx_hpad
	_markup_attrv "$line" vpad wx_vpad
	[[ -n "$wx_expand" ]] && tui.expand "$id" "$wx_expand"
	[[ -n "$wx_width" ]] && tui.width "$id" "$wx_width"
	[[ -n "$wx_height" ]] && tui.height "$id" "$wx_height"
	_markup_attrv "$line" class _ma1
	_tui_cache_class "$id" "$_ma1"
	tui.pad "$id" "${wx_hpad:-$wx_padding}" "${wx_vpad:-$wx_padding}"
}
