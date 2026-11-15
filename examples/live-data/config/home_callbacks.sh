#!/usr/bin/env bash
# home_callbacks.sh - the Live monitor. A timer appends samples and changes service rows; nothing here draws.

declare -gi PAUSED=0 LOAD=40

monitor_visit() {
	tui.data.append services "web|up|12" "db|up|31" "cache|up|3" "queue|up|7" # a keyed dataset: appending a known name updates it
	tui.every 1 sample
}

# sample - one second of fake data: a load that wanders, and services whose latency moves
sample() {
	((PAUSED)) && return 0
	((LOAD += RANDOM % 21 - 10))
	((LOAD < 2)) && LOAD=2
	((LOAD > 98)) && LOAD=98
	tui.data.append load "$LOAD"
	tui.data.stat load pct avg mean
	tui.set_label l_avg "average: ${mean%%.*} %"
	local name
	for name in web db cache queue; do
		tui.data.cell services "$name" ms ms
		((ms = ms + RANDOM % 7 - 3, ms < 1 ? ms = 1 : 0))
		tui.data.set services "$name" ms "$ms"
		((ms > 40)) && tui.data.set services "$name" state slow || tui.data.set services "$name" state up
	done
}

on_pause() {
	if ((PAUSED)); then
		PAUSED=0
		tui.set_label b_pause "[ Pause ]"
	else
		PAUSED=1
		tui.set_label b_pause "[ Resume ]"
	fi
}

# on_sort - the table follows the dataset, so sorting the dataset is all it takes
on_sort() { tui.data.sort services ms --num --desc; }
