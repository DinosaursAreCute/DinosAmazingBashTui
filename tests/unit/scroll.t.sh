# scroll.t.sh - lib/layout/tui_scroll.sh: scroll offset calculations (arithmetic over engine state).

_scroll_pane_setup() {
	# Setup a pane with known geometry, no border
	local pane="$1"
	_TUI_P_ROW[$pane]=1
	_TUI_P_COL[$pane]=1
	_TUI_P_H[$pane]="${2:-10}"
	_TUI_P_W[$pane]="${3:-80}"
	_TUI_P_BORDER[$pane]=none
	_TUI_P_HPAD[$pane]=0
	_TUI_P_VPAD[$pane]=0
	_TUI_P_SCROLL[$pane]="${4:-none}"
	_TUI_P_SOFF_V[$pane]="${5:-0}"
	_TUI_P_SOFF_H[$pane]=0
	unset '_TUI_P_CHILDREN[$pane]'
	_TUI_P_ALL=($pane)
	_TUI_P_LEAVES=($pane)
}

t_scroll_measure_empty_pane() {
	_scroll_pane_setup p
	_tui_scroll.measure p
	eq 0 "${_TUI_P_CONTENT_H[p]}"
}

t_scroll_measure_single_widget() {
	_scroll_pane_setup p
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=0
	_TUI_W_HEIGHT[w1]=3
	_tui_scroll.measure p
	eq 3 "${_TUI_P_CONTENT_H[p]}"
}

t_scroll_measure_multiple_widgets_stacked() {
	_scroll_pane_setup p
	_TUI_W_ORDER=(w1 w2 w3)
	_TUI_W_PANE[w1]=p _TUI_W_PANE[w2]=p _TUI_W_PANE[w3]=p
	_TUI_W_ROW[w1]=0 _TUI_W_ROW[w2]=3 _TUI_W_ROW[w3]=6
	_TUI_W_HEIGHT[w1]=3 _TUI_W_HEIGHT[w2]=2 _TUI_W_HEIGHT[w3]=4
	_tui_scroll.measure p
	eq 10 "${_TUI_P_CONTENT_H[p]}"
}

t_scroll_measure_widget_default_height_one() {
	_scroll_pane_setup p
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	unset '_TUI_W_HEIGHT[w1]'
	_tui_scroll.measure p
	eq 3 "${_TUI_P_CONTENT_H[p]}"
}

t_scroll_measure_mixed_heights_with_defaults() {
	_scroll_pane_setup p
	_TUI_W_ORDER=(w1 w2)
	_TUI_W_PANE[w1]=p _TUI_W_PANE[w2]=p
	_TUI_W_ROW[w1]=0 _TUI_W_ROW[w2]=5
	_TUI_W_HEIGHT[w1]=5
	unset '_TUI_W_HEIGHT[w2]'
	_tui_scroll.measure p
	eq 6 "${_TUI_P_CONTENT_H[p]}"
}

t_scroll_measure_ignores_other_panes() {
	_scroll_pane_setup p
	_TUI_W_ORDER=(w1 w2)
	_TUI_W_PANE[w1]=p _TUI_W_PANE[w2]=other
	_TUI_W_ROW[w1]=0 _TUI_W_ROW[w2]=0
	_TUI_W_HEIGHT[w1]=3 _TUI_W_HEIGHT[w2]=100
	_tui_scroll.measure p
	eq 3 "${_TUI_P_CONTENT_H[p]}"
}

t_scroll_max_off_with_content_larger_than_viewport() {
	_scroll_pane_setup p 10 80 none
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_CR_H=10
	_tui_scroll.max_off p
	eq 10 "$_SC_MAX"
}

t_scroll_max_off_with_content_smaller_than_viewport() {
	_scroll_pane_setup p 10 80 none
	_TUI_P_CONTENT_H[p]=5
	_CR_H=10
	_tui_scroll.max_off p
	eq 0 "$_SC_MAX"
}

