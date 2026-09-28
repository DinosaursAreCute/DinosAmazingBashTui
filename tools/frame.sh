#!/usr/bin/env bash
# frame.sh PAGE [COLSxROWS] [--sgr] - headless render of a markup page to
# plain text, without a real terminal: ANSI stripped by default, kept with
# --sgr. Used for visual checks without a terminal, and to record/compare
# golden frames (see tools/t_golden.sh).
#
#   tools/frame.sh share/demo/components.xml           # 80x24, ANSI stripped
#   tools/frame.sh share/demo/components.xml 120x40     # explicit size
#   tools/frame.sh share/demo/components.xml --sgr      # keep styling
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

_F_PAGE=""
_F_SIZE="80x24"
_F_SGR=0
for _f_arg in "$@"; do
	case "$_f_arg" in
		--sgr) _F_SGR=1 ;;
		[0-9]*x[0-9]*) _F_SIZE="$_f_arg" ;;
		*) _F_PAGE="$_f_arg" ;;
	esac
done
unset _f_arg
if [[ -z "$_F_PAGE" ]]; then
	echo "usage: frame.sh PAGE [COLSxROWS] [--sgr]" >&2
	exit 2
fi

_TUI_COLS="${_F_SIZE%x*}"
_TUI_ROWS="${_F_SIZE#*x}"

# host-independent, same isolation tools/t.sh uses for unit tests: a frame
# must render the same bytes regardless of where/when this runs.
LC_ALL=C
TZ=UTC
export LC_ALL TZ
_F_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dabt-frame.XXXXXX")"
trap 'rm -rf "$_F_ROOT"' EXIT
HOME="$_F_ROOT/home"
TUI_HOME="$_F_ROOT/home/.config/DABT"
XDG_CONFIG_HOME="$_F_ROOT/home/.config"
XDG_DATA_HOME="$_F_ROOT/home/.local/share"
XDG_CACHE_HOME="$_F_ROOT/home/.cache"
XDG_STATE_HOME="$_F_ROOT/home/.local/state"
mkdir -p "$HOME" "$TUI_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
export HOME TUI_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
export TUI_APP_NAME="frame_tool"

# shellcheck source=../lib/tui.sh
source "$REPO/lib/tui.sh"

# Minimal, non-terminal-mutating subset of tui.init: sets up the root pane
# without stty/alt-screen/mouse modes or querying a real tty size, so the
# frame is reproducible regardless of where this runs.
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

_F_OUT="$(
	tui.load "$_F_PAGE" || exit 1
	_tui._layout root
	tui.render
)" || exit 1

if ((_F_SGR)); then
	printf '%s\n' "$_F_OUT"
else
	printf '%s\n' "$_F_OUT" | sed -E $'s/\x1b(\\[[0-9;?]*[a-zA-Z]|\\][^\x07]*(\x07|\x1b\\\\))//g'
fi
