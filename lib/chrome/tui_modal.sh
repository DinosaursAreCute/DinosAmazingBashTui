#!/usr/bin/env bash
# tui_modal.sh - the modal preset of the layer stack (tui_layer.sh): a function layer that also owns the input. The
# foundation for the command palette (tui_cmd.sh), dialogs and prompts. Its draw function is a top function layer, so
# every repaint of the page under it is followed by it (_tui._flush); removing it is a full repaint (tui.relayout).
#
# A MODAL is a layer that owns the input: while one is open every key goes to its handler and the
# mouse goes to its mouse handler (or is ignored) - bindings, focus, scrolling and the pointer are
# suspended. Only the terminal-control chord (ctrl+alt+p) and quit-on-SIGINT still work.
#   tui.modal.open NAME KEYFN DRAWFN [MOUSEFN]
#       KEYFN   NAME_OF_KEY     canonical key name ("a", "enter", "ctrl+p", "up"...); "paste" with TUI_EVENT_PASTE
#       DRAWFN                  draws the modal
#       MOUSEFN EVENT X Y       EVENT = mouse:left, wheel:up, ...  (absolute 1-based cell)
#   tui.modal.close             remove it and repaint the screen
#   tui.modal.active [NAME]     rc 0 while a modal (or that one) is open
#   tui.modal.redraw            draw now (call after your state changes)
# requires: tui_layer
declare -g _TUI_MODAL="" _TUI_MODAL_KEYFN="" _TUI_MODAL_DRAWFN="" _TUI_MODAL_MOUSEFN=""

declare -gi _TUI_FLUSH_GEN=0
# Last full-render frame (saved by tui.render). tui.modal.dismiss replays it instead of re-composing the page
# while nothing but overlays has painted since: _TUI_FLUSH_GEN - _TUI_BASE_GEN counts every flush after the base,
# _TUI_OVL_FLUSHES the ones that were layer-stack draws. Other paints are folded into it (_tui_modal.base_fold); an erase, restyle or resize invalidates it.
declare -g _TUI_BASE_FRAME=""
declare -gi _TUI_BASE_GEN=-1 _TUI_OVL_FLUSHES=0 _TUI_BASE_EPOCH=-1 _TUI_BASE_ROWS=0 _TUI_BASE_COLS=0
declare -gi _TUI_OVL_FLUSHING=0
declare -gi _TUI_DISMISS_REPLAY="${TUI_DISMISS_REPLAY:-1}"
tui.modal.active() { [[ -n "$_TUI_MODAL" && (-z "${1:-}" || "$_TUI_MODAL" == "$1") ]]; }
tui.modal.redraw() {
	[[ -n "$_TUI_MODAL_DRAWFN" ]] && _tui_layer.draw_all
	return 0
}

tui.modal.open() {
	[[ -n "$_TUI_MODAL" ]] && tui.modal.close
	_TUI_MODAL="$1"
	_TUI_MODAL_KEYFN="$2"
	_TUI_MODAL_DRAWFN="$3"
	_TUI_MODAL_MOUSEFN="${4:-}"
	tui.layer.fn_add "$3"
	_tui_async.cover_changed
	((_TUI_RUNNING)) && _tui_layer.draw_all
	return 0
}

tui.modal.close() {
	[[ -n "$_TUI_MODAL" ]] || return 0
	tui.layer.fn_remove "$_TUI_MODAL_DRAWFN"
	_TUI_MODAL=""
	_TUI_MODAL_KEYFN=""
	_TUI_MODAL_DRAWFN=""
	_TUI_MODAL_MOUSEFN=""
	_tui_async.cover_changed
	tui.relayout # one synchronized full repaint: the overlay is gone, everything under it is back
}

# _tui_modal.base_fold BUF - BUF was just painted over the page (a tick, hover or focus repaint): append it to the saved
# frame, which stays an exact replay of the screen because later paint bytes overwrite earlier ones. Bounded: past the
# cap, or on a style/size change, the base is dropped and the next dismissal does the full repaint.
_tui_modal.base_fold() {
	((_TUI_BASE_GEN >= 0)) || return 0
	if ((${#_TUI_BASE_FRAME} < 196608)) && _tui_modal.base_valid; then
		_TUI_BASE_FRAME+="$1"
		_TUI_BASE_GEN+=1
	else
		_TUI_BASE_GEN=-1
		_TUI_BASE_FRAME=""
	fi
}

_tui_modal.base_valid() {
	((_TUI_CACHES)) || return 1
	((_TUI_DISMISS_REPLAY && _TUI_BASE_GEN >= 0 && _TUI_FLUSH_GEN - _TUI_BASE_GEN == _TUI_OVL_FLUSHES)) || return 1
	((_TUI_BASE_EPOCH == _TUI_RC_EPOCH && _TUI_BASE_ROWS == _TUI_ROWS && _TUI_BASE_COLS == _TUI_COLS)) || return 1
	[[ -n "$_TUI_BASE_FRAME" ]]
}

# tui.modal.dismiss - close without running anything (esc, click outside). Replays the saved base frame when it is
# still what the screen shows under the overlay; otherwise the full tui.modal.close repaint. Not for closes that
# precede an action: the action may change state the base frame does not know about.
tui.modal.dismiss() {
	[[ -n "$_TUI_MODAL" ]] || return 0
	if ! _tui_modal.base_valid; then
		_tui_perf.count dismiss_full
		tui.modal.close
		return
	fi
	_tui_perf.begin dismiss
	_tui_perf.count dismiss_replay
	_tui_modal.reset
	mode.sync_start
	erase.all
	_tui._flush "$_TUI_BASE_FRAME"
	_TUI_BASE_GEN=$_TUI_FLUSH_GEN
	_TUI_OVL_FLUSHES=0
	((_TUI_KEYS_SUSPENDED)) && _tui_input.draw_overlay
	_tui_layer.draw_all
	mode.sync_end
	_tui_perf.end dismiss
}

# tui.reset_ui: a modal never survives a page change
_tui_modal.reset() {
	[[ -n "$_TUI_MODAL" ]] || return 0
	tui.layer.fn_remove "$_TUI_MODAL_DRAWFN"
	_TUI_MODAL=""
	_TUI_MODAL_KEYFN=""
	_TUI_MODAL_DRAWFN=""
	_TUI_MODAL_MOUSEFN=""
	_tui_async.cover_changed
}

# tui.overlay.box ROW COL WIDTH SGR TITLE LINE... - appends a framed box to _TUI_FRAME (for overlay/modal
# DRAWFNs, always called from _tui_layer.draw_all's build/flush cycle - never prints directly).
#   SGR: the colours as SGR parameters, e.g. "1;97;44".  LINEs are cut/padded to the inner width. No state kept.
tui.overlay.box() {
	local row="$1" col="$2" w="$3" sgr="$4" title="$5"
	shift 5
	local inner=$((w - 2)) bar hz line sp t out=$'\e7' r="$row"
	printf -v bar '%*s' "$inner" ''
	hz="${bar// /─}"
	t=" $title "
	out+=$'\e['"${sgr}m"$'\e['"${r};${col}H┌─${t}${hz:0:$((inner - ${#t} - 1))}┐"
	for line in "$@"; do
		((r++))
		line=" ${line}"
		line="${line:0:$inner}"
		printf -v sp '%*s' "$((inner - ${#line}))" ''
		out+=$'\e['"${r};${col}H│${line}${sp}│"
	done
	((r++))
	out+=$'\e['"${r};${col}H└${hz}┘"$'\e[0m\e8'
	_TUI_FRAME+="$out"
}
