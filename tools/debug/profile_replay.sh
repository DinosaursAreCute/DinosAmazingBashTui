#!/usr/bin/env bash
# profile_replay.sh - which recorded call costs the most when a cached page is replayed?
#   tools/debug/profile_replay.sh [-d PAGES_DIR] PAGE...
# Replays the page's recorded builder calls one by one and adds up the time per call name (fork-free timing via
# $EPOCHREALTIME, so the numbers are not inflated by the measurement). Look for: an _tui_cache_run_on_visit line that
# dominates (the page's own on_visit work), _tui_cache_source (callback files re-sourced every visit), or a cheap
# builder whose per-call cost is unexpectedly high (~200us is normal for tui.class).
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
DIR="$ROOT/lib"
PAGES_DIR="$ROOT/share/demo"
[[ "$1" == -d ]] && {
	PAGES_DIR="$2"
	shift 2
}
(($#)) || {
	sed -n '2,8p' "$0" | sed 's/^# \?//'
	exit 1
}
export XDG_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
cd "$DIR" && source ./tui.sh
PAGES_DIR="$(cd "$PAGES_DIR" && pwd)"
_TUI_ROWS=45
_TUI_COLS=150
_TUI_P_ROW[root]=1
_TUI_P_COL[root]=1
_TUI_P_H[root]=45
_TUI_P_W[root]=150
home="${TUI_PROFILE_HOME:-home}"
tui.load "$PAGES_DIR/$home.xml" >/dev/null 2>&1
_TUI_RUNNING=1
for p in "$@"; do
	f="$PAGES_DIR/$p.xml"
	tui.goto "$f" >/dev/null 2>&1
	tui.goto "$PAGES_DIR/$home.xml" >/dev/null 2>&1
	tui.reset_ui >/dev/null 2>&1
	_TUI_MARKUP_DIR="${f%/*}"
	_TUI_MARKUP_FILE="$f"
	t0=${EPOCHREALTIME/[.,]/}
	tui.cache.valid "$f"
	t1=${EPOCHREALTIME/[.,]/}
	declare -A tot=() cnt=()
	while IFS= read -r cmd; do
		[[ -z "$cmd" ]] && continue
		w="${cmd%% *}"
		w="${w//\'/}"
		a=${EPOCHREALTIME/[.,]/}
		eval "$cmd" >/dev/null 2>&1
		b=${EPOCHREALTIME/[.,]/}
		((tot[$w] += b - a, cnt[$w]++))
	done <<<"${_TUI_CACHE_PAGE[$f]}"
	echo "== $p: cache.valid=$(((t1 - t0) / 1000))ms; replay by call:"
	for k in "${!tot[@]}"; do echo "$((${tot[$k]} / 1000)) $k ${cnt[$k]} ${tot[$k]}"; done | sort -rn | head -6 |
		awk '{printf "   %5d ms  %-30s x%-3s (%d us each)\n",$1,$2,$3,$4/$3}'
	unset tot cnt
done
