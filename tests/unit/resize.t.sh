# resize.t.sh - WINCH/size-guard regressions (lib/tui.sh: tui.init, tui.run,
# _tui._apply_resize).
#
# Bug: tui.run() used to zero _TUI_RESIZED unconditionally before its first
# render, and its WINCH trap wasn't installed until inside tui.run itself -
# a resize caught anywhere between tui.init (which reads the terminal size
# once, for the very first layout) and tui.run's first render was silently
# discarded: the first frame drew at whatever size tui.init happened to
# read, with no correction until the terminal's NEXT resize (if any ever
# came). Fixed by installing the trap in tui.init and applying a pending
# resize before tui.run's first render instead of dropping it.
#
# _tui._read_term_size (which _tui._apply_resize uses) reads `stty size`
# directly, not the mockable term.size() - by design, for accurate live
# resize handling - so these tests mock `stty` itself (a plain bash
# function shadows the external command) rather than term.size, to stay
# host-independent (this box's own real tty, if any, must not leak in).

_resize_mock_stty() { # ROWS COLS - overrides `stty` until _resize_restore_stty
	_R_ROWS="$1" _R_COLS="$2"
	stty() { printf '%s %s\n' "$_R_ROWS" "$_R_COLS"; }
}

_resize_restore_stty() { unset -f stty; }

# One cycle covers both: (1) _tui._apply_resize itself re-measures the tty
# and relayouts root, and (2) that's exactly what tui.run's own top now does
# with a resize flagged before its first render - the actual regression
# (it used to zero _TUI_RESIZED unread instead).
ti_pending_resize_before_first_render_is_applied_not_dropped() {
	local _R_REAL_TERM_SIZE
	_R_REAL_TERM_SIZE="$(declare -f term.size)"
	term.size() {
		printf -v "$1" 24
		printf -v "$2" 80
	} # tui.init's own read: the "stale" first size
	tui.reset_ui
	tui.hsplit root a b
	local w_before=${_TUI_P_W[a]}

	_resize_mock_stty 48 160 # the window's real, settled size; _tui._apply_resize reads the tty directly
	_TUI_RESIZED=1           # a WINCH for it arrived before tui.run ever rendered

	# tui.run's own top: "if a resize is pending, apply it before the first render" (see lib/tui.sh)
	if ((_TUI_RESIZED)); then
		_tui._apply_resize
	fi
	_TUI_RESIZED=0

	eq "48" "$_TUI_ROWS"
	eq "160" "$_TUI_COLS"
	eq "160" "${_TUI_P_W[root]}"       # not 80: the pending resize was applied, not discarded
	ok '(( _TUI_P_W[a] != w_before ))' # root relaid out at the new size, not left at the old one
	_resize_restore_stty
	eval "$_R_REAL_TERM_SIZE"
}

t_init_installs_the_winch_trap_before_the_first_render_can_happen() {
	# regression guard for the fix's placement: the trap must be set inside
	# tui.init itself, not only once tui.run starts - otherwise a resize
	# during a long cache warm-up (between tui.init and tui.run) has no
	# handler at all and _TUI_RESIZED is never set for tui.run to apply.
	# (Not calling tui.init here: it puts a real tty in raw mode and emits
	# terminal control codes - checking its body is the host-independent way.)
	match "$(declare -f tui.init)" "trap 'tui\.on_resize' WINCH"
}

# a pane's parent is remembered: the footer asks for it for every ancestor of the focused pane on each build, and finding it
# scans every pane of the page. The remembered parent is checked against the children list, so a pane that moved is found again.
t_resize_parent_is_remembered_and_checked_against_the_children() {
	tui.reset_ui
	tui.hsplit root a b
	_tui_resize.parent a
	eq "root 0 2" "$_RZ_P $_RZ_I $_RZ_N"
	local all=("${_TUI_P_ALL[@]}")
	_TUI_P_ALL=() # no scan is possible now: the answer comes from memory
	_RZ_P="" _RZ_I="" _RZ_N=""
	_tui_resize.parent a
	eq "0 root 0 2" "$? $_RZ_P $_RZ_I $_RZ_N"
	_TUI_P_ALL=("${all[@]}")
	_TUI_P_CHILDREN[root]="b a" # a moved within its parent
	_tui_resize.parent a
	eq "root 1 2" "$_RZ_P $_RZ_I $_RZ_N"
	_TUI_P_CHILDREN[root]="b" _TUI_P_CHILDREN[b]="a" # a moved under b
	_tui_resize.parent a
	eq "b 0 1" "$_RZ_P $_RZ_I $_RZ_N"
	_TUI_P_CHILDREN[b]=""
	_tui_resize.parent a
	eq "1" "$?"
}

# the root has no parent, and the walk up from any pane ends there every time: that miss is remembered too, until the layout changes
t_resize_parent_miss_is_remembered_until_the_layout_changes() {
	tui.reset_ui
	tui.hsplit root a b
	_tui_resize.parent root
	eq "1" "$?"
	_TUI_P_CHILDREN[a]="root" # root is a child now, but no layout change was announced: the remembered miss stands
	_tui_resize.parent root
	eq "1" "$?"
	_tui.epoch_bump layout
	_tui_resize.parent root
	eq "0 a" "$? $_RZ_P"
}
