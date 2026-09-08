#!/usr/bin/env bash
# markup_demo.sh — launches config/home.xml through the file-based TUI loader.
source "$(dirname "$0")/tui.sh"

tui.start "$(dirname "$0")/../config/home.xml"
