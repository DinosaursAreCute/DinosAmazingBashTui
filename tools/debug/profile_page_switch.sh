#!/usr/bin/env bash
# profile_page_switch.sh - where does a page switch spend its time? (cache-hit path, headless, no terminal needed)
#   tools/debug/profile_page_switch.sh [-d PAGES_DIR] [-r ROWSxCOLS] PAGE...      (PAGE = file name without .xml)
#   tools/debug/profile_page_switch.sh home settings components debug_input
# For each page: visit once (records it), go home, then time the three phases of a warm tui.goto:
#   reset (tui.reset_ui)  |  load_cached (replay of recorded builder calls + <script> re-sourcing + on_visit)  |  render
# A big load_cached usually means the page's on_visit / callback does real work (see profile_replay.sh to split it).
# A big render usually means many content panes (each costs an awk unless the fast path applies).
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
DIR="$ROOT/lib"
PAGES_DIR="$ROOT/share/demo"
ROWS=45
COLS=150
while [[ "$1" == -* ]]; do
	case "$1" in -d)
		PAGES_DIR="$2"
		shift 2
		;;
	-r)
		ROWS="${2%x*}"
		COLS="${2#*x}"
		shift 2
		;;
	*) break ;; esac
done
(($#)) || {
	sed -n '2,10p' "$0" | sed 's/^# \?//'
	exit 1
}
export XDG_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
cd "$DIR" && source ./tui.sh
PAGES_DIR="$(cd "$PAGES_DIR" && pwd)"
_TUI_ROWS=$ROWS
_TUI_COLS=$COLS
_TUI_P_ROW[root]=1
_TUI_P_COL[root]=1
_TUI_P_H[root]=$ROWS
_TUI_P_W[root]=$COLS
home="${TUI_PROFILE_HOME:-home}"
tui.load "$PAGES_DIR/$home.xml" >/dev/null 2>&1
_TUI_RUNNING=1
for p in "$@"; do
	f="$PAGES_DIR/$p.xml"
	tui.goto "$f" >/dev/null 2>&1
	tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1 # warm the cache
	t0=${EPOCHREALTIME/[.,]/}
	tui.reset_ui >/dev/null 2>&1
	t1=${EPOCHREALTIME/[.,]/}
	tui.load_cached "$f" >/dev/null 2>&1
	t2=${EPOCHREALTIME/[.,]/}
	tui.render >/dev/null 2>&1
	t3=${EPOCHREALTIME/[.,]/}
	printf '%-18s reset=%4dms  load_cached=%4dms  render=%4dms  TOTAL=%4dms  (leaves=%d widgets=%d)\n' "$p" \
		$(((t1 - t0) / 1000)) $(((t2 - t1) / 1000)) $(((t3 - t2) / 1000)) $(((t3 - t0) / 1000)) "${#_TUI_P_LEAVES[@]}" "${#_TUI_W_ORDER[@]}"
	tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
done