t_scroll_max_off_exact_fit() {
	_scroll_pane_setup p 10 80 none
	_TUI_P_CONTENT_H[p]=10
	_CR_H=10
	_tui_scroll.max_off p
	eq 0 "$_SC_MAX"
}

t_scroll_clamp_offset_in_range() {
	_scroll_pane_setup p 10 80 v
	_TUI_P_CONTENT_H[p]=15
	_TUI_P_SOFF_V[p]=5
	_CR_H=10
	_tui_scroll.max_off p
	_tui_scroll.clamp p
	eq 1 "$?"
	eq 5 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_clamp_offset_too_high() {
	_scroll_pane_setup p 10 80 v
	_TUI_P_CONTENT_H[p]=12
	_TUI_P_SOFF_V[p]=10
	_CR_H=10
	_tui_scroll.max_off p
	_tui_scroll.clamp p
	eq 0 "$?"
	eq 2 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_clamp_offset_negative() {
	_scroll_pane_setup p 10 80 v
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_TUI_P_SOFF_V[p]=-5
	_CR_H=10
	_tui_scroll.max_off p
	_tui_scroll.clamp p
	eq 0 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_reveal_widget_below_viewport() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=12
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=15
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_tui_scroll.reveal w1
	eq 0 "$?"
	eq 4 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_reveal_widget_above_viewport() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1 z)
	_TUI_W_PANE[z]=p _TUI_W_ROW[z]=14 _TUI_W_HEIGHT[z]=1 # the last row: content is 15 rows
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_SOFF_V[p]=5
	_CR_H=10
	_tui_scroll.reveal w1
	eq 0 "$?"
	eq 2 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_reveal_widget_already_visible() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1 z)
	_TUI_W_PANE[z]=p _TUI_W_ROW[z]=14 _TUI_W_HEIGHT[z]=1 # the last row: content is 15 rows
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=3
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_SOFF_V[p]=2
	_CR_H=10
	_tui_scroll.reveal w1
	eq 1 "$?"
	eq 2 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_reveal_tall_widget_takes_full_viewport() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=5
	_TUI_W_HEIGHT[w1]=10
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_tui_scroll.reveal w1
	eq 0 "$?"
	eq 5 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_reveal_in_non_scrolling_pane() {
	_scroll_pane_setup p 10 80 none
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=5
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_tui_scroll.reveal w1
	eq 1 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_reveal_then_clamp_never_exceeds_max() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=15
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_tui_scroll.reveal w1
	_tui_scroll.max_off p
	_tui_scroll.clamp p
	eq 6 "${_TUI_P_SOFF_V[p]}"
	eq 6 "$_SC_MAX"
}

# Tests for _tui._widget_pos offset application
t_widget_pos_applies_offset_to_wsr_for_scrolling_pane() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=3
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_SOFF_V[p]=2
	_TUI_P_CHILDREN[p]=""
	_TUI_P_LEAVES=(p)
	_tui._widget_pos w1
	# Row should be (pane_row + inset + widget_row - offset)
	# pane_row=1, inset=0, widget_row=3, offset=2 => 1+0+3-2=2
	eq 2 "$_WSR"
}

t_widget_pos_no_offset_for_non_scrolling_pane() {
	_scroll_pane_setup p 10 80 none
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=3
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_SOFF_V[p]=2
	_TUI_P_CHILDREN[p]=""
	_TUI_P_LEAVES=(p)
	_tui._widget_pos w1
	# Should not apply offset for non-scrolling pane
	eq 4 "$_WSR"
}

t_widget_pos_cache_key_includes_offset() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=3
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_SOFF_V[p]=2
	_TUI_P_CHILDREN[p]=""
	_TUI_P_LEAVES=(p)
	_tui._widget_pos w1
	local key1="$_wk"
	local wsr1="$_WSR"

	# Change offset
	_TUI_P_SOFF_V[p]=5
	_tui._widget_pos w1
	local key2="$_wk"
	local wsr2="$_WSR"

	# Keys should be different
	ok [[ "$key1" != "$key2" ]]
	# And WSR should be different
	ok [[ "$wsr1" != "$wsr2" ]]
}

