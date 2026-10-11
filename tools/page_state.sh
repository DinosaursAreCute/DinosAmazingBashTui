#!/usr/bin/env bash
# page_state.sh PAGE [COLSxROWS] - headless build of a markup page, then its engine state (every pane and widget
# array, so tab order and placement included; not the raw node store or the refresh signatures, which follow the markup text), one line per array, sorted. Two markup spellings of the same page
# must print identical lines: `diff <(tools/page_state.sh old.xml) <(tools/page_state.sh new.xml)` proves a rewrite
# (nesting widgets in panes, ...) changed nothing the engine sees. Same isolation as tools/frame.sh.
#
#   tools/page_state.sh share/demo/widgets.xml
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
_S_PAGE="${1:-}"
_S_SIZE="${2:-80x24}"
[[ -n "$_S_PAGE" ]] || {
	echo "usage: page_state.sh PAGE [COLSxROWS]" >&2
	exit 2
}

LC_ALL=C
TZ=UTC
export LC_ALL TZ
_S_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dabt-state.XXXXXX")"
trap 'rm -rf "$_S_ROOT"' EXIT
HOME="$_S_ROOT/home"
TUI_HOME="$_S_ROOT/home/.config/DABT"
XDG_CONFIG_HOME="$_S_ROOT/home/.config"
XDG_DATA_HOME="$_S_ROOT/home/.local/share"
XDG_CACHE_HOME="$_S_ROOT/home/.cache"
XDG_STATE_HOME="$_S_ROOT/home/.local/state"
mkdir -p "$HOME" "$TUI_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
export HOME TUI_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
export TUI_APP_NAME="state_tool"

# shellcheck source=../lib/tui.sh
source "$REPO/lib/tui.sh" >/dev/null 2>&1 # loading may print (update notice); only the state below is the output
_TUI_COLS="${_S_SIZE%x*}"
_TUI_ROWS="${_S_SIZE#*x}"
tui.config.apply
_TUI_P_ROW[root]=1
_TUI_P_COL[root]=1
_TUI_P_H[root]=$_TUI_ROWS
_TUI_P_W[root]=$_TUI_COLS
_TUI_P_BORDER[root]="single"
_TUI_P_TITLE[root]=""
_TUI_P_LEAVES=(root)
_TUI_P_ALL=(root)
tui.load "$_S_PAGE" >/dev/null || exit 1
_tui._layout root
declare -p $(compgen -v | grep -E '^_TUI_(W|P)_' | grep -vE '^_TUI_P_(RAW|SIG_[A-Z]+)$') 2>/dev/null | sort
