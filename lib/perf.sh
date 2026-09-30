# ╔════════════════════════════════════════════════════════════════════════╗
# ║    perf.sh                                                              ║
# ╚════════════════════════════════════════════════════════════════════════╝
# Fork-free span timing and counters (markup-v2 stage 0.2). Spans use
# $EPOCHREALTIME so a begin/end pair never forks; with _TUI_PERF_TRACKING=0
# every entry point below is a single `(( ))` test and returns immediately.
#
# Public: tui.perf.report, tui.perf.reset, tui.perf.mean_render_ms (tui.sh).
# Private: _tui_perf.begin/end/count wrap the phases that matter (parse,
# build, layout, render, flush, dispatch) in the current code.

declare -g _TUI_PERF_TRACKING="${_TUI_PERF_TRACKING:-0}"
declare -gA _TUI_PERF_T0=()       # span name -> start time (us), set by begin
declare -gA _TUI_PERF_LOG=()      # span name -> space-joined ring of durations (us)
declare -gA _TUI_PERF_COUNTERS=() # counter name -> integer total
declare -gi _TUI_PERF_RING_MAX=500

# $EPOCHREALTIME has a comma decimal under some locales (e.g. de_DE);
# stripping everything but digits keeps this fork-free and locale-proof,
# unlike splitting on '.' or handing the raw value to awk/bc.
_tui_perf._now_us() { _TUI_PERF_NOW_US="${EPOCHREALTIME//[!0-9]/}"; }

_tui_perf.begin() {
	((_TUI_PERF_TRACKING)) || return 0
	_tui_perf._now_us
	_TUI_PERF_T0[$1]=$_TUI_PERF_NOW_US
}

_tui_perf.end() {
	((_TUI_PERF_TRACKING)) || return 0
	local name="$1" t0="${_TUI_PERF_T0[$1]:-}"
	[[ -z "$t0" ]] && return 0
	_tui_perf._now_us
	local -a vals=(${_TUI_PERF_LOG[$name]:-})
	vals+=($((_TUI_PERF_NOW_US - t0)))
	# trim the oldest half once the ring doubles its budget, same
	# amortised-trim shape _tui._flush already uses for its render log.
	((${#vals[@]} > _TUI_PERF_RING_MAX * 2)) && vals=("${vals[@]: -_TUI_PERF_RING_MAX}")
	_TUI_PERF_LOG[$name]="${vals[*]} "
}

# _tui_perf.count NAME [N=1] - adds N (default 1) to counter NAME.
_tui_perf.count() {
	((_TUI_PERF_TRACKING)) || return 0
	local name="$1" n="${2:-1}"
	_TUI_PERF_COUNTERS[$name]=$((${_TUI_PERF_COUNTERS[$name]:-0} + n))
}

tui.perf.reset() {
	_TUI_PERF_T0=()
	_TUI_PERF_LOG=()
	_TUI_PERF_COUNTERS=()
}

# tui.perf.report - one line per span (span<TAB>name<TAB>mean_us<TAB>p95_us<TAB>count),
# then one line per counter (counter<TAB>name<TAB>total). Not a hot path: the p95 sort
# forks, same as any other one-shot reporting tool.
tui.perf.report() {
	local name
	for name in "${!_TUI_PERF_LOG[@]}"; do
		local -a vals=(${_TUI_PERF_LOG[$name]})
		local n=${#vals[@]}
		((n == 0)) && continue
		local sum=0 v
		for v in "${vals[@]}"; do ((sum += v)); done
		mapfile -t vals < <(printf '%s\n' "${vals[@]}" | sort -n)
		local p95_idx=$((n * 95 / 100))
		((p95_idx >= n)) && p95_idx=$((n - 1))
		printf 'span\t%s\t%d\t%d\t%d\n' "$name" "$((sum / n))" "${vals[$p95_idx]}" "$n"
	done
	for name in "${!_TUI_PERF_COUNTERS[@]}"; do
		printf 'counter\t%s\t%d\n' "$name" "${_TUI_PERF_COUNTERS[$name]}"
	done
}

# TUI_PERF_LOG=FILE - dump the report once at exit, so a real session can be
# profiled without editing code.
_tui_perf.dump_at_exit() { tui.perf.report >>"$TUI_PERF_LOG"; }
[[ -n "${TUI_PERF_LOG:-}" ]] && trap '_tui_perf.dump_at_exit' EXIT
