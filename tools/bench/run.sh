#!/usr/bin/env bash
# bench/run.sh [--compare FILE] - runs the stage-0 benches against the
# current code and prints name/mean_us/p95_us/forks (see tools/bench/lib.sh).
#
#   tools/bench/run.sh                        # print current numbers
#   tools/bench/run.sh > tools/bench/baseline.txt
#   tools/bench/run.sh --compare tools/bench/baseline.txt
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=lib.sh
source "$REPO/tools/bench/lib.sh"

_BENCH_COMPARE=""
[[ "$1" == "--compare" ]] && _BENCH_COMPARE="$2"

_bench_setup_env
PAGE="$REPO/share/demo/components.xml"

_b_cold_load() { tui.load "$PAGE" >/dev/null; }
_b_warm_load() { tui.load_cached "$PAGE" >/dev/null; }
_b_full_render() { tui.render >/dev/null; }
_b_hover_redraw() {
	_TUI_HOVERED_WIDGET="$_BENCH_WID"
	_tui._draw_widgets_now "$_BENCH_WID" >/dev/null
}
_b_focus_move() {
	_TUI_FOCUS_ID="$_BENCH_WID"
	_tui._draw_pane_borders_now "$_BENCH_PANE" >/dev/null
}
_b_mouse_hit() { _tui._locate_pane "$((_TUI_COLS / 2))" "$((_TUI_ROWS / 2))"; }
_b_resize_relayout() { _tui._layout root; }
_b_scroll_burst() {
	_tui._scroll_kb down
	_tui._scroll_kb down
	_tui._scroll_kb down
	_tui._flush_pending_render >/dev/null
}

tui.load "$PAGE" >/dev/null
_tui._layout root
tui.render >/dev/null
_BENCH_WID="${_TUI_W_ORDER[0]:-}"
_BENCH_PANE="${_TUI_P_ALL[0]:-root}"

{
	_bench_run cold_page_load 10 _b_cold_load
	_bench_run warm_page_load 20 _b_warm_load
	_bench_run full_render 30 _b_full_render
	_bench_run hover_redraw 50 _b_hover_redraw
	_bench_run focus_move 50 _b_focus_move
	_bench_run mouse_hit 100 _b_mouse_hit
	_bench_run resize_relayout 30 _b_resize_relayout
	_bench_run scroll_burst 30 _b_scroll_burst
} >"$BENCH_REPO/tools/bench/.run_out.$$"

if [[ -z "$_BENCH_COMPARE" ]]; then
	cat "$BENCH_REPO/tools/bench/.run_out.$$"
	rm -f "$BENCH_REPO/tools/bench/.run_out.$$"
	exit 0
fi

_BENCH_FAIL=0
while IFS=$'\t' read -r name mean p95 forks; do
	base_mean="$(awk -F'\t' -v n="$name" '$1==n{print $2}' "$_BENCH_COMPARE")"
	[[ -z "$base_mean" ]] && continue
	# G3: no bench more than 5% slower in mean than the recorded baseline.
	limit=$((base_mean * 105 / 100))
	if ((mean > limit)); then
		printf 'G3\ttools/bench/run.sh:0\t%s: %dus mean > baseline %dus + 5%%\n' "$name" "$mean" "$base_mean"
		_BENCH_FAIL=1
	fi
done <"$BENCH_REPO/tools/bench/.run_out.$$"
rm -f "$BENCH_REPO/tools/bench/.run_out.$$"
exit "$_BENCH_FAIL"
