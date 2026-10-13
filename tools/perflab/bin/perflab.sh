#!/usr/bin/env bash
# perflab.sh - the fixture app of the profiler's perflab scenario file (tools/profiler/scenarios/perflab.py).
# It starts on a page with one button; the profiler's steps press it, and the button opens the page named by
# PERFLAB_PAGE, sized by PERFLAB_N / PERFLAB_COLS. Nothing here changes with the demo: the pages are frozen on purpose.
TUI_APP_NAME=perflab
TUI_APP_TITLE="DABT perflab"
TUI_APP_DESC="Fixture app for the framework's performance scenarios"
# shellcheck source=../../../lib/tui.sh
source "$(dirname "$0")/../../../lib/tui.sh"

PERFLAB_PAGES="$(cd "$(dirname "$0")/../pages" && pwd)"
export PERFLAB_PAGES
tui.start_cached "$PERFLAB_PAGES/start.xml"
