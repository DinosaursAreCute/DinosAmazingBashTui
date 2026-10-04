#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════════════╗
# ║    tui_emit.sh                                                          ║
# ╚════════════════════════════════════════════════════════════════════════╝
# Buffer-mode paint primitives (markup-v2 stage 0.3). Draw paths append to
# the shared _TUI_FRAME string via printf -v instead of writing to stdout,
# so a full render is one write instead of one write per glyph/style
# change. _tui._flush (lib/tui.sh) is still the only place bytes reach the
# terminal; callers reset _TUI_FRAME, run draw functions, then flush it
# once.
#
# _tui._apply_style/_tui._apply_ring (lib/tui.sh) print directly and stay
# that way: they're also called from outside the render path (e.g.
# tui_api.sh's standalone pane repaint), which still wants an immediate
# write. _tui.emit_style/_tui.emit_ring below are the buffer-mode
# equivalents, used only by draw paths that build into _TUI_FRAME.

declare -g _TUI_FRAME=""

# _tui.emit TEXT... - appends TEXT (args joined by IFS) to _TUI_FRAME.
# Native += (no fork), not self-referencing printf -v (printf -v _TUI_FRAME
# '%s%s' "$_TUI_FRAME" ...): that re-materializes the whole (growing) string
# through the format engine on every call - O(n) per call, so a full page
# of emits goes quadratic. += extends the existing buffer instead. Measured
# 300x for 20k appends of a real frame's size.
_tui.emit() {
	_TUI_FRAME+="$*"
}

_tui.emit_goto() { # ROW COL
	local _e_s
	printf -v _e_s '\e[%d;%dH' "$1" "$2"
	_TUI_FRAME+="$_e_s"
}

_tui.emit_reset() { _TUI_FRAME+=$'\e[0m'; }

# _tui.emit_sgr CODE - one bare SGR code, e.g. 1 (bold), 2 (dim), 7 (reverse).
_tui.emit_sgr() {
	local _e_s
	printf -v _e_s '\e[%sm' "$1"
	_TUI_FRAME+="$_e_s"
}

# _tui.emit_fg_hex HEX - 24-bit foreground colour (mirrors fg.hex).
_tui.emit_fg_hex() {
	local hex="${1#\#}" _e_s
	printf -v _e_s '\e[38;2;%d;%d;%dm' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
	_TUI_FRAME+="$_e_s"
}

# _tui.emit_printf FMT ARGS... - printf's own formatting, appended instead
# of printed. Covers every remaining literal printf call in a draw path
# (padding, truncation, multi-field layout) with one helper instead of one
# per shape.
_tui.emit_printf() {
	local _ep_text
	printf -v _ep_text "$@"
	_tui.emit "$_ep_text"
}

# _tui.emit_pad WIDTH - WIDTH blank columns.
_tui.emit_pad() {
	local blank
	printf -v blank '%*s' "$1" ""
	_tui.emit "$blank"
}

# _tui.emit_repeat CH N - N copies of single-width char CH (border runs).
_tui.emit_repeat() {
	_tui._repeat_v "$1" "$2"
	_tui.emit "$_R"
}

# _tui.emit_style KEY [FALLBACK] [BGFALLBACK] - the same fg/bg/mods
# resolution as _tui._apply_style, appended instead of printed. Reuses the
# existing fork-free _tui._style_v resolver (lib/tui.sh); an unknown colour
# name falls back to _tui._style_v's own slow, capturing path, same as the
# hot render code that already calls it.
_tui.emit_style() {
	_tui._style_v "$@"
	_tui.emit "$_SGR"
}

# _tui.emit_ring KEY FALLBACK ID - _tui._apply_ring's fg/bg/mods
# resolution (KEY falling back to FALLBACK for fg/mods, FALLBACK's own bg
# falling back to ID's normal bg), appended as one SGR sequence. Falls back
# to the slow capturing path only for a colour name outside the 16 ANSI
# names known to _tui._sgr_from - rare, borders overwhelmingly use hex or
# a named colour.
_tui.emit_ring() {
	local key="$1" fb="$2" id="$3" fg bg mods
	if [[ -n "$_TUI_RESIZE_PANE" && "$id" == "$_TUI_RESIZE_PANE" ]]; then # keyboard resize mode: the target's border looks hovered
		if _tui_hit.class_sgr resize_handle 1 "$id"; then _tui.emit "$_SGR"; else _tui.emit $'\e[1;97m'; fi
		return
	fi
	fg="${_TUI_STYLE_FG[$key]:-${_TUI_STYLE_FG[$fb]:-}}"
	mods="${_TUI_STYLE_MOD[$key]:-${_TUI_STYLE_MOD[$fb]:-}}"
	bg="${_TUI_STYLE_BG[$fb]:-${_TUI_STYLE_BG[${id}_normal]:-}}"
	if _tui._sgr_from "$fg" "$bg" "$mods"; then
		_tui.emit "$_SGR"
		return
	fi
	local seq="" m
	if [[ -n "$fg" ]]; then
		if [[ "$fg" == \#* ]]; then seq+="$(fg.hex "$fg" 2>/dev/null)"; else seq+="$("fg.$fg" 2>/dev/null)"; fi
	fi
	if [[ -n "$bg" ]]; then
		if [[ "$bg" == \#* ]]; then seq+="$(bg.hex "$bg" 2>/dev/null)"; else seq+="$("bg.$bg" 2>/dev/null)"; fi
	fi
	for m in $mods; do seq+="$("style.$m" 2>/dev/null)"; done
	_tui.emit "$seq"
}
