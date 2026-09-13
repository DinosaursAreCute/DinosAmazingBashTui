#!/usr/bin/env bash
# terminal_init.sh — auto-starts a live interactive shell when the Terminal page loads.
# Sourced by tui.load via <script src="…"/>, after the panes it targets already exist.
tui.exec "bash" "term_output" "term_actions"
