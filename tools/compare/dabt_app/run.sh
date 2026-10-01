#!/usr/bin/env bash
# run.sh - launches the DABT side of the comparison (4 pages). Same file set as tools/compare/textual_app.
TUI_APP_NAME=compare_dabt
TUI_APP_TITLE="DABT comparison app"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/tui.sh
source "$HERE/../../../lib/tui.sh"
tui.start_cached "$HERE/buttons.xml"
