#!/usr/bin/env bash
# dialog_shots.sh [OUTDIR] [ROWSxCOLS] - headless frames of every dialog/toast state -> OUTDIR/NAME.ans (turn into PNGs with
# python3 tools/debug/screenshots.py's Screen, see dialog_shots.py). Also drives the key handlers, so it doubles as a smoke test.
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
DIR="$ROOT/lib"
OUT="${1:-/tmp/dabt_dialogs}"
SIZE="${2:-30x100}"
ROWS="${SIZE%x*}"
COLS="${SIZE#*x}"
mkdir -p "$OUT"
export XDG_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
stty() { [[ "$1" == size ]] && echo "$ROWS $COLS"; }
cd "$DIR" && source ./tui.sh
_TUI_ROWS=$ROWS
_TUI_COLS=$COLS
_TUI_P_ROW[root]=1
_TUI_P_COL[root]=1
_TUI_P_W[root]=$COLS
_tui._root_h
tui.load "$ROOT/share/demo/home.xml" >/dev/null 2>&1
_TUI_RUNNING=1
LOG=()
yes_fn() { LOG+=("yes_fn $*"); }
no_fn() { LOG+=("no_fn $*"); }
got() { LOG+=("got[$*]"); }
only_digits() { [[ "$1" =~ ^[0-9]+$ ]] || {
	TUI_DIALOG_ERROR="digits only"
	return 1
}; }
shot() { tui.render >"$OUT/$1.ans"; }
tui.render >/dev/null
tui.confirm "Delete all 42 selected files? This cannot be undone." yes_fn no_fn --danger --yes Delete --no Keep
shot confirm_danger
_tui_dialog.key right
_tui_dialog.key left
_tui_dialog.key enter >/dev/null
LOG+=("result=$TUI_DIALOG_RESULT")
tui.confirm "Save changes?" yes_fn no_fn
shot confirm
_tui_dialog.key y >/dev/null
LOG+=("result=$TUI_DIALOG_RESULT")
tui.message "Export finished: 128 rows written." got --title Done
shot message
_tui_dialog.key enter >/dev/null
tui.prompt "Name the new profile:" got --placeholder "e.g. work" --title Rename
shot prompt_empty
for c in h e l l o; do _tui_dialog.key "$c"; done
_tui_dialog.key left
_tui_dialog.key backspace
shot prompt_text
_tui_dialog.key enter >/dev/null
LOG+=("result=$TUI_DIALOG_RESULT")
tui.prompt "Port number:" got --validate only_digits --value 80x
_tui_dialog.key enter
shot prompt_error
_tui_dialog.key backspace
_tui_dialog.key enter >/dev/null
tui.choose "Pick a theme" got default ocean forest sunset light --message "Applies to every page" --selected 2
shot choose
_tui_dialog.key down
_tui_dialog.key enter >/dev/null
tui.notify "Settings saved" success 60
tui.notify "Disk almost full (92%)" warn 60
tui.notify "Could not reach the server: connection refused after 3 retries" error 60
tui.notify "Plain info toast" info 60
shot toasts
tui.confirm "Quit with a toast open?" yes_fn no_fn
shot confirm_with_toasts
_tui_dialog.key esc >/dev/null
tui.notify.clear >/dev/null
printf '%s\n' "${LOG[@]}" >"$OUT/log.txt"
echo "count after clear: $(tui.notify.count)" >>"$OUT/log.txt"
