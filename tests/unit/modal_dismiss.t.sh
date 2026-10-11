# modal_dismiss.t.sh - tui.modal.dismiss replays the saved base frame only while it still matches the screen.

_md_draw() { :; }
_md_open_valid() {
	_TUI_MODAL=m _TUI_MODAL_DRAWFN=_md_draw _TUI_FL_ORDER=(_md_draw) _TUI_FL_TOP=1
	_TUI_BASE_FRAME="BASEFRAME"
	_TUI_DISMISS_REPLAY=1
	_TUI_BASE_GEN=$_TUI_FLUSH_GEN _TUI_OVL_FLUSHES=0
	_TUI_BASE_EPOCH=$_TUI_RC_EPOCH _TUI_BASE_ROWS=$_TUI_ROWS _TUI_BASE_COLS=$_TUI_COLS
}

t_dismiss_replays_base_frame_when_valid() {
	_t_needs_caches || return 0
	_md_open_valid
	local out
	tui.modal.dismiss >"$_T_ROOT/md.out"
	out="$(<"$_T_ROOT/md.out")"
	match "$out" 'BASEFRAME'
}

t_dismiss_clears_the_modal() {
	_md_open_valid
	tui.modal.dismiss >/dev/null
	eq "" "$_TUI_MODAL"
}

t_dismiss_overlay_flushes_do_not_invalidate() {
	_t_needs_caches || return 0
	_md_open_valid
	_TUI_FLUSH_GEN+=2 _TUI_OVL_FLUSHES=2
	local out
	tui.modal.dismiss >"$_T_ROOT/md.out"
	out="$(<"$_T_ROOT/md.out")"
	match "$out" 'BASEFRAME'
}

t_dismiss_unknown_painter_invalidates() {
	_md_open_valid
	_TUI_FLUSH_GEN+=1 # something painted without telling the base frame
	tui.modal.dismiss >"$_T_ROOT/md.out"
	local out
	out="$(<"$_T_ROOT/md.out")"
	[[ "$out" != *BASEFRAME* ]] || _t_fail "replayed a stale base frame"
}

t_dismiss_tick_repaint_is_folded_into_the_base() {
	_t_needs_caches || return 0
	_md_open_valid
	_tui._flush "TICKBYTES" >/dev/null # a clock tick under the overlay
	tui.modal.dismiss >"$_T_ROOT/md.out"
	local out
	out="$(<"$_T_ROOT/md.out")"
	match "$out" 'BASEFRAMETICKBYTES'
}

t_dismiss_overlay_draw_is_not_folded_into_the_base() {
	_t_needs_caches || return 0
	_md_open_valid
	_TUI_OVL_FLUSHING=1
	_tui._flush "OVERLAYBYTES" >/dev/null
	_TUI_OVL_FLUSHING=0
	_TUI_OVL_FLUSHES+=1
	tui.modal.dismiss >"$_T_ROOT/md.out"
	local out
	out="$(<"$_T_ROOT/md.out")"
	match "$out" 'BASEFRAME'
	[[ "$out" != *OVERLAYBYTES* ]] || _t_fail "overlay bytes replayed"
}

t_dismiss_oversized_base_is_dropped() {
	_md_open_valid
	printf -v _TUI_BASE_FRAME '%*s' 200000 ""
	_tui._flush "X" >/dev/null
	eq -1 "$_TUI_BASE_GEN"
}

t_dismiss_style_change_invalidates() {
	_md_open_valid
	_TUI_RC_EPOCH+=1
	local out
	tui.modal.dismiss >"$_T_ROOT/md.out"
	out="$(<"$_T_ROOT/md.out")"
	[[ "$out" != *BASEFRAME* ]] || _t_fail "replayed a stale base frame"
}

t_dismiss_resize_invalidates() {
	_md_open_valid
	local cols=$_TUI_COLS out
	_TUI_COLS+=1
	tui.modal.dismiss >"$_T_ROOT/md.out"
	out="$(<"$_T_ROOT/md.out")"
	_TUI_COLS=$cols
	[[ "$out" != *BASEFRAME* ]] || _t_fail "replayed a stale base frame"
}

t_dismiss_erase_invalidates() {
	_md_open_valid
	erase.all >/dev/null
	local out
	tui.modal.dismiss >"$_T_ROOT/md.out"
	out="$(<"$_T_ROOT/md.out")"
	[[ "$out" != *BASEFRAME* ]] || _t_fail "replayed a stale base frame"
}

t_dismiss_switch_off_never_replays() {
	_md_open_valid
	_TUI_DISMISS_REPLAY=0
	local out
	tui.modal.dismiss >"$_T_ROOT/md.out"
	out="$(<"$_T_ROOT/md.out")"
	[[ "$out" != *BASEFRAME* ]] || _t_fail "replayed with the switch off"
}
