#!/usr/bin/env bash
source "$(dirname "$0")/tui_markup.sh"
source "$(dirname "$0")/tui.sh"
source "$(dirname "$0")/terminal_controls.sh"
source "$(dirname "$0")/colors.sh"
tui.start "$(dirname "$0")/../config/home.xml"
