#!/usr/bin/env bash
# run.sh - launches the DABT side of the workbench benchmark app (5 pages). Spec: ../SPEC.md
TUI_APP_NAME=compare_workbench_dabt
TUI_APP_TITLE="Workbench"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../../../../lib/tui.sh
set DEBUG=1
source "$HERE/../../../../../../lib/tui.sh" 
tui.start_cached "$HERE/overview.xml"
