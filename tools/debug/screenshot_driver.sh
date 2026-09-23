#!/usr/bin/env bash
# screenshot_driver.sh THEME ROWSxCOLS OUTDIR PAGES_DIR PAGE... - headless: visit each page under THEME, dump the raw frame to OUTDIR/PAGE.ans
# Used by screenshots.py (which turns the .ans dumps into PNGs). THEME = "default" or a name from PAGES_DIR/themes/*.css
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
DIR="$ROOT/lib"
theme="$1" size="$2" out="$3" pdir="$4"
shift 4
ROWS="${size%x*}" COLS="${size#*x}"
export XDG_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
stty() { [[ "$1" == size ]] && echo "$ROWS $COLS"; } # headless: no tty, so report the requested size
export TUI_APP_NAME=dabt_demo
mkdir -p "$XDG_CONFIG_HOME/DABT/apps/dabt_demo"
echo "theme=$theme" >"$XDG_CONFIG_HOME/DABT/apps/dabt_demo/settings.conf" # settings page re-syncs its theme on visit
cd "$DIR" && source ./tui.sh
_TUI_ROWS=$ROWS
_TUI_COLS=$COLS
_TUI_P_ROW[root]=1
_TUI_P_COL[root]=1
_TUI_P_H[root]=$ROWS
_TUI_P_W[root]=$COLS
mkdir -p "$out"
tui.load "$pdir/home.xml" >/dev/null 2>&1
_TUI_RUNNING=1
_TUI_ROWS=$ROWS
_TUI_COLS=$COLS
_TUI_P_W[root]=$COLS
_tui._root_h
_TUI_P_ROW[root]=1
_TUI_P_COL[root]=1
[[ "$theme" != default ]] && tui.theme.set "$pdir/themes/$theme.css" >/dev/null 2>&1
SETTLE="${SETTLE:-0.5}"
# settle: let timers / clocks / tui.every jobs run for SETTLE seconds (headless has no main loop, so poll the tick listeners by hand)
_settle() {
	local n=$((${SETTLE%.*} * 10 + ${SETTLE#*.})) i l
	[[ "$SETTLE" == *.* ]] || n=$((SETTLE * 10))
	((n < 1)) && n=1
	for ((i = 0; i < n; i++)); do
		read -rt 0.1 <> <(:)
		[[ -n "${_TUI_TICK_FN:-}" ]] && "$_TUI_TICK_FN"
		for l in "${_TUI_TICK_LISTENERS[@]}"; do "$l"; done
	done
}
_shot() {
	_settle
	tui.render >"$out/$1.ans" 2>/dev/null
}
# spec: PAGE | PAGE@TAB_ID | PAGE@*  (every tab of the page's tab group)
for spec in "$@"; do
	p="${spec%%@*}"
	tab="${spec#*@}"
	[[ "$spec" == *@* ]] || tab=""
	tui.goto "$pdir/$p.xml" >/dev/null 2>&1
	if [[ -z "$tab" ]]; then
		_shot "$p"
		continue
	fi
	tabs=("$tab")
	if [[ "$tab" == "*" ]]; then
		tabs=()
		for t in $(printf '%s\n' "${!_TUI_TAB_GROUP[@]}" | sort -V); do tabs+=("$t"); done
	fi
	for t in "${tabs[@]}"; do
		tui.tabs.activate "$t" >/dev/null 2>&1
		_shot "${p}__${t}"
	done
done
