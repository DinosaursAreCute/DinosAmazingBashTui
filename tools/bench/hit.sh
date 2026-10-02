#!/usr/bin/env bash
# bench/hit.sh - the mouse-hit lookup cost depends on the zones crossing the pointer's row, not on the page's widget total (plan task 2C).
#
#   tools/bench/hit.sh            prints  name<TAB>mean_us<TAB>p95_us<TAB>forks  for 10 and 500 widgets,
#                                 then a verdict line and exit 1 if the 500-widget mean exceeds 2x the 10-widget mean
#
# One widget per row, the pointer on the middle one; the index is rebuilt once per size (timed separately).
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=lib.sh
source "$REPO/tools/bench/lib.sh"

_bench_setup_env
_TUI_ROWS=600
_TUI_P_H[root]=$_TUI_ROWS
_TUI_P_BORDER[root]=none

_hb_mid_row=1
_hb_fill() { # N
	local i
	_TUI_W_ORDER=() _TUI_W_TYPE=() _TUI_W_PANE=() _TUI_W_ROW=()
	for ((i = 0; i < $1; i++)); do tui.button "hb$i" root "$i" "Go" ""; done
	_hb_mid_row=$((1 + $1 / 2))
	_tui_hit.rebuild
}
_b_hit_at() { _tui_hit.at 3 "$_hb_mid_row"; }
_b_hit_rebuild() { _tui_hit.rebuild; }

declare -A res=()
for n in 10 500; do
	_hb_fill "$n"
	line="$(_bench_run "mouse_hit_${n}_widgets" 300 _b_hit_at)"
	printf '%s\n' "$line"
	line="${line#*$'\t'}"
	res[$n]="${line%%$'\t'*}"
	_bench_run "hit_rebuild_${n}_widgets" 10 _b_hit_rebuild
done
if ((res[500] > 2 * res[10] + 20)); then
	printf 'FAIL\tmouse_hit grows with widget count: %s us (10) vs %s us (500)\n' "${res[10]}" "${res[500]}"
	exit 1
fi
printf 'PASS\tmouse_hit flat: %s us (10) vs %s us (500)\n' "${res[10]}" "${res[500]}"
