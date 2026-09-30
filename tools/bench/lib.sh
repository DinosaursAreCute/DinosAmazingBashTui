# bench/lib.sh - shared harness for tools/bench/run.sh (stage 0.2). Pure
# bash, fixed inputs, a fixed terminal size - same host-independence rules
# as tools/t.sh, so a bench number means the same thing on any machine.
BENCH_REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

_bench_setup_env() {
	LC_ALL=C
	TZ=UTC
	export LC_ALL TZ
	_BENCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dabt-bench.XXXXXX")"
	trap 'rm -rf "$_BENCH_ROOT"' EXIT
	HOME="$_BENCH_ROOT/home"
	TUI_HOME="$_BENCH_ROOT/home/.config/DABT"
	XDG_CONFIG_HOME="$_BENCH_ROOT/home/.config"
	XDG_DATA_HOME="$_BENCH_ROOT/home/.local/share"
	XDG_CACHE_HOME="$_BENCH_ROOT/home/.cache"
	XDG_STATE_HOME="$_BENCH_ROOT/home/.local/state"
	mkdir -p "$HOME" "$TUI_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
	export HOME TUI_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
	export TUI_APP_NAME="bench_tool"

	_TUI_ROWS=30
	_TUI_COLS=100

	# shellcheck source=../../lib/tui.sh
	source "$BENCH_REPO/lib/tui.sh"

	tui.config.apply
	_TUI_P_ROW[root]=1
	_TUI_P_COL[root]=1
	_TUI_P_H[root]=$_TUI_ROWS
	_TUI_P_W[root]=$_TUI_COLS
	_TUI_P_BORDER[root]="single"
	_TUI_P_TITLE[root]=""
	_TUI_P_LEAVES=(root)
	_TUI_P_ALL=(root)
	_tui_home.touch
	tui.plugin.startup
	tui.hook.fire init
}

# _bench_run NAME ITERS FN [ARGS...] - runs FN ITERS times, prints
# name<TAB>mean_us<TAB>p95_us<TAB>forks (forks = _TUI_PERF_COUNTERS[forks]
# accumulated over the run; only the fork sites instrumented with
# _tui_perf.count forks are counted, not every subshell in the tree).
_bench_run() {
	local name="$1" iters="$2" fn="$3"
	shift 3
	tui.perf.reset
	_TUI_PERF_TRACKING=1
	local -a durs=()
	# _bi (not i/n/row - common un-localized loop names in the code under
	# test; bash's dynamic scoping lets a callee's bare loop var clobber an
	# outer one of the same name) and a while-loop (not `for ((_bi=0..))`,
	# so a callee resetting _bi can't re-trigger the arithmetic increment).
	local _bi=0 t0 t1
	while ((_bi < iters)); do
		t0="${EPOCHREALTIME//[!0-9]/}"
		"$fn" "$@"
		t1="${EPOCHREALTIME//[!0-9]/}"
		durs+=($((t1 - t0)))
		((_bi++))
	done
	local n=${#durs[@]} sum=0 d
	for d in "${durs[@]}"; do ((sum += d)); done
	mapfile -t durs < <(printf '%s\n' "${durs[@]}" | sort -n)
	local p95_idx=$((n * 95 / 100))
	((p95_idx >= n)) && p95_idx=$((n - 1))
	local forks="${_TUI_PERF_COUNTERS[forks]:-0}"
	_TUI_PERF_TRACKING=0
	printf '%s\t%d\t%d\t%d\n' "$name" "$((sum / n))" "${durs[$p95_idx]}" "$forks"
}
