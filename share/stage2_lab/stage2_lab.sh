#!/usr/bin/env bash
# stage2_lab.sh - launches share/stage2_lab/, the Stage 2 (markup-v2-implementation-plan.md
# tasks 2A-2D) validation fixture. Dev-only: not a shipped command (see tools/ vs bin/ in
# CLAUDE.md), just a way to eyeball the plan's intended syntax against the real running app
# while 2A/2B/2C/2D land.
TUI_APP_NAME=stage2_lab
# shellcheck source=../lib/tui.sh
source "$(dirname "$0")/../../lib/tui.sh"

tui.start_cached "page1.xml"
