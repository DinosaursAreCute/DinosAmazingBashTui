#!/usr/bin/env bash
# bench_page_switch.sh - times tui.goto's three phases (reset_ui / load / render)
# across page switches. Baseline for evaluating static-content caching on page load.
#
# The actual page-switching runs in a background worker, isolated from this
# terminal (its stdin is /dev/null, so tui.init's stty calls can't touch the
# real tty), reporting one line per switch down a fifo. The foreground never
# blocks on that fifo (read -t) - it always keeps driving a progress bar and
# a stall watchdog, and Ctrl-C always reaches it because this terminal is
# never put in raw mode. If the worker itself locks up, Ctrl-C here still
# kills it (SIGTERM then SIGKILL).
#
# usage: tools/legacy/bench_page_switch.sh [-n iterations] [-c] [page.xml ...]
#   no page args -> benchmarks every config/*.xml (skips _*.xml fragments)
#   -c            -> switch via tui.load_cached (lib/tui_cache.sh) instead of
#                     the raw tui.load, and pick up any already-warmed disk
#                     cache first - run once with -c and once without to
#                     compare the two logs/<run>/report.txt side by side.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/terminal_controls.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/terminal_renderer.sh"

# Defensive: reset any scroll region (DECSTBM) a *previous* run of this (or
# any other pb.init-using) script may have left wedged on this terminal if
# it was killed before its own teardown could run - otherwise this run's
# output could go the same way, invisible for reasons that predate it.
printf '\e[r'

ITER=20
CACHED=0
while getopts "n:ch" opt; do
    case "$opt" in
        n) ITER="$OPTARG" ;;
        c) CACHED=1 ;;
        h) echo "usage: $0 [-n iterations] [-c] [page.xml ...]" >&2; exit 0 ;;
        *) echo "usage: $0 [-n iterations] [-c] [page.xml ...]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

