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

# The form's generated rows are a <for id="gen_groups"> in scrolling.xml: one group is 10 widgets, ~19 lines. The markup
# holds the floor (SCROLL_GROUPS_DEFAULT, kept equal to its count); an addon raises the count to cover 4 x the terminal
# height, so the pane scrolls on any terminal.
SCROLL_LINES_PER_GROUP=19
SCROLL_GROUPS_DEFAULT=2

# scroll_write_rows ROWS - writes the addon for a ROWS-tall terminal when it needs more groups than the file holds (or
# than the default, with no file). rc 0 = the file changed, so a page built before it is stale; rc 1 = nothing to do.
# Needs no running app: the launcher calls it before the first load, so the page is built once, at its final size.
scroll_write_rows() {
	local need addon="${TUI_APP_CONF:-}/addons/scroll_rows.xml" cur="" have=$SCROLL_GROUPS_DEFAULT xml
	[[ -n "${TUI_APP_CONF:-}" ]] || return 1
	need=$((($1 * 4 + SCROLL_LINES_PER_GROUP - 1) / SCROLL_LINES_PER_GROUP))
	[[ -r "$addon" ]] && { IFS= read -r -d "" cur <"$addon" || true; }
	[[ "$cur" =~ value=\"([0-9]+)\" ]] && have=$((BASH_REMATCH[1] > have ? BASH_REMATCH[1] : have))
	((need > have)) || return 1
	printf -v xml '<addon id="scroll_rows" target="scrolling.xml" prefix="false">\n  <set ref="#gen_groups" attr="count" value="%d"/>\n</addon>\n' "$need"
	mkdir -p "${addon%/*}"
	printf '%s' "$xml" >"$addon"
}
# scroll_fit_rows - on_visit: a terminal taller than the addon covers rebuilds the pane once
scroll_fit_rows() {
	local rows cols
	read -r rows cols < <(tui.get.terminal)
	scroll_write_rows "$rows" && tui.page.refresh
	return 0
}
noop() { :; }
# tui.scroll.to takes a widget or a pane id and a position
on_scroll_top() { tui.scroll.to scroll_form top; }
on_scroll_bottom() { tui.scroll.to scroll_form bottom; }
on_scroll_list() { tui.scroll.to sf_list center; }
