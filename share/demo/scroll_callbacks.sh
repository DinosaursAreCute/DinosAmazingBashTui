#!/usr/bin/env bash

on_load_scroll_data() {
	# the two tui.output viewports: vertical, and both axes
	local v_data="" h_data="This is a very long line to demonstrate horizontal scrolling. " i
	for i in {1..100}; do
		v_data+="Line $i - Vertical scrolling demo"$'\n'
	done
	tui.output "scroll_v" "$v_data"

	for i in {1..10}; do
		h_data+="It just keeps going and going and going... "
	done
	local b_data=""
	for i in {1..100}; do
		b_data+="Line $i - ${h_data}"$'\n'
	done
	tui.output "scroll_b" "$b_data"
	scroll_fit_rows
}

# The form's generated rows are a <for id="gen_groups"> in scrolling.xml: one group is 10 widgets, ~19 lines. The default
# of 12 groups is ~240 lines, over 4 x a 45-row terminal. On a taller terminal an addon raises the count to cover 4 x the
# terminal height; refresh rebuilds the pane.
SCROLL_LINES_PER_GROUP=19
SCROLL_GROUPS_DEFAULT=12
: "${SCROLL_GROUPS_SET:=$SCROLL_GROUPS_DEFAULT}" # the file is sourced on every page load
scroll_fit_rows() {
	local rows cols need addon="${TUI_APP_CONF:-}/addons/scroll_rows.xml"
	[[ -n "${TUI_APP_CONF:-}" ]] || return 0
	read -r rows cols < <(tui.get.terminal)
	need=$(((rows * 4 + SCROLL_LINES_PER_GROUP - 1) / SCROLL_LINES_PER_GROUP))
	((need > SCROLL_GROUPS_SET)) || return 0
	mkdir -p "${addon%/*}"
	printf '<addon id="scroll_rows" target="scrolling.xml" prefix="false">\n  <set ref="#gen_groups" attr="count" value="%d"/>\n</addon>\n' "$need" >"$addon"
	SCROLL_GROUPS_SET=$need
	tui.page.refresh
}
noop() { :; }
# tui.scroll.to takes a widget or a pane id and a position
on_scroll_top() { tui.scroll.to scroll_form top; }
on_scroll_bottom() { tui.scroll.to scroll_form bottom; }
on_scroll_list() { tui.scroll.to sf_list center; }