PAGES=()
if (( $# > 0 )); then
    for arg in "$@"; do
        if [[ "$arg" != */* && ! -r "$arg" ]]; then
            arg="$REPO_ROOT/config/$arg"
        fi
        PAGES+=("$arg")
    done
else
    while IFS= read -r f; do
        [[ "$(basename "$f")" == _* ]] && continue
        PAGES+=("$f")
    done < <(find "$REPO_ROOT/config" -maxdepth 1 -name '*.xml' | sort)
fi
(( ${#PAGES[@]} >= 1 )) || { echo "no pages to benchmark" >&2; exit 1; }
(( ITER >= 1 )) || { echo "iterations must be >= 1" >&2; exit 1; }

if [[ -z "${EPOCHREALTIME:-}" ]]; then
    echo "bench_page_switch.sh: needs bash 5+ (EPOCHREALTIME)" >&2
    exit 1
fi

now_us() { printf '%s' "${EPOCHREALTIME//[^0-9]/}"; }

TOTAL_SWITCHES=$(( ${#PAGES[@]} * ITER ))

# Runs land in logs/<timestamp>/ under the repo, not /tmp, so the raw data
# (results.txt) and the rendered report (report.txt) are still there to
# look at after the run. The fifo alone is ephemeral and gets removed.
LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
MODE_TAG="uncached"; (( CACHED )) && MODE_TAG="cached"
WORKDIR="$LOG_DIR/bench_page_switch_${RUN_ID}_${MODE_TAG}"
mkdir -p "$WORKDIR"
PROGRESS_FIFO="$WORKDIR/progress.fifo"
RESULTS_FILE="$WORKDIR/results.txt"
REPORT_FILE="$WORKDIR/report.txt"
mkfifo "$PROGRESS_FIFO"

#  worker the real page-switching loop, run in the background ───────
# stdin -> /dev/null so tui.init's `stty -echo -icanon` (which targets fd0,
# not whatever the controlling tty happens to be) can't touch the real
# terminal the progress bar is drawn on. Its own screen output (fd1) is
# discarded the same way the old single-process version did; only the
# "PROGRESS ..." lines on fd 6 (the fifo) and the final results file leave
# this subshell.
_bench_worker() {
    exec </dev/null
    exec 6>"$PROGRESS_FIFO"
    # stdout (the TUI's own screen escapes) is thrown away, but stderr goes
    # to a log file, not /dev/null - a worker crash needs to be diagnosable,
    # not just visible as "no results" with the real reason lost.
    exec 3>&1 1>/dev/null 2>"$WORKDIR/worker.stderr.log"

    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/tui.sh"
    local -A SUM_RESET=() SUM_LOAD=() SUM_RENDER=() SUM_TOTAL=() COUNT=()
    local -A COLD_TOTAL=() MIN_TOTAL=() MAX_TOTAL=() SERIES_MS=()
    trap '_master_cleanup 2>/dev/null' EXIT INT TERM

    tui.init
    # Pick up whatever's already warmed on disk (e.g. from a prior
    # bin/DABT_demo.sh run) so -c reflects realistic steady-state replay
    # from the first switch, not just from the second visit onward.
    (( CACHED )) && tui.cache.load_dir "$(tui.cache.disk_dir)"

    # named iter_i, not i: tui.sh's _tui._render_output has an un-`local`
    # `for (( i=... ))` scroll loop that, via bash's dynamic scoping,
    # clobbers any caller's variable literally named `i` on every
    # tui.render call - silently breaking this loop's bound if named `i`.
    local page name iter_i t0 t1 t2 t3 reset_us load_us render_us total_us switch_n=0
    for page in "${PAGES[@]}"; do
        name="$(basename "$page")"
        for (( iter_i = 0; iter_i < ITER; iter_i++ )); do
            t0=$(now_us)
            tui.reset_ui
            t1=$(now_us)
            if (( CACHED )); then
                tui.load_cached "$page"
            else
                tui.load "$page"
            fi
            t2=$(now_us)
            tui.render
            t3=$(now_us)

            reset_us=$(( t1 - t0 )); load_us=$(( t2 - t1 ))
            render_us=$(( t3 - t2 )); total_us=$(( t3 - t0 ))

            SUM_RESET[$name]=$(( ${SUM_RESET[$name]:-0} + reset_us ))
            SUM_LOAD[$name]=$(( ${SUM_LOAD[$name]:-0} + load_us ))
            SUM_RENDER[$name]=$(( ${SUM_RENDER[$name]:-0} + render_us ))
            SUM_TOTAL[$name]=$(( ${SUM_TOTAL[$name]:-0} + total_us ))
            COUNT[$name]=$(( ${COUNT[$name]:-0} + 1 ))
            SERIES_MS[$name]="${SERIES_MS[$name]:-}${SERIES_MS[$name]:+ }$(( total_us / 1000 ))"
            (( iter_i == 0 )) && COLD_TOTAL[$name]=$total_us
            if [[ -z "${MIN_TOTAL[$name]:-}" || total_us -lt ${MIN_TOTAL[$name]} ]]; then
                MIN_TOTAL[$name]=$total_us
            fi
            if [[ -z "${MAX_TOTAL[$name]:-}" || total_us -gt ${MAX_TOTAL[$name]} ]]; then
                MAX_TOTAL[$name]=$total_us
            fi

            (( switch_n++ ))
            printf 'PROGRESS %d %d %s %d\n' "$switch_n" "$TOTAL_SWITCHES" "$name" "$total_us" >&6
        done
    done

    exec 1>&3 3>&-

    # Data-only, pipe-delimited - the foreground does all the pretty
    # rendering (table/sparkline), since terminal_renderer.sh needs a real
    # terminal width and shouldn't run inside the redirected/headless worker.
    {
        for page in "${PAGES[@]}"; do
            name="$(basename "$page")"
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$name" "${COUNT[$name]}" \
                "${SUM_RESET[$name]}" "${SUM_LOAD[$name]}" "${SUM_RENDER[$name]}" "${SUM_TOTAL[$name]}" \
                "${COLD_TOTAL[$name]}" "${MIN_TOTAL[$name]}" "${MAX_TOTAL[$name]}" \
                "${SERIES_MS[$name]}"
        done
    } > "$RESULTS_FILE"

    printf 'DONE\n' >&6
    exec 6>&-
}

# foreground progress bar + stall watchdog, worker always killable ──
WORKER_PID=""

cleanup_fg() {
    trap - EXIT INT TERM
    printf '\r'; erase.line_right 2>/dev/null; printf '\n'
    cur.show
    { exec 5>&-; } 2>/dev/null
    if [[ -n "$WORKER_PID" ]] && kill -0 "$WORKER_PID" 2>/dev/null; then
        kill -TERM "$WORKER_PID" 2>/dev/null
        for _ in 1 2 3 4 5; do
            kill -0 "$WORKER_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$WORKER_PID" 2>/dev/null
    fi
    # Keep $WORKDIR (results.txt/report.txt) for post-run inspection -
    # only the fifo is throwaway.
    rm -f "$PROGRESS_FIFO" 2>/dev/null
}
trap cleanup_fg EXIT INT TERM

# Open read+write so this open never blocks waiting for a writer - the
# worker's later write-only open then always finds a reader present.
exec 5<>"$PROGRESS_FIFO"

_bench_worker &
WORKER_PID=$!

# A plain \r-redrawn line, not pb.init/pb.update's scroll-region (DECSTBM)
# trick: DECSTBM has to be reset by pb.teardown to un-wedge, and anything
# that kills this script in a way the trap can't catch (SIGKILL, a closed
# terminal tab) leaves that reset never running - the real terminal's
# scroll region then stays stuck, silently swallowing output in every
# later command on that tty, not just this script's own run.
draw_bar() {
    local msg="$1" current="$2" total="$3" width=30
    local pct=0
    (( total > 0 )) && pct=$(( 100 * current / total ))
    (( pct > 100 )) && pct=100
    local filled=$(( pct * width / 100 ))
    local bar_filled bar_empty
    bar_filled="$(printf '%*s' "$filled" '' | tr ' ' '#')"
    bar_empty="$(printf '%*s' $(( width - filled )) '' | tr ' ' '.')"
    printf '\r'
    erase.line_right
    printf "%b|%s%s| %3d%% %s%b" "$BRIGHT_CYAN" "$bar_filled" "$bar_empty" "$pct" "$msg" "$RESET"
}
clear_bar() {
    printf '\r'
    erase.line_right
}

cur.hide
printf "${BRIGHT_CYAN}bench_page_switch${RESET}: %d page(s) x %d iteration(s) = %d switches, mode=%s (worker pid %d)\n" \
    "${#PAGES[@]}" "$ITER" "$TOTAL_SWITCHES" "$( (( CACHED )) && printf cached || printf uncached )" "$WORKER_PID"

START_US=$(now_us)
LAST_PROGRESS_US=$START_US
STALL_SEC=5
current_n=0
last_name="starting..."
last_ms=0
done_flag=0

# Redraws (draw_bar forks a couple of subshells to build the bar string)
# are throttled to "on new data, or at most ~3x/sec otherwise" rather than
# every 0.2s poll tick unconditionally - with -c, individual switches can
# drop to ~250ms, cheap enough that a busier foreground redraw loop
# measurably steals wall-clock from the worker's own timed sections
# (they're concurrent processes; the OS scheduler doesn't know one of them
# is "the thing being timed"). Uncached switches (700ms+) never showed
# this because the redraw cost was already negligible next to them.
LAST_DRAW_US=0
DRAW_MIN_INTERVAL_US=300000

while (( ! done_flag )); do
    got_new=0
    if IFS= read -r -t 0.2 -u 5 line; then
        got_new=1
        now_line_us=$(now_us)
        case "$line" in
            "PROGRESS "*)
                read -r _ current_n _total last_name last_total_us <<< "$line"
                last_ms=$(( last_total_us / 1000 ))
                LAST_PROGRESS_US=$now_line_us
                ;;
            "DONE")
                done_flag=1
                ;;
        esac
    fi

    # Worker gone without a DONE line (crashed) - stop waiting on it.
    if (( ! done_flag )) && ! kill -0 "$WORKER_PID" 2>/dev/null; then
        done_flag=1
    fi
    (( done_flag )) && break

    now=$(now_us)
    (( ! got_new && (now - LAST_DRAW_US) < DRAW_MIN_INTERVAL_US )) && continue
    LAST_DRAW_US=$now

    elapsed_s=$(( (now - START_US) / 1000000 ))
    stalled_s=$(( (now - LAST_PROGRESS_US) / 1000000 ))

    if (( stalled_s >= STALL_SEC )); then
        draw_bar "${BRIGHT_YELLOW}STALLED ${stalled_s}s${RESET} since '${last_name}' (${last_ms}ms) - pid ${WORKER_PID}, ${elapsed_s}s elapsed - Ctrl-C to kill" \
            "$current_n" "$TOTAL_SWITCHES"
    else
        draw_bar "${last_name} ${last_ms}ms  (${elapsed_s}s elapsed)" "$current_n" "$TOTAL_SWITCHES"
    fi
done

wait "$WORKER_PID" 2>/dev/null
clear_bar
printf '\n'
cur.show
trap - EXIT INT TERM
{ exec 5>&-; } 2>/dev/null

{
if [[ -s "$RESULTS_FILE" ]]; then
    # ── build the table + timeline chart from the worker's raw numbers ──
    declare -a table_rows=("Page|N|Mean ms|Min ms|Max ms|Cold ms|Load%|Trend")
    declare -a all_series=()
    run_sum_total=0 run_count=0 run_min="" run_max=""

    while IFS='|' read -r name n sum_reset sum_load sum_render sum_total cold min max series; do
        [[ -z "$name" ]] && continue
        mean_ms=$(awk -v t="$sum_total" -v n="$n" 'BEGIN { printf "%.0f", t/n/1000 }')
        min_ms=$(awk -v v="$min" 'BEGIN { printf "%.0f", v/1000 }')
        max_ms=$(awk -v v="$max" 'BEGIN { printf "%.0f", v/1000 }')
        cold_ms=$(awk -v v="$cold" 'BEGIN { printf "%.0f", v/1000 }')
        load_pct=$(awk -v a="$sum_load" -v t="$sum_total" 'BEGIN { printf "%.0f", (t>0 ? a/t*100 : 0) }')
        trend="$(sparkline_string -d " " "$series" 2>/dev/null)"
        table_rows+=("${name}|${n}|${mean_ms}|${min_ms}|${max_ms}|${cold_ms}|${load_pct}%|${trend}")

        # intentional: split the space-separated ms series into elements
        # shellcheck disable=SC2206
        all_series+=($series)
        run_sum_total=$(( run_sum_total + sum_total ))
        run_count=$(( run_count + n ))
        [[ -z "$run_min" || min -lt run_min ]] && run_min=$min
        [[ -z "$run_max" || max -gt run_max ]] && run_max=$max
    done < "$RESULTS_FILE"

    if (( ${#all_series[@]} > 0 )); then
        printf "\n${BRIGHT_CYAN}Timeline${RESET} (ms/switch, run order):\n"
        sparkline -c BRIGHT_GREEN -d " " -w 60 "${all_series[*]}"
    fi

    printf "\n"
    table -d "|" "${table_rows[@]}"

    if (( run_count > 0 )); then
        run_mean_ms=$(awk -v t="$run_sum_total" -v n="$run_count" 'BEGIN { printf "%.0f", t/n/1000 }')
        run_min_ms=$(awk -v v="$run_min" 'BEGIN { printf "%.0f", v/1000 }')
        run_max_ms=$(awk -v v="$run_max" 'BEGIN { printf "%.0f", v/1000 }')
        printf "\n"
        kv "Mode: ${MODE_TAG}" "Switches: ${run_count}" "Mean: ${run_mean_ms}ms" "Min: ${run_min_ms}ms" "Max: ${run_max_ms}ms"
    fi
else
    echo "bench_page_switch.sh: worker produced no results (crashed or was killed)"
    if [[ -s "$WORKDIR/worker.stderr.log" ]]; then
        printf "\nworker stderr (%s):\n" "$WORKDIR/worker.stderr.log"
        cat "$WORKDIR/worker.stderr.log"
    fi
fi
} | tee "$REPORT_FILE"

rm -f "$PROGRESS_FIFO" 2>/dev/null
printf "\nLog: %s\n" "$WORKDIR"
