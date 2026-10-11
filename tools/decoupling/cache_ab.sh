#!/usr/bin/env bash
# cache_ab.sh [PAGE...] - runs the same scripted session with every cache on and with TUI_CACHES=off and compares the
# frame after each step (resize and back, theme set / switch / clear, leave the page and return, a widget edit, a pane
# collapse). The two modes must agree byte for byte: a difference is a cache boundary bug, named by the step.
# Default pages: the demo pages that exercise the most. Prints one line per page and step that differs; exit 1 on any.
set -o pipefail # no -u: the sourced lib reads unset variables on purpose
REPO="$(cd -P "$(dirname "$0")/../.." && pwd -P)"
cd "$REPO" || exit 1
PAGES=("$@")
((${#PAGES[@]})) || PAGES=(home components widgets scrolling)
THEME_A="$REPO/share/defaults/themes/dracula.css"
THEME_B="$REPO/share/defaults/themes/nord.css"

session() { # PAGE -> "step<TAB>md5" lines, run in the mode of the environment
	local page="$1"
	# shellcheck source=../bench/lib.sh
	source "$REPO/tools/bench/lib.sh"
	_bench_setup_env >/dev/null 2>&1
	local file="$REPO/share/demo/$page.xml" other="$REPO/share/demo/features.xml"
	_TUI_MARKUP_FILE="$file"
	local step=0
	snap() {         # NAME - layout, render, hash the frame
		tui.paint.reset # the paint diff sends only changed rows by design; reset it so both modes send the whole frame
		_tui._layout root 2>/dev/null
		local frame
		frame=$(tui.render 2>/dev/null)
		[[ -n ${CACHE_AB_DUMP:-} ]] && printf '%s' "$frame" >"$CACHE_AB_DUMP/$1.txt" # CACHE_AB_DUMP=DIR keeps every frame for a diff
		printf '%s\t%s\n' "$1" "$(md5sum <<<"$frame" | cut -c1-12)"
	}
	resize() { # COLS ROWS
		_TUI_COLS=$1 _TUI_ROWS=$2
		_TUI_P_W[root]=$1 _TUI_P_H[root]=$2
		_tui.epoch_bump layout
	}
	resize 100 30
	tui.load "$file" >/dev/null 2>&1
	snap load
	resize 140 40
	snap resize_wide
	resize 100 30
	snap resize_back
	tui.theme.set "$THEME_A" >/dev/null 2>&1
	snap theme_a
	tui.theme.set "$THEME_B" >/dev/null 2>&1
	snap theme_b
	tui.theme.clear >/dev/null 2>&1
	snap theme_cleared
	tui.goto "$other" >/dev/null 2>&1
	snap other_page
	tui.goto "$file" >/dev/null 2>&1
	snap page_again
	local first_label="" id
	for id in "${_TUI_W_ORDER[@]}"; do [[ "${_TUI_W_TYPE[$id]:-}" == label ]] && {
		first_label=$id
		break
	}; done
	if [[ -n $first_label ]]; then
		tui.set "$first_label" "changed text" >/dev/null 2>&1
		snap widget_edit
	fi
	local p
	for p in "${!_TUI_P_COLLAPSIBLE[@]}"; do
		tui.collapse "$p" on >/dev/null 2>&1
		snap "collapse_$p"
		tui.collapse "$p" off >/dev/null 2>&1
		snap "expand_$p"
		break
	done
}

if [[ ${1:-} == --session ]]; then # internal: one page in the current environment
	session "$2"
	exit 0
fi

bad=0
for page in "${PAGES[@]}"; do
	on=$("$0" --session "$page" 2>/dev/null)
	off=$(TUI_CACHES=off "$0" --session "$page" 2>/dev/null)
	if [[ "$on" == "$off" && -n "$on" ]]; then
		printf 'cache_ab: %-12s ok (%d steps)\n' "$page" "$(wc -l <<<"$on")"
	else
		bad=1
		printf 'cache_ab: %-12s DIFFERS\n' "$page"
		diff <(printf '%s\n' "$on") <(printf '%s\n' "$off") | grep '^[<>]' | head -6 | sed 's/^</  on :/; s/^>/  off:/'
	fi
done
exit $bad
