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

declare -gA _TUI_W_ROWSPAN=() _WXSEL=() _WXTOP=() _WXCOLS=() _WXH=() _WXPCT=() _WXF=()
declare -g _WX_TARGET="" _WX_CLICK_T=0 _WX_CLICK_ID="" _WX_CLICK_I=-1

# _tui_wx.new ID TYPE PANE ROW FOCUSABLE : common widget bookkeeping (the same fields tui.button sets)
_tui_wx.new() {
	local id="$1" type="$2"
	if [[ -z "$id" || -z "$3" ]]; then
		echo "tui.$type: missing id or pane, skipping widget" >&2
		return 1
	fi
	_TUI_W_TYPE[$id]="$type"
	_TUI_W_PANE[$id]="$3"
	_TUI_W_ROW[$id]="$4"
	_TUI_W_LABEL[$id]=""
	_TUI_W_VALUE[$id]=""
	_TUI_W_ACTION[$id]=""
	_TUI_W_ORDER+=("$id")
	[[ "$5" == 1 ]] && _TUI_FOCUSABLE+=("$id")
	return 0
}

tui.password() {
	_tui_wx.new "$1" password "$2" "$3" 1 || return 1
	_TUI_W_PH[$1]="${4:-}"
	_TUI_W_LABEL[$1]="${5:-}"
	_TUI_W_SUBMIT[$1]="${6:-}"
}
tui.textarea() {
	_tui_wx.new "$1" textarea "$2" "$3" 1 || return 1
	_TUI_W_PH[$1]="${4:-}"
	_TUI_W_ROWSPAN[$1]="${5:-0}"
	_TUI_W_SUBMIT[$1]="${6:-}"
}
tui.list() {
	_tui_wx.new "$1" list "$2" "$3" 1 || return 1
	_TUI_W_ACTION[$1]="${4:-}"
	_TUI_W_ROWSPAN[$1]="${5:-0}"
	_WXSEL[$1]=-1
	_WXTOP[$1]=0
	_tui_wx.arr "$1"
	_WXA=()
}
tui.table() {
	_tui_wx.new "$1" table "$2" "$3" 1 || return 1
	_TUI_W_ACTION[$1]="${4:-}"
	_TUI_W_ROWSPAN[$1]="${5:-0}"
	_WXSEL[$1]=-1
	_WXTOP[$1]=0
	_WXCOLS[$1]=""
	_tui_wx.arr "$1"
	_WXA=()
}
tui.select() {
	_tui_wx.new "$1" select "$2" "$3" 1 || return 1
	_TUI_W_LABEL[$1]="${4:-}"
	_TUI_W_ACTION[$1]="${5:-}"
	_WXSEL[$1]=-1
	_tui_wx.arr "$1"
	_WXA=()
}
tui.progress() {
	_tui_wx.new "$1" progress "$2" "$3" 0 || return 1
	_TUI_W_LABEL[$1]="${4:-}"
	_TUI_W_VALUE[$1]=0
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
tui.list.selected() { printf '%s\n' "${_WXSEL[$1]:--1}"; }
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
tui.table.selected() { tui.list.selected "$1"; }
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
	_TUI_W_VALUE[$1]="${_WXA[i]}"
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
	_TUI_W_VALUE[$1]=$v
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

# _tui_wx.draw ID TYPE SR SC SW SH FOCUSED HOVERED STYLE_KEY PANE_KEY   (called by _tui._draw_widget)
_tui_wx.draw() {
	local id="$1" type="$2" sr="$3" sc="$4" sw="$5" sh="$6" focused="$7" hovered="$8" sk="$9" pk="${10}"
	case "$type" in
		input | password) _tui_text.draw_line "$id" "$sr" "$sc" "$sw" "$focused" "$sk" "$pk" ;;
		textarea) _tui_text.draw_area "$id" "$sr" "$sc" "$sw" "$sh" "$focused" "$sk" "$pk" ;;
		list | table) _tui_wx.draw_rows "$id" "$type" "$sr" "$sc" "$sw" "$sh" "$focused" "$sk" "$pk" ;;
		select) _tui_wx.draw_select "$id" "$sr" "$sc" "$sw" "$focused" "$sk" "$pk" ;;
		progress) _tui_wx.draw_progress "$id" "$sr" "$sc" "$sw" "$sk" "$pk" ;;
	esac
}

