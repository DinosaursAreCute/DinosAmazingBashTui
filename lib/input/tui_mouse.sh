#!/usr/bin/env bash
# tui_mouse.sh - mouse reports: hover tracking, motion coalescing, and the SGR report handler that routes presses to tui_input.sh.
#
#   Internal (_tui._*): _set_hovered_pane, _set_hovered_widget, _pointer_shape_of, _pointer_update, _pointer_reset, _mouse_seq_is_motion, _coalesce_mouse_motion, _handle_mouse
# requires:

# _tui._set_hovered_pane tracks which pane the pointer is over purely as
# routing state for scroll-wheel/keyboard-scroll targeting (_tui._scroll_kb,
# the wheel branch of _tui._handle_mouse) - it does NOT trigger any redraw.
# Pane borders only ever change for focus (see _tui._draw_pane_border), so
# hovering a pane costs one assignment and nothing else.
_tui._set_hovered_pane() { _TUI_HOVERED_PANE="$1"; }

# _tui._set_hovered_widget is change-gated (a no-op unless the hovered
# widget actually differs) but, unlike the deferred scroll queue, draws
# immediately via _tui._draw_widgets_now. A button redraw is one cheap,
# single-widget write - there's no fan-out to collapse the way a multi-pane
# sweep used to cause when panes also redrew their borders on hover, so
# debouncing it only added latency between "pointer arrives" and "button
# lights up" without saving any real work. Trading "many more small draws"
# for "instant feedback" is the right side of that tradeoff here.
_tui._set_hovered_widget() {
	local new="$1"
	[[ "$new" == "$_TUI_HOVERED_WIDGET" ]] && return
	local old="$_TUI_HOVERED_WIDGET"
	_TUI_HOVERED_WIDGET="$new"
	((_TUI_RUNNING)) || return
	_tui._draw_widgets_now "$old" "$new"
}

# Mouse pointer shape (OSC 22, ignored by terminals that lack it). The shape of a widget is its `cursor:` CSS value, else the
# default of its type; anywhere else the terminal's own. TUI_POINTER_SHAPE=0 (Settings > Input) turns it off.
declare -g TUI_POINTER_SHAPE=1 _TUI_POINTER_NOW=""
declare -gA _TUI_POINTER_DEFAULT=([button]=pointer [checkbox]=pointer [select]=pointer [list]=pointer [table]=pointer [input]=text [textarea]=text)

# _tui._pointer_shape_of ZONE_ARG WIDGET_ID X Y -> _PS. An open modal decides alone (its POINTERFN, else the terminal's own pointer); so does
# the blocked page under a modal or popup layer. Else: layer chrome, resize handles and collapse buttons (they sit on borders), the
# widget's `cursor:` (:hover, then :focus, then the base rule), its type default, "default".
_tui._pointer_shape_of() {
	if [[ -n "$_TUI_MODAL" ]]; then
		_PS=default
		[[ -n "$_TUI_MODAL_POINTERFN" ]] && "$_TUI_MODAL_POINTERFN" "$3" "$4"
		return 0
	fi
	if ((_TUI_L_N)) && _tui_layer.blocked; then
		_PS=default
		return 0
	fi
	case "$1" in
		ly-btn:* | ly-dt) _PS=pointer && return 0 ;;
		ly-drag) _PS=move && return 0 ;;
		ly-size) _PS=nwse-resize && return 0 ;;
		rz-h | rz-hl) _PS=col-resize && return 0 ;;
		rz-v | rz-vl) _PS=row-resize && return 0 ;;
		rz-corner) _PS=nwse-resize && return 0 ;;
		cv-*) _PS=pointer && return 0 ;;
	esac
	_PS=default
	[[ -n "$2" ]] || return 0
	_PS="${_TUI_STYLE_CUR[$2_hover]:-}"
	[[ -z "$_PS" && "$2" == "$_TUI_FOCUS_ID" ]] && _PS="${_TUI_STYLE_CUR[$2_focus]:-}"
	_PS="${_PS:-${_TUI_STYLE_CUR[$2_normal]:-${_TUI_POINTER_DEFAULT[${_TUI_W_TYPE[$2]:-}]:-default}}}"
}

# _tui._pointer_update WIDGET_ID ZONE_ARG X Y - sets the pointer shape for what is under the pointer (WIDGET_ID "" for none); writes only on a change.
_tui._pointer_update() {
	((TUI_POINTER_SHAPE)) || {
		_tui._pointer_reset
		return 0
	} # switched off in Settings: give the pointer back
	_tui._pointer_shape_of "${2:-}" "$1" "${3:-}" "${4:-}"
	local shape="$_PS"
	[[ "$shape" == "$_TUI_POINTER_NOW" ]] && return 0
	[[ -z "$_TUI_POINTER_NOW" && "$shape" == default ]] && return 0
	_TUI_POINTER_NOW="$shape"
	printf '\e]22;%s\e\\' "$shape" >&"$_TUI_OUT_FD"
}

