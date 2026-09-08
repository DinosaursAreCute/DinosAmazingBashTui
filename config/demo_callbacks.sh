#!/usr/bin/env bash
# demo_callbacks.sh — callbacks shared by the config/*.xml demo pages.
# Sourced by tui.load via <script src="…"/>; tui.sh is already loaded by then.

on_theme_apply() {
    local theme font
    theme=$(tui.get "inp_theme")
    font=$(tui.get "inp_font")

    tui.update "out1" "Theme: ${theme:-<empty>}"
    tui.update "out2" "Font:  ${font:-<empty>}"
    tui.update "out3" "✔ Applied!"
}

on_reset() {
    tui.set "inp_theme" ""
    tui.set "inp_font" ""
    tui.update "out1" ""
    tui.update "out2" ""
    tui.update "out3" ""
}

# No-op action for widgets that only exist to showcase styling/alignment.
on_noop() { :; }

on_quit() {
    tui.stop
}

