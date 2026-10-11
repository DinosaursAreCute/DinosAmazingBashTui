#!/usr/bin/env bash
# md_editor.sh - entry script of the Markdown test app: a full-screen editor with rendered source and a split preview.
#   examples/md-editor/run.sh [FILE.md]      (or:  dabt app run md-editor)
APP_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ -z "${TUI_ROOT:-}" ]] && command -v dabt >/dev/null 2>&1; then
	_dabt="$(readlink -f "$(command -v dabt)")"
	TUI_ROOT="$(cd -P "$(dirname "$_dabt")/.." && pwd -P)"
fi
[[ -r "${TUI_ROOT:-}/lib/tui.sh" ]] || TUI_ROOT="$(cd -P "$APP_DIR/../.." && pwd -P)"
[[ -r "$TUI_ROOT/lib/tui.sh" ]] || {
	echo "md-editor: DABT not found. Install it first." >&2
	exit 1
}

TUI_APP_NAME="${TUI_APP_NAME:-md-editor}"
TUI_APP_TITLE="Markdown test app"
TUI_APP_DESC="Markdown editor with rendered source and split preview"
TUI_APP_ENTRY="md_editor.sh"
source "$TUI_ROOT/lib/tui.sh"

MD_APP_DIR="$APP_DIR"
tui.start_cached "$APP_DIR/config/editor.xml"
