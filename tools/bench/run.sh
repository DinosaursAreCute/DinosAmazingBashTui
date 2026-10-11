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
_b_mouse_hit() { _tui_hit.at "$((_TUI_COLS / 2))" "$((_TUI_ROWS / 2))"; }
_b_resize_relayout() { _tui._layout root; }
_b_scroll_burst() {
	_tui._scroll_kb down
	_tui._scroll_kb down
	_tui._scroll_kb down
	_tui._flush_pending_render >/dev/null
}
# v2 benches: a fused, resizable, collapsible page (the Workspace demo) and a 30-widget keep_state page.
# _BENCH_FLIP alternates the sign so a drag step never hits the clamp.
WS_PAGE="$REPO/share/demo/workspace.xml"
_BENCH_FLIP=1
_b_resize_drag_step() {
	((_BENCH_FLIP = -_BENCH_FLIP))
	tui.resize logs 0 "$_BENCH_FLIP"
}
_b_collapse_toggle() {
	tui.collapse services on
	tui.collapse services off
}
_b_hit_with_handles() { _tui_hit.at "$_BENCH_HX" "$_BENCH_HY"; }
_b_hover_zone_move() {
	_tui_hit.at "$_BENCH_HX" "$_BENCH_HY"
	_tui_hit.hover >/dev/null
	_tui_hit.at "$_BENCH_MX" "$_BENCH_MY"
	_tui_hit.hover >/dev/null
}
# one iteration = two page switches (a -> b -> a). The shell pair shares one chrome; the plain pair builds it per page.
_b_goto_pair() {
	tui.goto "$_BENCH_PA" >/dev/null
	tui.goto "$_BENCH_PB" >/dev/null
}
# _bench_goto_pages DIR - the chrome (header with 8 buttons, nav of 12 buttons, footer) and two 20-widget pages, as a shell
# pair (s_a, s_b) and as plain pages (p_a, p_b)
_bench_goto_pages() {
	local d="$1" i name chrome="" body
	for ((i = 0; i < 8; i++)); do chrome+="<button id=\"h$i\" text=\"head $i\"/>"; done
	for ((i = 0; i < 12; i++)); do chrome+="<button id=\"n$i\" text=\"nav $i\"/>"; done
	for name in a b; do
		body=""
		for ((i = 0; i < 20; i++)); do body+="<input id=\"${name}$i\" label=\"f$i:\"/>"; done
		printf '<tui shell="_shell.xml"><pane id="main_%s" border="single" split="v">%s</pane></tui>\n' "$name" "$body" >"$d/s_$name.xml"
		printf '<tui><pane id="root" split="v"><pane id="chrome" border="single">%s</pane><pane id="main_%s" border="single" split="v">%s</pane></pane></tui>\n' "$chrome" "$name" "$body" >"$d/p_$name.xml"
	done
	printf '<tui><pane id="root" split="v"><pane id="chrome" border="single">%s</pane><outlet id="body"/></pane></tui>\n' "$chrome" >"$d/_shell.xml"
}
# a floating window: one full page repaint with its layer drawn on top (what every drag step costs), and the hit lookup
# with the layer's zones ranked above the page's
_b_layer_drag_step() {
	tui.layer.move bench_win "$((3 + (_BENCH_STEP++ % 6)))" "$((10 + (_BENCH_STEP % 9)))" >/dev/null
}
_b_layer_hit() {
	_tui_hit.at 20 6
}
_b_store_save_restore() {
	_tui_store.save_page
	_tui_store.restore_page
}

tui.load "$PAGE" >/dev/null
_tui._layout root
tui.render >/dev/null
_BENCH_WID="${_TUI_W_ORDER[0]:-}"
_BENCH_PANE="${_TUI_P_ALL[0]:-root}"

# _bench_size - tui.load resets the screen size (0x0 without a tty): the layout and the hit index need the fixed one
_bench_size() {
	_TUI_ROWS=30 _TUI_COLS=100
	_TUI_P_ROW[root]=1 _TUI_P_COL[root]=1 _TUI_P_H[root]=$_TUI_ROWS _TUI_P_W[root]=$_TUI_COLS
}

