#!/usr/bin/env bash
# monitor.sh - entry script of the Live monitor ("A live dashboard" tutorial).
#   dabt app run monitor          (or:  bash monitor.sh  with DABT installed)
APP_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -z "${TUI_ROOT:-}" ]] && command -v dabt >/dev/null 2>&1; then
	_dabt="$(readlink -f "$(command -v dabt)")"
	TUI_ROOT="$(cd -P "$(dirname "$_dabt")/.." && pwd -P)"
fi
[[ -r "${TUI_ROOT:-}/lib/tui.sh" ]] || TUI_ROOT="$(cd -P "$APP_DIR/../.." && pwd -P)"
[[ -r "$TUI_ROOT/lib/tui.sh" ]] || {
	echo "monitor: DABT not found. Install it first." >&2
	exit 1
}

TUI_APP_NAME="${TUI_APP_NAME:-monitor}"
TUI_APP_TITLE="Live monitor"
TUI_APP_DESC="Datasets, bound widgets and charts"
TUI_APP_ENTRY="monitor.sh"
source "$TUI_ROOT/lib/tui.sh"

tui.start_cached "$APP_DIR/config/home.xml"
