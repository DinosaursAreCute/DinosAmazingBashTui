#!/usr/bin/env bash
# demo_callbacks.sh - callbacks shared by the config/*.xml demo pages.
# Sourced by tui.load via <script src="…"/>; tui.sh is already loaded by then.

on_theme_apply() {
	local theme font notif dark
	theme=$(tui.get "inp_theme")
	font=$(tui.get "inp_font")
	notif=$(tui.get "chk_notifications")
	dark=$(tui.get "chk_darkmode")

	tui.update "out1" "Theme: ${theme:-<empty>}"
	tui.update "out2" "Font:  ${font:-<empty>}"
	tui.update "out3" "Notifications: $([[ "$notif" == "1" ]] && echo on || echo off)   Dark mode: $([[ "$dark" == "1" ]] && echo on || echo off)"
	tui.update "out4" "✔ Applied!"
}

on_reset() {
	tui.set "inp_theme" ""
	tui.set "inp_font" ""
	tui.update "chk_notifications" "0"
	tui.update "chk_darkmode" "0"
	tui.update "out1" ""
	tui.update "out2" ""
	tui.update "out3" ""
	tui.update "out4" ""
}

# No-op action for widgets that only exist to showcase styling/alignment.
on_noop() { :; }

on_quit() {
	tui.stop
}
