#!/usr/bin/env bash
# page_switch.sh [N] [-h] [--pages "a.xml b.xml ..."] - profiles N page
# switches (default 20) through the real tui.goto path, using lib/perf.sh's
# existing span/counter instrumentation (parse/build/layout/render/flush,
# cache_hit/cache_miss, layout_memo_hit/miss, bytes_flushed, forks) instead
# of ad-hoc timing. Headless: no real terminal is taken over (same
# _bench_setup_env as tools/bench/run.sh), so this runs anywhere.
#
#   tools/bench/page_switch.sh                    # compact, microseconds, script-friendly
#   tools/bench/page_switch.sh -h                 # human: live per-switch lines, ms, heatmap/sparkline/boxplots
#   tools/bench/page_switch.sh 100 -h
#   tools/bench/page_switch.sh 40 --pages "home.xml settings.xml"
#
# -h isn't --help (there's no long-form flag here, so there's nothing for
# that to collide with) - it means "human-readable", matching what was
# actually asked for.
#
# Each switch alternates: every page's FIRST visit is a cache miss (a real
# parse+build+layout - genuinely ~1-2 SECONDS each, see tools/bench/run.sh's
# own cold_page_load baseline; that's normal, not a bug), every later
# revisit in the rotation is a cache hit (replay - parse/build spans won't
# fire at all for it, just render/flush and the cache_hit counter). A run
# mixing both is dominated by however many cache misses it contains, so the
# counters table's cache_hit/cache_miss split (and, in -h mode, seeing cold
# vs warm rows right in the heatmap) is what makes the numbers interpretable
# at all.
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=lib.sh
source "$REPO/tools/bench/lib.sh"
# shellcheck source=../../lib/dapk/ui.sh
source "$REPO/lib/dapk/ui.sh"
# shellcheck source=../../lib/terminal_renderer.sh
source "$REPO/lib/terminal_renderer.sh"
# shellcheck source=../../lib/terminal_controls.sh
source "$REPO/lib/terminal_controls.sh"

_PS_N=20
_PS_PAGES="home.xml components.xml widgets.xml settings.xml monitor.xml docu.xml"
_PS_HUMAN=0
while (($#)); do
	case "$1" in
		-h)
			_PS_HUMAN=1
			shift
			;;
		--pages)
			_PS_PAGES="$2"
			shift 2
			;;
		*)
			_PS_N="$1"
			shift
			;;
	esac
done

_bench_setup_env
dapk.ui.init
DEMO_DIR="$REPO/share/demo"

declare -a _ps_pages=()
for _ps_p in $_PS_PAGES; do
	[[ -r "$DEMO_DIR/$_ps_p" ]] || {
		dapk.ui.warn "skipping unreadable page '$_ps_p'"
		continue
	}
	_ps_pages+=("$DEMO_DIR/$_ps_p")
