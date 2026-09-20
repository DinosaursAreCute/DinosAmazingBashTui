#!/usr/bin/env bash
# tasks.sh - entry script of the Tasks app ("Writing Your First App").
#   dabt app run tasks          (or:  bash tasks.sh  with DABT installed)
APP_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# `dabt app run` exports TUI_ROOT; when started by hand, find DABT through the dabt command
if [[ -z "${TUI_ROOT:-}" ]] && command -v dabt >/dev/null 2>&1; then
    _dabt="$(readlink -f "$(command -v dabt)")"; TUI_ROOT="$(cd -P "$(dirname "$_dabt")/.." && pwd -P)"
fi
# running from a DABT checkout (examples/first-app): the checkout is the framework
[[ -r "${TUI_ROOT:-}/lib/tui.sh" ]] || TUI_ROOT="$(cd -P "$APP_DIR/../.." && pwd -P)"
[[ -r "$TUI_ROOT/lib/tui.sh" ]] || { echo "tasks: DABT not found. Install it first." >&2; exit 1; }

TUI_APP_NAME="${TUI_APP_NAME:-tasks}"          # set BEFORE sourcing tui.sh: your files live in ~/.config/DABT/apps/tasks
TUI_APP_TITLE="Tasks"; TUI_APP_DESC="A tiny to-do list"; TUI_APP_ENTRY="tasks.sh"
source "$TUI_ROOT/lib/tui.sh"

tui.start "$APP_DIR/config/home.xml"
