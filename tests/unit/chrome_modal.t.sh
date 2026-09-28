#!/usr/bin/env bash
# chrome_modal.t.sh - lib/chrome/tui_modal.sh buffer-mode overlay draw path (stage 0.3).

t_overlay_box_appends_to_frame() {
	_TUI_FRAME="prefix:"
	tui.overlay.box 2 3 10 "1;97;44" "T" "hi"
	ok '[[ "$_TUI_FRAME" == prefix:$'"'"'\e7'"'"'* ]]'
	ok '[[ "$_TUI_FRAME" == *$'"'"'\e[0m\e8'"'"' ]]'
}

t_overlay_draw_all_builds_one_frame_and_flushes_it_through_flush() {
	local _real_flush _flushed_with=""
	_real_flush="$(declare -f _tui._flush)"
	_tui._flush() { _flushed_with="$1"; }
	_t_ovl_fn() { _tui.emit "OVL"; }

	local -a _TUI_OVERLAY_FNS=(_t_ovl_fn)
	_TUI_FRAME="untouched"
	_tui_overlay.draw_all
	eq "OVL" "$_flushed_with"
	eq "untouched" "$_TUI_FRAME" # restored after the standalone build/flush

	eval "$_real_flush"
	unset -f _t_ovl_fn
}
