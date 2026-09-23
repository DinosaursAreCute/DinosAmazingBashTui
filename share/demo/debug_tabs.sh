#!/usr/bin/env bash
# debug_tabs.sh - tab actions shared by the two Debug pages. Kept separate from
# debug_callbacks.sh, whose top-level code builds the Events page's grid and hooks
# input to its tape pane - sourcing that on the keyboard page drew stray text.
dbg_tab_here() { :; }
dbg_goto_input() { tui.goto "debug_input.xml"; }
dbg_goto_events() { tui.goto "debug.xml"; }
dbg_goto_lab() { tui.goto "debug_lab.xml"; }
