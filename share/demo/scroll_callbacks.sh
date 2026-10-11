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
}
noop() { :; }
# tui.scroll.to takes a widget or a pane id and a position
on_scroll_top() { tui.scroll.to scroll_form top; }
on_scroll_bottom() { tui.scroll.to scroll_form bottom; }
on_scroll_list() { tui.scroll.to sf_list center; }