done
((${#_ps_pages[@]} >= 2)) || {
	dapk.ui.err "need at least 2 readable pages, got ${#_ps_pages[@]}"
	exit 1
}

# One-time setup cost, excluded from the measured run below by the
# tui.perf.reset right after it - tui.goto (unlike tui.start_cached) has no
# warm-up phase of its own, so the very first page needs an initial tui.load
# to have something to switch away FROM.
tui.load "${_ps_pages[0]}" >/dev/null

# _ps_us_ms US -> stdout "<1ms" or "Nms" (rounded, not truncated - a 600us
# phase should read 1ms, not 0ms).
_ps_us_ms() {
	local us="$1" ms=$(((us + 500) / 1000))
	((ms < 1)) && {
		printf '<1ms'
		return
	}
	printf '%dms' "$ms"
}

_TUI_PERF_TRACKING=1
tui.perf.reset
# _TUI_RUNNING is deliberately left 0: it's a real-terminal-session flag -
# several pages' on_visit handlers key off it to decide whether to start
# real background work (tui.exec, polling), which this headless profiler
# never wants. tui.goto only calls tui.render itself when _TUI_RUNNING is
# set, so this calls it explicitly instead, timed as part of the same
# "goto" span - the same cost tui.goto would pay in a real running app,
# without opting into everything else that flag gates.

declare -a _ps_row_page=() _ps_row_total=()
declare -A _ps_row_phase= # "i,phase" -> us, filled below
_ps_ring_len() {
	local -a v=(${_TUI_PERF_LOG[$1]:-})
	printf '%s' "${#v[@]}"
}
_ps_ring_sum_from() { # NAME FROM_IDX -> sum of entries at/after FROM_IDX
	local -a v=(${_TUI_PERF_LOG[$1]:-})
	local from="$2" sum=0 i
	for ((i = from; i < ${#v[@]}; i++)); do ((sum += v[i])); done
	printf '%s' "$sum"
}

pb.init
_ps_t0="${EPOCHREALTIME//[!0-9]/}"
_ps_i=0
while ((_ps_i < _PS_N)); do
	_ps_target="${_ps_pages[$((_ps_i % ${#_ps_pages[@]}))]}"
	_ps_label="$(basename "$_ps_target")"
	pb.update "$_ps_label" "$_ps_i" "$_PS_N"
	_ps_parse0=$(_ps_ring_len parse) _ps_build0=$(_ps_ring_len build)
	_ps_layout0=$(_ps_ring_len layout) _ps_render0=$(_ps_ring_len render)
	_ps_flush0=$(_ps_ring_len flush)

	_tui_perf.begin goto
	tui.goto "$_ps_target" >/dev/null 2>&1
	tui.render >/dev/null 2>&1
	_tui_perf.end goto

	_ps_row_page+=("$_ps_label")
	_ps_p=$(_ps_ring_sum_from parse "$_ps_parse0")
	_ps_b=$(_ps_ring_sum_from build "$_ps_build0")
	_ps_l=$(_ps_ring_sum_from layout "$_ps_layout0")
	_ps_r=$(_ps_ring_sum_from render "$_ps_render0")
	_ps_f=$(_ps_ring_sum_from flush "$_ps_flush0")
	_ps_row_phase["$_ps_i,parse"]=$_ps_p
	_ps_row_phase["$_ps_i,build"]=$_ps_b
	_ps_row_phase["$_ps_i,layout"]=$_ps_l
	_ps_row_phase["$_ps_i,render"]=$_ps_r
	_ps_row_phase["$_ps_i,flush"]=$_ps_f
	_ps_total_us=$((_ps_p + _ps_b + _ps_l + _ps_r + _ps_f))
	_ps_row_total+=("$_ps_total_us")

	((_ps_i++))
	echo $_ps_label $((_ps_total_us / 1000)) ms

done
_ps_t1="${EPOCHREALTIME//[!0-9]/}"

pb.teardown

_ps_total_ms=$(((_ps_t1 - _ps_t0) / 1000))
_ps_mean_us=$(((_ps_t1 - _ps_t0) / _PS_N))

if ((! _PS_HUMAN)); then
	dapk.ui.kv "total" "${_ps_total_ms}ms (${_ps_mean_us}us/switch mean, wall-clock incl. everything below)"

	declare -a _ps_rows=()
	while IFS=$'\t' read -r _ps_kind _ps_a _ps_b _ps_c _ps_d; do
		[[ "$_ps_kind" == span ]] && _ps_rows+=("$_ps_a"$'\x1f'"${_ps_b} us"$'\x1f'"${_ps_c} us"$'\x1f'"$_ps_d")
	done < <(tui.perf.report)
	_ps_h1="phase" _ps_h2="mean" _ps_h3="p95" _ps_h4="count"
	_ps_w1=${#_ps_h1} _ps_w2=${#_ps_h2} _ps_w3=${#_ps_h3} _ps_w4=${#_ps_h4}
	for _ps_row in "${_ps_rows[@]}"; do
		IFS=$'\x1f' read -r _ps_a _ps_b _ps_c _ps_d <<<"$_ps_row"
		((${#_ps_a} > _ps_w1)) && _ps_w1=${#_ps_a}
		((${#_ps_b} > _ps_w2)) && _ps_w2=${#_ps_b}
		((${#_ps_c} > _ps_w3)) && _ps_w3=${#_ps_c}
		((${#_ps_d} > _ps_w4)) && _ps_w4=${#_ps_d}
	done
	echo
	printf '%s--- span breakdown ---%s\n' "$B" "$R"
	printf '%-*s  %*s  %*s  %*s\n' "$_ps_w1" "$_ps_h1" "$_ps_w2" "$_ps_h2" "$_ps_w3" "$_ps_h3" "$_ps_w4" "$_ps_h4"
	for _ps_row in "${_ps_rows[@]}"; do
		IFS=$'\x1f' read -r _ps_a _ps_b _ps_c _ps_d <<<"$_ps_row"
		printf '%-*s  %*s  %*s  %*s\n' "$_ps_w1" "$_ps_a" "$_ps_w2" "$_ps_b" "$_ps_w3" "$_ps_c" "$_ps_w4" "$_ps_d"
	done

	declare -a _ps_crows=()
	while IFS=$'\t' read -r _ps_kind _ps_a _ps_b; do
		[[ "$_ps_kind" == counter ]] && _ps_crows+=("$_ps_a"$'\x1f'"$_ps_b")
	done < <(tui.perf.report)
	_ps_ch1="counter" _ps_ch2="total"
	_ps_cw1=${#_ps_ch1} _ps_cw2=${#_ps_ch2}
	for _ps_row in "${_ps_crows[@]}"; do
		IFS=$'\x1f' read -r _ps_a _ps_b <<<"$_ps_row"
		((${#_ps_a} > _ps_cw1)) && _ps_cw1=${#_ps_a}
		((${#_ps_b} > _ps_cw2)) && _ps_cw2=${#_ps_b}
	done
	echo
	printf '%s--- counters ---%s\n' "$B" "$R"
	printf '%-*s  %*s\n' "$_ps_cw1" "$_ps_ch1" "$_ps_cw2" "$_ps_ch2"
	for _ps_row in "${_ps_crows[@]}"; do
		IFS=$'\x1f' read -r _ps_a _ps_b <<<"$_ps_row"
		printf '%-*s  %*s\n' "$_ps_cw1" "$_ps_a" "$_ps_cw2" "$_ps_b"
	done
	exit 0
fi

# ═══════════════════════════════════════════════════════════════════════
#  -h: human-readable - heatmap, sparkline, box plots
# ═══════════════════════════════════════════════════════════════════════
# Every page in the rotation is a cache miss exactly once - its first visit,
# switches 1..#pages - then a cache hit every time after. So the first
# #pages switches are structurally always the slow ones and everything
# after is steady-state fast; averaging them together makes the mean
# meaningless (it's neither the cold cost nor the warm one). The heatmap
# below still shows every switch, cold included - that's where seeing the
# warm-up actually happen is useful - but the summary/sparkline stats
# exclude it.
_ps_warmup=${#_ps_pages[@]}
((_ps_warmup >= _PS_N)) && _ps_warmup=0 # nothing but warm-up ran - don't exclude everything

echo
printf '%s━ Summary ━%s\n' "$B" "$R"
if ((_ps_warmup > 0)); then
	_ps_steady_us=0
	for ((_ps_i = _ps_warmup; _ps_i < _PS_N; _ps_i++)); do ((_ps_steady_us += _ps_row_total[_ps_i])); done
	_ps_steady_n=$((_PS_N - _ps_warmup))
	printf 'Total elapsed: %s\n' "$(_ps_us_ms $((_ps_t1 - _ps_t0)))"
	printf 'Steady-state mean: %s/switch (%d switches, %d warm-up excluded)\n' \
		"$(_ps_us_ms $((_ps_steady_us / _ps_steady_n)))" "$_ps_steady_n" "$_ps_warmup"
else
	printf 'Total elapsed: %s\n' "$(_ps_us_ms $((_ps_t1 - _ps_t0)))"
	printf 'Mean/switch: %s (all cache misses, no warm-up)\n' "$(_ps_us_ms "$_ps_mean_us")"
fi

# ── heatmap: rows = switches (labeled by page), columns = total + each phase ──
echo
printf '%s━ Heatmap by switch (ms, colored by column intensity) ━%s\n' "$B" "$R"
_ps_phases=(parse build layout render flush)

# Build heatmap rows: "label|total|phase1|phase2|..."
declare -a _ps_heat_rows=("page|total|parse|build|layout|render|flush")
for ((_ps_i = 0; _ps_i < _PS_N; _ps_i++)); do
	if ((_ps_i == _ps_warmup && _ps_warmup > 0)); then
		_ps_heat_rows+=("WARM-UP ABOVE|──|──|──|──|──|──")
	fi
	_ps_row="$(printf '%02d_%s' "$((_ps_i + 1))" "${_ps_row_page[$_ps_i]}")|$((_ps_row_total[$_ps_i] / 1000))"
	for _ps_p in "${_ps_phases[@]}"; do
		_ps_v=${_ps_row_phase["$_ps_i,$_ps_p"]:-0}
		_ps_row+=$(printf '|%d' "$((_ps_v / 1000))")
	done
	_ps_heat_rows+=("$_ps_row")
done
heatmap "${_ps_heat_rows[@]}" -cw 5 -p 0 -lw 12

# ── sparkline: total time per switch, steady-state only (warm-up would ──
# dwarf every other bar and flatten the rest of the chart to nothing) ──
echo
printf '%s━ Steady-state totals (sparkline, ms; %d warm-up switch(es) excluded) ━%s\n' "$B" "$_ps_warmup" "$R"
declare -a _ps_steady_rows=("${_ps_row_total[@]:_ps_warmup}")
_ps_spark_data=""
for _ps_v in "${_ps_steady_rows[@]}"; do _ps_spark_data+="$((_ps_v / 1000)) "; done
sparkline -c CYAN "$_ps_spark_data"
printf 'min %s   max %s   n=%d\n' \
	"$(_ps_us_ms "$(printf '%s\n' "${_ps_steady_rows[@]}" | sort -n | head -1)")" \
	"$(_ps_us_ms "$(printf '%s\n' "${_ps_steady_rows[@]}" | sort -n | tail -1)")" \
	"${#_ps_steady_rows[@]}"

# ── box plots: full distribution per phase, from every recorded sample.
# "goto" fires exactly once per switch (1:1 with the loop), so its warm-up
# entries can be skipped unambiguously by index; parse/build only ever
# happen on a cache miss anyway (their whole sample set IS the cold cost,
# nothing to exclude), and layout/render/flush fire on every switch as part
# of normal steady-state work too, not just during warm-up, so their full
# distribution is the honest one to show. ────────────────────────────────
echo
printf '%s━ Distribution per phase (box plot, ms) ━%s\n' "$B" "$R"
_ps_summary_ms() { # SPAN_NAME [SKIP_FIRST] -> stdout "min,q1,med,q3,max,n" in ms
	local -a v=(${_TUI_PERF_LOG[$1]:-})
	local skip="${2:-0}"
	((skip > 0)) && v=("${v[@]:skip}")
	local n=${#v[@]}
	((n == 0)) && {
		printf '0,0,0,0,0,0'
		return
	}
	local -a ms=() x
	for x in "${v[@]}"; do ms+=($((x / 1000))); done
	mapfile -t ms < <(printf '%s\n' "${ms[@]}" | sort -n)
	printf '%s,%s,%s,%s,%s,%s' "${ms[0]}" "${ms[$((n / 4))]}" "${ms[$((n / 2))]}" "${ms[$((n * 3 / 4))]}" "${ms[$((n - 1))]}" "$n"
}
declare -a _ps_box_rows=("goto (steady-state):$(_ps_summary_ms goto "$_ps_warmup")")
for _ps_p in "${_ps_phases[@]}"; do
	_ps_box_rows+=("$_ps_p:$(_ps_summary_ms "$_ps_p")")
done
boxplot "${_ps_box_rows[@]}"
