#!/usr/bin/env bash

on_load_scroll_data() {
	# 1. Populate Vertical Data
	local v_data=""
	for i in {1..100}; do
		v_data+="Line $i - Vertical scrolling demo"$'\n'
	done
	tui.output "scroll_v" "$v_data"

	# 2. Populate Horizontal Data
	local h_data="This is a very long line to demonstrate horizontal scrolling. "
	for i in {1..10}; do
		h_data+="It just keeps going and going and going... "
	done
	tui.output "scroll_h" "$h_data"

	# 3. Populate Both Axes
	local b_data=""
	for i in {1..100}; do
		b_data+="Line $i - ${h_data}"$'\n'
	done
	tui.output "scroll_b" "$b_data"

	tui.update "btn_load" "[ Data Loaded ]"
}