# _tui._pointer_reset - hands the pointer back to the terminal (exit, terminal mode).
_tui._pointer_reset() {
	[[ -z "$_TUI_POINTER_NOW" ]] && return 0
	_TUI_POINTER_NOW=""
	printf '\e]22;\e\\' >&"$_TUI_OUT_FD"
}

# _tui._mouse_seq_is_motion SEQ - true for a pure movement report (bare
# hover, or a drag with a button held): the SGR protocol sets bit 32 on
# the button field for any motion sample and terminates it with 'M'. These
# are the only reports safe to discard in favor of a newer one - presses,
# releases, and wheel notches are one-shot state transitions and must
# never be dropped.
_tui._mouse_seq_is_motion() {
	local seq="${1#\[<}"
	[[ "${seq: -1}" == "M" ]] || return 1
	local btn
	IFS=';' read -r btn _ _ <<<"${seq%[Mm]}"
	(((btn & 32) != 0))
}

# _tui._coalesce_mouse_motion SEQ - given a just-decoded motion sequence,
# peeks ahead for more input already sitting in the buffer and keeps only
# the newest motion report, so hover/drag state is resolved (and redrawn)
# at most once per settled position instead of once per crossed cell.
# Anything peeked that ISN'T a coalescible motion report (a click, a wheel
# notch, a keystroke, a non-mouse escape sequence) is not discarded - it's
# rewound into _TUI_PENDING_INPUT byte-for-byte so the normal dispatch
# logic in tui.run handles it next, in its original order, completely
# unaware a peek ever happened. Leaves the resolved sequence in
# _TUI_SEQ_BUF. TUI_MOUSE_DRAIN_MAX bounds the peek loop so an unbroken
# flood can't stall the rest of the event loop indefinitely.
_tui._coalesce_mouse_motion() {
	local pending="$1" drained=0 c
	while ((drained < TUI_MOUSE_DRAIN_MAX)); do
		IFS= read -rsn1 -t "$TUI_MOUSE_DRAIN_PEEK_TIMEOUT" c || break
		((drained++))

		if [[ "$c" != $'\e' ]]; then
			_TUI_PENDING_INPUT+="$c"
			break
		fi

		_tui._read_escape_seq
		local next="$_TUI_SEQ_BUF"

		if [[ "$next" == "[<"* ]] && _tui._mouse_seq_is_motion "$next"; then
			pending="$next"
			continue
		fi

		_TUI_PENDING_INPUT+=$'\e'"$next"
		break
	done
	_TUI_SEQ_BUF="$pending"
}

_tui._handle_mouse() {
	((_TUI_PASSTHROUGH)) && return 0 # stray reports still in flight when the mode started
	local seq="$1"
	seq="${seq#\[<}"
	local end="${seq: -1}"
	seq="${seq%[Mm]}"

	IFS=';' read -r btn mx my <<<"$seq"

	local hover_widget=""
	_tui_hit.at "$mx" "$my" && hover_widget="$_HIT"
	_tui._set_hovered_pane "$_HIT_PANE"
	_tui._set_hovered_widget "$hover_widget"
	_tui_hit.hover # resize handle / collapse button hover (tui_hit.sh)
	local zone="${_TUI_HZ_HOVER:+${_TUI_HZ_HOVER#*|}}"
	[[ -z "$zone" && "$_HIT_KIND" == layer ]] && zone="ly-$_HIT_ARG"
	_tui._pointer_update "$hover_widget" "$zone" "$mx" "$my"

	if [[ -n "$_TUI_ON_INPUT_EVENT" ]]; then
		local kind="move"
		if ((btn >= 64 && btn <= 69)); then
			kind="wheel"
		elif [[ "$end" == "m" ]]; then
			kind="release"
		elif ! _tui._mouse_seq_is_motion "$1"; then
			kind="press"
		fi
		_tui._notify_input "mouse $kind btn=$btn (${mx},${my}) widget=${hover_widget:--} pane=${_HIT_PANE:--}"
	fi

	# Everything below the hover/notify bookkeeping is a binding now:
	# see tui_input.sh (mouse:left, wheel:up, drag:left, ... -> tui.action.*).
	_tui_input.mouse_event "$btn" "$end" "$mx" "$my"
}