_tui_wx.draw_select() {
	local id="$1" sr="$2" sc="$3" sw="$4" focused="$5" sk="$6" pk="$7"
	local label="${_TUI_W_LABEL[$id]:-}" v="${_TUI_W_VALUE[$id]:-}" lw=0 line
	[[ -z "$v" ]] && v="(none)"
	[[ -n "$label" ]] && {
		lw=$((${#label} + 1))
		style.bold
		printf '%s ' "$label"
		style.reset
	}
	_tui._apply_style "$sk" "$pk"
	((focused)) && style.reverse || { [[ -z "${_TUI_STYLE_FG[$sk]:-}" ]] && style.dim; }
	local fw=$((sw - lw))
	line="[ ${v} ▾ ]"
	_tui_text.padc "$line" "$fw"
	printf '%s' "$_PADC"
	style.reset
}

_tui_wx.draw_progress() {
	local id="$1" sr="$2" sc="$3" sw="$4" sk="$5" pk="$6"
	local label="${_TUI_W_LABEL[$id]:-}" pct=${_TUI_W_VALUE[$id]:-0} lw=0 bw fill
	[[ "$pct" =~ ^[0-9]+$ ]] || pct=0
	((pct > 100)) && pct=100
	[[ -n "$label" ]] && {
		lw=$((${#label} + 1))
		printf '%s ' "$label"
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
	printf '%s%s%s%s%s %3d%%' "$f" "${fs// /█}" "$e" "${es// /░}" $'\e[0m' "$pct"
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

	_tui._apply_style "$sk" "$pk"
	_tui._style_v "$sk" "$pk"
	local base="$_SGR"
	local cls=list_sel
	((hdr)) && cls=table_sel
	tui.class.sgr "$cls"
	local selsgr="${TUI_SGR:-$'\e[0;97;48;2;62;92;138m'}"
	local rowi=0
	if ((hdr)); then
		cur.goto "$sr" "$sc"
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
		printf '%s%s%s%s' "$hs" "$line" $'\e[0m' "$base"
		rowi=1
	fi
	for ((i = 0; i < rows; i++)); do
		cur.goto $((sr + rowi + i)) "$sc"
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
					printf '%s%s%s%s' "$selsgr" "$line" $'\e[0m' "$base"
				else printf '%s%s%s%s' $'\e[7m' "$line" $'\e[27m' "$base"; fi
			else printf '%s' "$line"; fi
		else printf '%*s' "$fw" ""; fi
		if ((sw > fw)); then # scroll indicator
			local thumb=$((top * (rows - 1) / (n - rows > 0 ? n - rows : 1)))
			cur.goto $((sr + rowi + i)) $((sc + fw))
			((i == thumb)) && printf '▐' || printf ' '
		fi
	done
	style.reset
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
	local tag="$1" line="$2" id pane row rows items data
	id="$(_markup_attr "$line" id)"
	pane="$(_markup_attr "$line" pane)"
	row="$(_markup_attr "$line" row)"
	rows="$(_markup_attr "$line" rows)"
	local -a arr=()
	case "$tag" in
		password)
			tui.password "$id" "$pane" "$row" "$(_markup_attr "$line" placeholder)" "$(_markup_attr "$line" label)" "$(_markup_attr "$line" submit)"
			tui.label_align "$id" "$(_markup_attr "$line" label_align)"
			tui.label_width "$id" "$(_markup_attr "$line" label_width)"
			;;
		textarea)
			tui.textarea "$id" "$pane" "$row" "$(_markup_attr "$line" placeholder)" "${rows:-0}" "$(_markup_attr "$line" submit)"
			local v
			v="$(_markup_attr "$line" value)"
			[[ -n "$v" ]] && tui.set "$id" "${v//\\n/$'\n'}"
			;;
		list)
			tui.list "$id" "$pane" "$row" "$(_markup_attr "$line" action)" "${rows:-0}"
			items="$(_markup_attr "$line" items)"
			if [[ -n "$items" ]]; then
				IFS='|' read -ra arr <<<"$items"
				tui.list.set "$id" "${arr[@]}"
			fi
			;;
		table)
			tui.table "$id" "$pane" "$row" "$(_markup_attr "$line" action)" "${rows:-0}"
			data="$(_markup_attr "$line" data)"
			if [[ -n "$data" ]]; then IFS=';' read -ra arr <<<"$data"; fi
			tui.table.set "$id" "$(_markup_attr "$line" columns)" "${arr[@]}"
			;;
		select)
			tui.select "$id" "$pane" "$row" "$(_markup_attr "$line" label)" "$(_markup_attr "$line" action)"
			local sv
			sv="$(_markup_attr "$line" value)"
			[[ -n "$sv" ]] && tui.set "$id" "$sv"
			items="$(_markup_attr "$line" items)"
			if [[ -n "$items" ]]; then
				IFS='|' read -ra arr <<<"$items"
				tui.select.set "$id" "${arr[@]}"
			fi
			;;
		progress)
			tui.progress "$id" "$pane" "$row" "$(_markup_attr "$line" label)"
			local pv
			pv="$(_markup_attr "$line" value)"
			[[ -n "$pv" ]] && tui.set "$id" "$pv"
			;;
	esac
	local oc
	oc="$(_markup_attr "$line" on_change)"
	[[ -n "$oc" ]] && tui.on_change "$id" "$oc"
	tui.align "$id" "$(_markup_attr "$line" align)"
	tui.valign "$id" "$(_markup_attr "$line" valign)"
	tui.minsize "$id" "$(_markup_attr "$line" min_width)"
	tui.maxsize "$id" "$(_markup_attr "$line" max_width)"
	tui.class "$id" "$(_markup_attr "$line" class)"
	tui.pad "$id" "$(_markup_attr "$line" hpad)" "$(_markup_attr "$line" vpad)"
}
