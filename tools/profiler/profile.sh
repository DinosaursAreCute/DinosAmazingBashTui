#!/usr/bin/env bash
# profile.sh - end-to-end profiler for DABT apps.
#   tools/profiler/profile.sh              standard run (~3 min): latency rounds + call-stack trace
#   tools/profiler/profile.sh --quick      ~1.5 min
#   tools/profiler/profile.sh --deep       5 rounds + traced cold start (~10 min)
#   tools/profiler/profile.sh --report DIR re-render a saved run without running anything
#   tools/profiler/profile.sh --help       every option
# It starts the real app in a hidden terminal, plays a scripted user session (start, every page,
# keyboard, mouse, palette, resize, idle, quit), measures latency with probes inside the app, and
# folds a bash xtrace of the same session into call-graph statistics. Results: terminal report
# plus reports/<timestamp>/report.html. Needs bash >= 5 and python3 >= 3.8 (no pip packages).
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

((BASH_VERSINFO[0] >= 5)) || {
	echo "profile.sh: bash >= 5 required (found $BASH_VERSION)" >&2
	exit 2
}
command -v python3 >/dev/null || {
	echo "profile.sh: python3 not found (used for the pty driver and the report; standard library only)" >&2
	exit 2
}
python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' || {
	echo "profile.sh: python3 >= 3.8 required" >&2
	exit 2
}

echo "Starting profiler..."
# The machine must stay awake for the whole run (a suspend mid-run ruins every timing). Use an inhibitor when one works;
# DABT_NO_INHIBIT=1 turns this off.
if [[ -z "${DABT_NO_INHIBIT:-}" ]]; then
	if command -v systemd-inhibit >/dev/null 2>&1 && systemd-inhibit --what=sleep:idle --who="DABT profiler" --why="probe" true 2>/dev/null; then
		exec systemd-inhibit --what=sleep:idle --who="DABT profiler" --why="profiling run: timings need an awake machine" \
			python3 "$HERE/profile.py" "$@"
	elif command -v caffeinate >/dev/null 2>&1; then
		exec caffeinate -i python3 "$HERE/profile.py" "$@" # macOS
	fi
fi
exec python3 "$HERE/profile.py" "$@"