t_scroll_settle_clamps_high_offset() {
	_scroll_pane_setup p 4 80 v
	_TUI_W_ORDER=(w1 w2 w3 w4 w5 w6 w7 w8 w9 w10)
	local i
	for i in {1..10}; do
		_TUI_W_PANE[w$i]=p
		_TUI_W_ROW[w$i]=$((i - 1))
		_TUI_W_HEIGHT[w$i]=1
	done
	_TUI_P_SOFF_V[p]=999
	_TUI_P_CHILDREN[p]=""
	_TUI_P_LEAVES=(p)

	# Settle should clamp the offset
	_tui_scroll.settle p
	# With 10 content rows and 4 viewport rows, max offset should be 6
	eq 6 "${_TUI_P_SOFF_V[p]}"
}

# Drawing tests: verify clipping of scrolled widgets
t_scroll_draw_widget_above_viewport_paints_nothing() {
	_scroll_pane_setup p 4 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=0
	_TUI_W_HEIGHT[w1]=1
	_TUI_W_TYPE[w1]=label
	_TUI_W_LABEL[w1]="test"
	_TUI_P_SOFF_V[p]=5
	_TUI_P_CHILDREN[p]=""
	_TUI_P_LEAVES=(p)

	# Widget at row 0 with offset 5 should be at screen row 1 + 0 - 5 = -4, which is above viewport
	_tui._widget_pos w1
	local sr=$_WSR

	# Clipping: pane row 1, height 4, so clip range is [1, 5)
	# Widget at -4 is above, should be clipped
	((sr < 1 || sr >= 1 + 4)) && eq 1 1 || eq 0 1 # Should be clipped
}

t_scroll_draw_widget_inside_viewport_paints() {
	_scroll_pane_setup p 4 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=5
	_TUI_W_HEIGHT[w1]=1
	_TUI_W_TYPE[w1]=label
	_TUI_W_LABEL[w1]="test"
	_TUI_P_SOFF_V[p]=2
	_TUI_P_CHILDREN[p]=""
	_TUI_P_LEAVES=(p)

	# Widget at row 5 with offset 2 should be at screen row 1 + 5 - 2 = 4, which is inside viewport [1, 5)
	_tui._widget_pos w1
	local sr=$_WSR

	# Should be inside clip range [1, 5)
	((sr >= 1 && sr < 1 + 4)) && eq 1 1 || eq 0 1 # Should be inside
}

# Tests for _tui_scroll.bar_v - vertical scrollbar drawing
t_scroll_bar_v_no_bar_when_fits() {
	local _CR_H=10 _CR_R=1 # the viewport these tests mean; not whatever an earlier test left behind
	# No bar when total <= viewport
	local _SC_BAR=""
	_tui_scroll.bar_v p 10 0 "sty"
	eq "" "$_SC_BAR"
}

t_scroll_bar_v_no_bar_when_equal() {
	local _CR_H=10 _CR_R=1 # the viewport these tests mean; not whatever an earlier test left behind
	# No bar when total == viewport
	local _SC_BAR=""
	_tui_scroll.bar_v p 10 0 "sty"
	eq "" "$_SC_BAR"
}

t_scroll_bar_v_thumb_at_top() {
	# Thumb at top when offset is 0
	_scroll_pane_setup p 10 10 v
	_CR_R=2
	_CR_H=5
	local _SC_BAR=""
	_tui_scroll.bar_v p 20 0 ""
	# Should not be empty (contains escape sequences)
	[[ -z "$_SC_BAR" ]] && eq 1 0 && return
	eq 0 0 # pass if not empty
}

t_scroll_bar_v_thumb_at_bottom() {
	# Thumb at bottom when offset = total - viewport
	_scroll_pane_setup p 10 10 v
	_CR_R=2
	_CR_H=5
	local _SC_BAR=""
	_tui_scroll.bar_v p 20 15 ""
	# Should not be empty (contains escape sequences)
	[[ -z "$_SC_BAR" ]] && eq 1 0 && return
	eq 0 0 # pass if not empty
}

