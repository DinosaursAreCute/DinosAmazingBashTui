#!/usr/bin/env bash
# switch_pages.sh [PAGE...] - what one page switch costs per demo page, in ms, headless (the same tui.goto path as the app, nothing
# is drawn to a terminal). Each page is switched to from Components, four round trips, after two warm-up rounds, so every switch is a
# warm one (cache replay). Prints one line: page=ms ... The mean of the two directions of a round trip.
#
#   tools/bench/switch_pages.sh                       # every page the nav lists
#   tools/bench/switch_pages.sh home workspace
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$REPO/tools/bench/lib.sh"
_bench_setup_env
D="$REPO/share/demo"
pages=("$@")
((${#pages[@]})) || pages=(home components settings monitor terminal scrolling case_study layout widgets workspace)
_TUI_RUNNING=1
for _ in 1 2; do for p in "${pages[@]}"; do tui.goto "$D/$p.xml" >/dev/null 2>&1; done; done
out=""
for p in "${pages[@]}"; do
	t0=${EPOCHREALTIME//[!0-9]/}
	for i in 1 2 3 4; do
		tui.goto "$D/components.xml" >/dev/null 2>&1
		tui.goto "$D/$p.xml" >/dev/null 2>&1
	done
	t1=${EPOCHREALTIME//[!0-9]/}
	out+="$p=$(((t1 - t0) / 8000)) "
done
echo "$out"
