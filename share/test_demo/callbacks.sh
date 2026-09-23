#!/usr/bin/env bash
source "${SCRIPT_DIR:-.}/tui_api.sh"

# Callback functions for the test demo
on_start() {
	tui.clock "hdr" "" "1"
}

on_exit() {
	echo "Test demo exited"
}