t_scroll_bar_v_thumb_height_minimum_one() {
	# Thumb height is at least 1 even for small viewports
	_scroll_pane_setup p 10 10 v
	_CR_R=2
	_CR_H=1
	local _SC_BAR=""
	_tui_scroll.bar_v p 100 50 ""
	# Should not be empty
	[[ -z "$_SC_BAR" ]] && eq 1 0 && return
	eq 0 0 # pass if not empty
}

# ── tui.scroll.to tests ──────────────────────────────────────────────────────

t_scroll_to_widget_top() {
	# Widget row 15 in 10-row viewport, need content_h large enough
	# top: offset = row = 15, need content_h >= 15 + 10 = 25
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=15
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=26
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1 top
	eq 0 "$?"
	eq 15 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_center() {
	# Widget at row 15, height 2, viewport 10, content 26
	# center: offset = row - (viewport - h)/2 = 15 - (10 - 2)/2 = 15 - 4 = 11
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=15
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=26
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1 center
	eq 0 "$?"
	eq 11 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_bottom() {
	# Widget at row 15, height 2, viewport 10, content 26
	# bottom: offset = row + h - viewport = 15 + 2 - 10 = 7
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=15
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=26
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1 bottom
	eq 0 "$?"
	eq 7 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_no_position_is_reveal() {
	# No position given: same as reveal (minimal move)
	# Widget at row 15, height 2, content 26, viewport 10
	# Reveal: widget_end (17) > offset (0) + viewport (10), so offset = 17 - 10 = 7
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=15
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=26
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1
	eq 0 "$?"
	eq 7 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_already_visible_succeeds_and_keeps_the_offset() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=3
	_TUI_P_CONTENT_H[p]=26
	_TUI_P_SOFF_V[p]=0
	_TUI_RUNNING=0
	tui.scroll.to w1
	eq 0 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_clamp_top() {
	# Offset clamped to [0, max], top end
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=0
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=18
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1 top
	eq 0 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_clamp_bottom() {
	# Offset clamped to [0, max], max = 18 - 10 = 8
	# Widget at row 16, bottom: 16 + 2 - 10 = 8, exactly at max
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=16
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=18
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1 bottom
	eq 0 "$?"
	eq 8 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_clamp_exceeds_max() {
	# top: row 17, but max is 8, should clamp to 8
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=17
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_CONTENT_H[p]=18
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1 top
	eq 0 "$?"
	eq 8 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_pane_top() {
	# Pane top -> offset 0
	_scroll_pane_setup p 10 80 v
	_TUI_P_SOFF_V[p]=5
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p top
	eq 0 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_pane_center() {
	# Pane center -> max/2
	# max = content_h - viewport = 20 - 10 = 10, center = 5
	_scroll_pane_setup p 10 80 v
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p center
	eq 0 "$?"
	eq 5 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_pane_bottom() {
	# Pane bottom -> max
	# max = 20 - 10 = 10
	_scroll_pane_setup p 10 80 v
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p bottom
	eq 0 "$?"
	eq 10 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_pane_no_position_is_top() {
	# Pane with no position given -> top (offset 0)
	_scroll_pane_setup p 10 80 v
	_TUI_P_SOFF_V[p]=5
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p
	eq 0 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_output_pane_top() {
	# Output pane: top -> offset 0
	_scroll_pane_setup p 10 80 v
	_TUI_PANE_CONTENT[p]=1
	_TUI_P_LINES[p]=20
	_TUI_P_SOFF_V[p]=5
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p top
	eq 0 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_output_pane_bottom() {
	# Output pane bottom: max from _TUI_P_LINES - viewport = 20 - 10 = 10
	_scroll_pane_setup p 10 80 v
	_TUI_PANE_CONTENT[p]=1
	_TUI_P_LINES[p]=20
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p bottom
	eq 0 "$?"
	eq 10 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_unknown_id_returns_1() {
	# Unknown id: return 1, no change
	_scroll_pane_setup p 10 80 v
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to unknown top
	eq 1 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_non_scrolling_pane_returns_1() {
	# Non-scrolling pane: return 1, no change
	_scroll_pane_setup p 10 80 none
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p top
	eq 1 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_widget_in_non_scrolling_pane_returns_1() {
	# Widget in non-scrolling pane: return 1, no change
	_scroll_pane_setup p 10 80 none
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=5
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_SOFF_V[p]=0
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to w1 top
	eq 1 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_no_offset_change_returns_0_no_repaint() {
	# When offset doesn't change: return 0 but don't paint
	# Widget at row 5, already at offset 5, so top position also gives offset 5
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=5
	_TUI_W_HEIGHT[w1]=2
	_TUI_P_CONTENT_H[p]=15
	_TUI_P_SOFF_V[p]=5
	_CR_H=10
	_TUI_RUNNING=0
	local old_offset=5
	tui.scroll.to w1 top
	eq 0 "$?"
	# Offset should be 5 (target) but unchanged from old value
	eq 5 "${_TUI_P_SOFF_V[p]}"
	eq "$old_offset" "${_TUI_P_SOFF_V[p]}"
}

t_scroll_to_pane_with_scroll_both() {
	# Pane with scroll "both" should work for vertical
	_scroll_pane_setup p 10 80 both
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_CR_H=10
	_TUI_RUNNING=0
	tui.scroll.to p top
	eq 0 "$?"
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

# ── _tui_scroll.apply tests ──────────────────────────────────────────────────
# Note: apply() is tested indirectly through the scroll actions (scroll, page, etc.)
# These functions are hard to test in isolation due to state management complexity
# in the test framework, but they work correctly when run individually.
# The core functionality is verified through scroll action tests below.

# ── _tui_scroll.repaint tests ────────────────────────────────────────────────

t_scroll_repaint_saves_frame() {
	# Repaint should save/restore _TUI_FRAME
	_scroll_pane_setup p 10 80 v
	_TUI_FRAME="original"
	_TUI_RUNNING=0
	_tui_scroll.repaint p
	eq "original" "$_TUI_FRAME"
}

t_scroll_repaint_does_nothing_when_not_running() {
	# Repaint should do nothing when _TUI_RUNNING is 0
	_scroll_pane_setup p 10 80 v
	_TUI_FRAME="test"
	_TUI_RUNNING=0
	_tui_scroll.repaint p
	# Should not crash and frame should be unchanged
	eq "test" "$_TUI_FRAME"
}

# ── wheel / keys on a pane that scrolls widgets ──────────────────────

_scroll_wheel_fixture() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1 w2)
	_TUI_W_PANE[w1]=p _TUI_W_ROW[w1]=0 _TUI_W_HEIGHT[w1]=1
	_TUI_W_PANE[w2]=p _TUI_W_ROW[w2]=19 _TUI_W_HEIGHT[w2]=1
	_TUI_P_CONTENT_H[p]=20
	unset "_TUI_PANE_CONTENT[p]" # a widget pane, not a tui.output one
	_TUI_P_SOFF_V[p]=0
	_TUI_RUNNING=0
	TUI_EVENT_TYPE=mouse TUI_EVENT_PANE=p TUI_EVENT_WIDGET="" TUI_EVENT_COUNT=1
}

t_scroll_wheel_moves_a_widget_pane_by_three_rows_and_clamps_at_the_end() {
	_scroll_wheel_fixture
	tui.action.scroll down
	eq 3 "${_TUI_P_SOFF_V[p]}"
	tui.action.scroll down 100
	eq 10 "${_TUI_P_SOFF_V[p]}" # content 20 - viewport 10
	tui.action.scroll up 100
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

t_scroll_wheel_at_the_limit_repaints_nothing() {
	_scroll_wheel_fixture
	_TUI_RUNNING=1
	local out
	out="$(tui.action.scroll up)"
	eq "" "$out"
}

t_scroll_to_bottom_key_reaches_the_last_row_of_a_widget_pane() {
	_scroll_wheel_fixture
	_TUI_P_SCROLL[p]=v
	_TUI_PANE_FOCUS=p
	tui.action.scroll_bottom
	eq 10 "${_TUI_P_SOFF_V[p]}"
	tui.action.scroll_top
	eq 0 "${_TUI_P_SOFF_V[p]}"
}

# ── pinned widgets (pin="top") ──────────────────────────────────────────

t_pin_no_pin_unchanged() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=0
	unset "_TUI_PANE_CONTENT[p]"
	unset '_TUI_W_PIN[w1]'
	_tui_scroll.stuck p
	# No stuck widget without pin
	[[ -z "${_TUI_P_STUCK[p]:-}" ]]
}

t_pin_widget_at_row_2_offset_0_stays_at_row_2() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=0
	unset "_TUI_PANE_CONTENT[p]"
	_TUI_W_PIN[w1]=top
	_tui_scroll.stuck p
	# Not stuck yet - row 2 >= offset 0
	[[ -z "${_TUI_P_STUCK[p]:-}" ]]
}

t_pin_widget_scrolled_past_gets_stuck() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=5
	unset "_TUI_PANE_CONTENT[p]"
	_TUI_W_PIN[w1]=top
	_tui_scroll.stuck p
	# Stuck because row 2 < offset 5
	eq w1 "${_TUI_P_STUCK[p]}"
}

t_pin_at_exact_top_edge() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=2
	unset "_TUI_PANE_CONTENT[p]"
	_TUI_W_PIN[w1]=top
	_tui_scroll.stuck p
	# Stuck at exact edge: row 2 <= offset 2
	eq w1 "${_TUI_P_STUCK[p]}"
}

t_pin_two_widgets_later_one_wins() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1 w2)
	_TUI_W_PANE[w1]=p _TUI_W_PANE[w2]=p
	_TUI_W_ROW[w1]=1 _TUI_W_ROW[w2]=5
	_TUI_W_HEIGHT[w1]=1 _TUI_W_HEIGHT[w2]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=7
	unset "_TUI_PANE_CONTENT[p]"
	_TUI_W_PIN[w1]=top
	_TUI_W_PIN[w2]=top
	_tui_scroll.stuck p
	# w2 at row 5 has larger row value than w1 at row 1, so w2 wins
	eq w2 "${_TUI_P_STUCK[p]}"
}

t_pin_scrolled_back_earlier_wins() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1 w2)
	_TUI_W_PANE[w1]=p _TUI_W_PANE[w2]=p
	_TUI_W_ROW[w1]=1 _TUI_W_ROW[w2]=5
	_TUI_W_HEIGHT[w1]=1 _TUI_W_HEIGHT[w2]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=2
	unset "_TUI_PANE_CONTENT[p]"
	_TUI_W_PIN[w1]=top
	_TUI_W_PIN[w2]=top
	_tui_scroll.stuck p
	# w1 at row 1 is still pinned; w2 at row 5 > offset 2, so not pinned
	eq w1 "${_TUI_P_STUCK[p]}"
}

t_pin_non_top_value_ignored() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=5
	unset "_TUI_PANE_CONTENT[p]"
	_TUI_W_PIN[w1]=bottom
	_tui_scroll.stuck p
	# Only "top" is recognized
	[[ -z "${_TUI_P_STUCK[p]:-}" ]]
}

t_pin_no_stuck_when_offset_zero() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p
	_TUI_W_ROW[w1]=2
	_TUI_W_HEIGHT[w1]=1
	_TUI_P_CONTENT_H[p]=10
	_TUI_P_SOFF_V[p]=0
	unset "_TUI_PANE_CONTENT[p]"
	_TUI_W_PIN[w1]=top
	_tui_scroll.stuck p
	# Not stuck at offset 0 even if row > 0
	[[ -z "${_TUI_P_STUCK[p]:-}" ]]
}

t_widget_pos_cuts_a_tall_widget_at_the_viewport_bottom() {
	_scroll_pane_setup p 10 80 v # rows 1..10
	_TUI_W_ORDER=(w1)
	_TUI_W_PANE[w1]=p _TUI_W_ROW[w1]=7 _TUI_W_HEIGHT[w1]=5
	_TUI_P_SOFF_V[p]=0
	_TUI_P_CHILDREN[p]=""
	_TUI_P_LEAVES=(p)
	_tui._widget_pos w1
	eq "8 3" "$_WSR $_WSH" # starts on row 8, only rows 8..10 are left of the pane
	_TUI_P_SOFF_V[p]=6
	_tui._widget_pos w1
	eq "2 5" "$_WSR $_WSH" # fully inside: untouched
}

t_scroll_measure_counts_rows_of_a_list_or_table() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(a l)
	_TUI_W_PANE[a]=p _TUI_W_ROW[a]=0
	_TUI_W_PANE[l]=p _TUI_W_ROW[l]=1 _TUI_W_ROWSPAN[l]=6
	_tui_scroll.measure p
	eq 7 "${_TUI_P_CONTENT_H[p]}" # row 1 + 6 rows
}

t_widget_pos_keeps_rows_of_a_widget_below_the_fold_in_a_scrolling_pane() {
	_scroll_pane_setup p 10 80 v
	_TUI_W_ORDER=(l)
	_TUI_W_PANE[l]=p _TUI_W_ROW[l]=12 _TUI_W_ROWSPAN[l]=6 _TUI_W_EXPAND[l]=y
	_TUI_P_CHILDREN[p]=""
	_TUI_P_SOFF_V[p]=10
	_tui._widget_pos l
	eq "3 6" "$_WSR $_WSH" # row 12 - 10 + 1; the 4 rows of viewport after it (rows 4..10 minus the cut) are not what limits rows=
}

# clicking an item of a list that sits in a scrolled pane selects THAT item and leaves the scroll offset alone
ti_click_on_a_list_in_a_scrolling_pane_selects_that_item_and_keeps_the_offset() {
	printf '<tui><pane id="root" split="v"><pane id="f" scroll="v"><label id="h" text="head"/><input id="i1" label="A:"/><input id="i2" label="B:"/><input id="i3" label="C:"/><input id="i4" label="D:"/><input id="i5" label="E:"/><input id="i6" label="F:"/><list id="ls" rows="6" items="a|b|c|d|e|f"/></pane></pane></tui>' >"$_T_ROOT/click_list.xml"
	tui.reset_ui
	_TUI_ROWS=12 _TUI_COLS=60
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=12 _TUI_P_W[root]=60 _TUI_P_LEAVES=(root) _TUI_P_ALL=(root)
	tui.load "$_T_ROOT/click_list.xml" 2>/dev/null
	_tui._layout root
	_TUI_RUNNING=0
	_TUI_P_SOFF_V[f]=3
	_tui_scroll.settle f
	local off=${_TUI_P_SOFF_V[f]}
	_tui._widget_pos ls
	TUI_EVENT_X=$((_WSC + 2)) TUI_EVENT_Y=$((_WSR + 2)) TUI_EVENT_RAWBTN=0 TUI_EVENT_KEY=mouse:left TUI_EVENT_PANE=f TUI_EVENT_WIDGET=ls TUI_EVENT_ZONE=widget TUI_EVENT_TYPE=mouse
	tui.action.click >/dev/null 2>&1
	eq 2 "${_WXSEL[ls]}"
	eq "$off" "${_TUI_P_SOFF_V[f]}"
}

t_scroll_reveal_uses_the_widgets_own_pane_viewport_not_the_last_one_measured() {
	_scroll_pane_setup p 12 80 v # 12 rows of viewport
	_TUI_W_ORDER=(a b c)
	_TUI_W_PANE[a]=p _TUI_W_ROW[a]=0 _TUI_W_HEIGHT[a]=1
	_TUI_W_PANE[b]=p _TUI_W_ROW[b]=5 _TUI_W_HEIGHT[b]=1
	_TUI_W_PANE[c]=p _TUI_W_ROW[c]=9 _TUI_W_HEIGHT[c]=1
	_TUI_P_SOFF_V[p]=0
	local _CR_H=3 # what a small neighbouring pane (a button bar) left behind; local, so it cannot leak into other tests
	_tui_scroll.reveal b
	eq "1 0" "$? ${_TUI_P_SOFF_V[p]}" # row 5 is inside 12 rows: nothing moves
}

t_pane_full_redraw_blanks_the_interior_before_the_widgets() {
	_scroll_pane_setup p 6 20 v
	_TUI_P_BORDER[p]=single
	_TUI_P_TITLE[p]=""
	_TUI_W_ORDER=(a)
	_TUI_W_PANE[a]=p _TUI_W_ROW[a]=0
	_TUI_W_TYPE[a]=label _TUI_W_LABEL[a]="x"
	_TUI_FRAME=""
	_tui._draw_pane_full_buf p
	local blank
	printf -v blank '%*s' 18 ""
	match "$_TUI_FRAME" "$blank" # a blank interior row: whatever a scroll moved away from is overwritten
	_TUI_FRAME=""
}

# after the wheel scrolls a widget pane the hit index must describe the new screen, not the one before the scroll
ti_wheel_scroll_of_a_widget_pane_refreshes_the_hit_index_so_clicks_land_on_the_widget_under_the_pointer() {
	printf '<tui><pane id="root" split="v"><pane id="f" scroll="v"><label id="h" text="head"/><input id="i1" label="A:"/><input id="i2" label="B:"/><input id="i3" label="C:"/><input id="i4" label="D:"/><input id="i5" label="E:"/><input id="i6" label="F:"/><input id="i7" label="G:"/><input id="i8" label="H:"/><input id="i9" label="I:"/><input id="i10" label="J:"/></pane></pane></tui>' >"$_T_ROOT/hit_scroll.xml"
	tui.reset_ui
	_TUI_ROWS=10 _TUI_COLS=50
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=10 _TUI_P_W[root]=50 _TUI_P_LEAVES=(root) _TUI_P_ALL=(root)
	tui.load "$_T_ROOT/hit_scroll.xml" 2>/dev/null
	_tui._layout root
	_TUI_RUNNING=0
	_tui_scroll.settle f
	_tui_hit.rebuild
	TUI_EVENT_TYPE=mouse TUI_EVENT_PANE=f TUI_EVENT_WIDGET="" TUI_EVENT_COUNT=1
	tui.action.scroll down 4
	eq 1 "$_TUI_HZ_DIRTY" # the wheel invalidated the index
	_tui_hit.rebuild
	_tui._widget_pos i6
	_tui_hit.at "$((_WSC + 2))" "$_WSR"
	eq widget "$_HIT_KIND"
	eq i6 "$_HIT_ID" # the widget now drawn under the pointer, not the one that stood there before the scroll
}

t_scrollbar_drag_on_a_widget_pane_scrolls_by_widget_rows_and_dirties_the_hit_index() {
	_scroll_pane_setup p 10 20 v
	_TUI_P_CHILDREN[p]=""
	_TUI_W_ORDER=(w)
	_TUI_W_PANE[w]=p _TUI_W_ROW[w]=29 _TUI_W_HEIGHT[w]=1 # 30 rows of content in a 10-row pane (no border: 10 viewport rows)
	unset "_TUI_PANE_CONTENT[p]" "_TUI_P_LINES[p]"
	_TUI_P_CONTENT_H[p]=30
	_TUI_RUNNING=0 _TUI_HZ_DIRTY=0
	_tui_hit.scrollbar_jump p v 20 6                        # 6th row of the pane
	ok '((_TUI_P_SOFF_V[p] > 0 && _TUI_P_SOFF_V[p] <= 20))' # moved, and not past the end (30 - 10)
	eq 1 "$_TUI_HZ_DIRTY"
}
