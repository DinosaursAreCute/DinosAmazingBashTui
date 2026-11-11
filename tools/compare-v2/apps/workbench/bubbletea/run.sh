#!/usr/bin/env bash
# run.sh - runs the Bubble Tea side of the workbench benchmark app. Builds the binary first when it is missing or older than the sources
# (run install.sh once to fetch the dependencies).
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/wb-bubbletea"
if [[ ! -x "$BIN" || -n "$(find "$HERE" -maxdepth 1 \( -name '*.go' -o -name go.mod \) -newer "$BIN" -print -quit)" ]]; then
	"$HERE/install.sh" >&2 || exit 1
fi
export WB_DATA="${WB_DATA:-$HERE/../data}"
exec "$BIN" "$@"