# _bench_v2 - loads the v2 pages and runs their benches (after the stage-0 ones, which use $PAGE)
_bench_v2() {
	local f="$_BENCH_ROOT/keep30.xml" i name
	{
		printf '<tui keep_state="true"><pane id="root" split="v" border="single" class="panel">\n'
		for ((i = 0; i < 30; i++)); do printf '<input id="k%d" label="f%d:" label_width="5"/>\n' "$i" "$i"; done
		printf '</pane></tui>\n'
	} >"$f"
	tui.load "$WS_PAGE" >/dev/null
	_bench_size
	_tui._layout root
	tui.render >/dev/null
	# a point on the logs/events divider (the bottom row of logs) and a point inside the details pane
	_BENCH_HX=$((_TUI_P_COL[logs] + 2)) _BENCH_HY=$((_TUI_P_ROW[logs] + _TUI_P_H[logs] - 1))
	_BENCH_MX=$((_TUI_P_COL[details] + 2)) _BENCH_MY=$((_TUI_P_ROW[details] + 3))
	_bench_run resize_drag_step 30 _b_resize_drag_step
	_bench_run collapse_toggle 20 _b_collapse_toggle
	_tui_hit.at "$_BENCH_HX" "$_BENCH_HY" # builds the index once: the bench measures lookups
	_bench_run hit_with_handles 100 _b_hit_with_handles
	_TUI_RUNNING=1 # the hover repaint only runs on a live screen; its output goes to /dev/null
	_bench_run hover_zone_move 30 _b_hover_zone_move
	_TUI_RUNNING=0
	tui.load "$f" >/dev/null
	_bench_size
	_tui._layout root
	tui.render >/dev/null
	for ((i = 0; i < 30; i++)); do _TUI_W_VALUE[k$i]="value $i"; done
	_bench_run store_save_restore 30 _b_store_save_restore
	local lf="$_BENCH_ROOT/layer.xml"
	printf '<tui>\n<pane id="root" split="v" border="single">\n<pane id="lp" border="single">\n<button id="lb1" text="under"/>\n</pane>\n</pane>\n<window id="bench_win" title="Win" x="8" y="3" width="40" height="10" float="true" closable="true">\n<button id="bw1" text="inside"/>\n<button id="bw2" text="more"/>\n</window>\n</tui>\n' >"$lf"
	tui.load "$lf" >/dev/null
	_bench_size
	_tui._layout root
	tui.render >/dev/null
	_BENCH_STEP=0
	_TUI_RUNNING=1 # the repaint only runs on a live screen; its output goes to /dev/null
	_bench_run layer_drag_step 20 _b_layer_drag_step
	_TUI_RUNNING=0
	_tui_hit.at 20 6 # builds the index once
	_bench_run layer_hit 100 _b_layer_hit
	_bench_goto_pages "$_BENCH_ROOT"
	_TUI_ROWS=30 _TUI_COLS=100
	for name in shell plain; do
		_BENCH_PA="$_BENCH_ROOT/${name:0:1}_a.xml" _BENCH_PB="$_BENCH_ROOT/${name:0:1}_b.xml"
		tui.goto "$_BENCH_PA" >/dev/null # builds and caches both pages and the shell
		tui.goto "$_BENCH_PB" >/dev/null
		_bench_run "goto_pair_$name" 20 _b_goto_pair
	done
}

{
	_bench_run cold_page_load 10 _b_cold_load
	_bench_run warm_page_load 20 _b_warm_load
	_bench_run full_render 30 _b_full_render
	_bench_run hover_redraw 50 _b_hover_redraw
	_bench_run focus_move 50 _b_focus_move
	_bench_run mouse_hit 100 _b_mouse_hit
	_bench_run resize_relayout 30 _b_resize_relayout
	_bench_run scroll_burst 30 _b_scroll_burst
	_bench_v2
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
